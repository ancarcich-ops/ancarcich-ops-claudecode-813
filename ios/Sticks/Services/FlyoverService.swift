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
        webView.configuration.userContentController.add(self, name: "sticksFlyover")
    }

    /// Points the flyover at `url`. No-op when that page is already
    /// loading/loaded (so re-entering 3D mode never restarts a warm
    /// scene); a previously failed load is retried.
    func prepare(url: URL) {
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
            self.state = .failed
        }
    }

    private func handleFinished() {
        // The HTML arriving is NOT "ready" — Google's tiles can still
        // silently stall. Wait for the embed's own status message; the
        // watchdog stays armed in case the page's JS never runs.
        if state == .loading { state = .pageLoaded }
    }

    /// Status posted by the embed's JS (slice 59).
    private func handleEmbedStatus(_ status: String) {
        switch status {
        case "ready":
            watchdog?.cancel()
            state = .ready
        case "stalled", "error":
            guard state != .ready else { return }
            watchdog?.cancel()
            state = .failed
        default:
            break
        }
    }

    private func handleFailure(_ error: Error) {
        // stopLoading()/superseded navigations report NSURLErrorCancelled
        // — not a real failure, the replacement load is already running.
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        watchdog?.cancel()
        state = .failed
    }

    /// WebGL-heavy pages can get their WebContent process killed by the
    /// system (the classic "spinner forever" case) — reload immediately.
    private func handleProcessTerminated() {
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
        guard message.name == "sticksFlyover",
              let status = (message.body as? [String: Any])?["status"] as? String else { return }
        Task { @MainActor in
            FlyoverService.shared.handleEmbedStatus(status)
        }
    }
}
