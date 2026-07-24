//
//  FlyoverService.swift
//  Sticks
//
//  Owns ONE long-lived WKWebView for the 3D hole flyover so the heavy
//  Google 3D Tiles page survives camera-mode switches and can be
//  preloaded before the user ever taps "3D":
//
//  - `prepare(url:)` is called for the displayed hole the moment the GPS
//    screen shows it (any mode) — tiles stream in the background while
//    the golfer is still on the satellite map, so 3D opens warm.
//  - Switching 3D → HOLE → 3D re-attaches the same WebView instantly
//    instead of reloading the page from zero.
//  - Real failure handling: navigation errors and WebContent process
//    crashes (frequent with WebGL-heavy pages) flip `state` to .failed,
//    and a watchdog catches loads that silently hang.
//  - Slice 59: the embed itself now reports status via the
//    `sticksFlyover` message handler — "ready" fires when the FIRST
//    MESH TILE actually paints (not merely when the HTML loads), and
//    "stalled"/"error" surface silent tile failures within ~6s so the
//    GPS screen can drop to the 2D map instead of spinning.
//  - Flyover fix: "stalled" is now SOFT — the embed fires it after only
//    6s with zero tiles painted, which slow networks / cold WebViews hit
//    routinely, and "ready" can still arrive right after it. Treating it
//    as fatal made 3D fail on every first open for many users. Only a
//    real "error" (e.g. Google rejected the tile request) or the 30s
//    watchdog fails the load now. A `sticksFlyoverLog` handler + console
//    capture script also surface the embed's JS errors in the app logs,
//    so silent failures are diagnosable from `rork-agent logs runtime`.
//  - WebGL probe: the embed is pure WebGL (deck.gl + Google 3D Tiles).
//    Environments whose WebView can't create a WebGL2 context (notably
//    the cloud simulator, where IOSurface access is sandboxed away)
//    render the empty sky gradient forever — no tiles, no error, no
//    console output. An injected probe now reports WebGL support the
//    moment the page loads: unsupported → `webglUnsupported` latches,
//    the load fails IMMEDIATELY (no 25s spinner), and the GPS screen
//    grays the 3D segment out for the rest of the session. Real devices
//    are unaffected. Logging also moved from os.log to NSLog so the
//    diagnostics actually appear in `rork-agent logs runtime`.
//

import WebKit
import Observation

@Observable
final class FlyoverService: NSObject {
    static let shared = FlyoverService()

    enum LoadState {
        case idle
        /// Page request in flight.
        case loading
        /// HTML finished loading; waiting on the embed's own "ready"
        /// (first mesh tile painted). Tiles can still silently stall here.
        case pageLoaded
        /// The embed reported "ready" — the 3D scene is actually visible.
        case ready
        case failed
    }

    private(set) var state: LoadState = .idle
    private(set) var currentURL: URL?

    /// Latched true when the WebView reports it cannot create a WebGL2
    /// context (e.g. the cloud simulator's sandbox blocks IOSurface).
    /// The flyover can never work in that environment, so the GPS
    /// screen disables the 3D segment instead of spinning and failing.
    private(set) var webglUnsupported = false

    /// NSLog (not os.log Logger) so lines show up in the captured
    /// runtime logs — Logger output is invisible to the log pipe.
    private static func log(_ message: String) {
        NSLog("[Flyover] %@", message)
    }

    let webView: WKWebView

    /// Bumped on every load; the watchdog only fails the generation it
    /// was started for, so a hole switch can't be failed by a stale timer.
    private var generation = 0
    private var watchdog: Task<Void, Never>?

    /// Loads that show no life after this long surface the RETRY state.
    private static let watchdogSeconds: Double = 30

    override private init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: .zero, configuration: config)
        // Transparent so the native loading treatment (dark backdrop +
        // spinner) shows through until the page paints its own scrim.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        super.init()
        webView.navigationDelegate = self
        // The production embed posts real status updates —
        // { status: "ready" | "stalled" | "error" } — through this
        // handler. The content controller retains the service; that's
        // intentional, it's a process-lifetime singleton.
        let controller = webView.configuration.userContentController
        controller.add(self, name: "sticksFlyover")
        // Diagnostics: pipe the embed's JS errors and console.error output
        // into the native log so "3D didn't load" is never a black box.
        controller.add(self, name: "sticksFlyoverLog")
        controller.addUserScript(WKUserScript(
            source: Self.consoleCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.webglProbeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
    }

    /// Forwards window errors, unhandled promise rejections, and
    /// console.error lines from the embed to `sticksFlyoverLog`.
    private static let consoleCaptureScript = """
    (function () {
      function post(line) {
        try {
          window.webkit.messageHandlers.sticksFlyoverLog.postMessage({ line: String(line).slice(0, 500) });
        } catch (_) {}
      }
      window.addEventListener('error', function (e) {
        post('window.onerror: ' + (e.message || 'unknown') + ' @ ' + (e.filename || '?') + ':' + (e.lineno || 0));
      });
      window.addEventListener('unhandledrejection', function (e) {
        post('unhandledrejection: ' + (e.reason && (e.reason.message || e.reason)));
      });
      var origError = console.error;
      console.error = function () {
        post('console.error: ' + Array.prototype.map.call(arguments, String).join(' '));
        return origError.apply(console, arguments);
      };
    })();
    """

    /// Reports whether this WebView can actually create a WebGL context.
    /// The flyover is 100% WebGL — without it the page paints only its
    /// CSS sky gradient and never errors, so the app must detect the
    /// capability itself. Posts through the same status channel:
    /// "webgl-ok" / "webgl-unavailable".
    private static let webglProbeScript = """
    (function () {
      var status = 'webgl-unavailable';
      try {
        var canvas = document.createElement('canvas');
        var gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
        if (gl) {
          status = 'webgl-ok';
          try {
            var info = gl.getExtension('WEBGL_debug_renderer_info');
            var renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
            window.webkit.messageHandlers.sticksFlyoverLog.postMessage({ line: 'webgl renderer: ' + renderer });
          } catch (_) {}
          var lose = gl.getExtension('WEBGL_lose_context');
          if (lose) { lose.loseContext(); }
        }
      } catch (_) {}
      try {
        window.webkit.messageHandlers.sticksFlyover.postMessage({ status: status });
      } catch (_) {}
    })();
    """

    /// Points the flyover at `url`. No-op when that page is already
    /// loading/loaded (so re-entering 3D mode never restarts a warm
    /// scene); a previously failed load is retried.
    func prepare(url: URL) {
        guard !webglUnsupported else { return }
        guard url != currentURL || state == .failed || state == .idle else { return }
        currentURL = url
        load(url)
    }

    /// Reloads the current hole's flyover after a failure.
    func retry() {
        guard let currentURL else { return }
        load(currentURL)
    }

    private func load(_ url: URL) {
        generation += 1
        state = .loading
        Self.log("Loading flyover: \(url.absoluteString)")
        webView.stopLoading()
        webView.load(URLRequest(url: url, timeoutInterval: 30))
        startWatchdog(generation: generation)
    }

    private func startWatchdog(generation: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchdogSeconds))
            guard !Task.isCancelled, let self,
                  self.generation == generation,
                  self.state == .loading || self.state == .pageLoaded else { return }
            Self.log("Watchdog fired after \(Self.watchdogSeconds)s (state \(String(describing: self.state))) — marking failed")
            self.state = .failed
        }
    }

    private func handleFinished() {
        // The HTML arriving is NOT "ready" — Google's tiles can still
        // silently stall. Wait for the embed's own status message; the
        // watchdog stays armed in case the page's JS never runs.
        Self.log("Page HTML finished loading")
        if state == .loading { state = .pageLoaded }
    }

    /// Status posted by the embed's JS (slice 59) or the injected
    /// WebGL probe.
    private func handleEmbedStatus(_ status: String) {
        Self.log("Embed status: \(status)")
        switch status {
        case "ready":
            watchdog?.cancel()
            state = .ready
        case "error":
            guard state != .ready else { return }
            watchdog?.cancel()
            state = .failed
        case "webgl-unavailable":
            // This WebView cannot render the flyover AT ALL (typical in
            // the cloud simulator, whose sandbox denies the IOSurface
            // access WebGL compositing needs). Latch it: fail now, stop
            // retrying, and let the GPS screen gray out the 3D segment.
            Self.log("WebGL unavailable in this environment — disabling 3D flyover")
            webglUnsupported = true
            watchdog?.cancel()
            state = .failed
        case "webgl-ok":
            Self.log("WebGL context OK — tiles should stream")
        case "stalled":
            // SOFT signal: the embed fires this after just 6s with no tile
            // painted — routine on slow networks and cold WebViews, and
            // "ready" often still arrives moments later. Keep waiting; the
            // 30s watchdog remains armed for loads that truly die.
            break
        default:
            break
        }
    }

    /// Diagnostic line forwarded from the embed's JS console.
    private func handleEmbedLog(_ line: String) {
        Self.log("[embed] \(line)")
    }

    private func handleFailure(_ error: Error) {
        // stopLoading()/superseded navigations report NSURLErrorCancelled
        // — not a real failure, the replacement load is already running.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        Self.log("Navigation failed: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
        watchdog?.cancel()
        state = .failed
    }

    /// WebGL-heavy pages can get their WebContent process killed by the
    /// system (the classic "spinner forever" case) — reload immediately.
    private func handleProcessTerminated() {
        Self.log("WebContent process terminated — reloading")
        guard currentURL != nil else { return }
        retry()
    }
}

extension FlyoverService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            FlyoverService.shared.handleFinished()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        Task { @MainActor in
            FlyoverService.shared.handleFailure(nsError)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        Task { @MainActor in
            FlyoverService.shared.handleFailure(nsError)
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            FlyoverService.shared.handleProcessTerminated()
        }
    }
}

extension FlyoverService: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body as? [String: Any]
        switch message.name {
        case "sticksFlyover":
            guard let status = body?["status"] as? String else { return }
            Task { @MainActor in
                FlyoverService.shared.handleEmbedStatus(status)
            }
        case "sticksFlyoverLog":
            guard let line = body?["line"] as? String else { return }
            Task { @MainActor in
                FlyoverService.shared.handleEmbedLog(line)
            }
        default:
            break
        }
    }
}
