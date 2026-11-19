//
//  TutorialCenter.swift
//  Sticks
//
//  The in-app "how to" coach marks: a dimmed screen with a spotlight
//  cut around one control and a small card explaining it (step N/M,
//  Skip / Back / Next). One tour per page, shown the first time that
//  page opens; the tab tour runs right after the welcome flow. Settings
//  → REPLAY TUTORIALS clears every flag and starts the tab tour again.
//
//  How it fits together:
//    - Views tag spotlight targets with `.tutorialAnchor("id")`. The
//      modifier reports the view's on-screen frame here.
//    - Screens ask for their tour with `request(_:)`. Requests queue;
//      one tour runs at a time and only on the surface it was asked
//      from (the create wizard is a full-screen cover above the tabs,
//      so a tab tour waits until the cover closes).
//    - The overlay lives in its own window above the app, so it dims
//      the tab bar, headers and covers alike, and blocks touches while
//      it is up.
//    - Steps whose target isn't on screen (an empty feed has no first
//      card) are dropped when the tour starts. A step can ask its page
//      to scroll the target into view (`.tutorialScrollHost()`).
//

import SwiftUI
import UIKit

// MARK: - Model

enum TutorialID: String, CaseIterable {
    case tabs
    case groups
    case stats
    case settings
    case match
    case createRound
    case createSideGames

    var storageKey: String { "sticks.tutorial.\(rawValue).v1" }
}

struct TutorialStep: Identifiable, Equatable {
    let id: String
    /// The `.tutorialAnchor` id to spotlight; nil = centered card.
    let target: String?
    let title: String
    let body: String
    /// SF Symbol shown in the card's badge.
    let icon: String
    /// Ask the page's scroll view to bring the target into view first.
    let scrolls: Bool

    init(
        target: String?,
        title: String,
        body: String,
        icon: String,
        scrolls: Bool = false
    ) {
        self.id = target ?? "intro.\(title)"
        self.target = target
        self.title = title
        self.body = body
        self.icon = icon
        self.scrolls = scrolls
    }
}

struct TutorialScrollRequest: Equatable {
    let nonce = UUID()
    let target: String
}

// MARK: - Center

@MainActor
@Observable
final class TutorialCenter {
    static let shared = TutorialCenter()

    /// Live on-screen frames of every tagged view, in window space.
    /// Anchors report on every scroll frame, so the raw store is NOT
    /// observed; only while a tour is on screen does a change bump
    /// `frameRevision`, which the overlay observes through `frames`.
    @ObservationIgnored private var frameStore: [String: CGRect] = [:]
    private var frameRevision = 0

    var frames: [String: CGRect] {
        _ = frameRevision
        return frameStore
    }

    /// The tour on screen, with only the steps whose targets exist.
    private(set) var activeID: TutorialID?
    private(set) var steps: [TutorialStep] = []
    private(set) var stepIndex = 0
    /// Flipped just before the overlay fades out, so it can animate.
    private(set) var isClosing = false

    /// Pages listen and scroll the named target into view.
    private(set) var scrollRequest: TutorialScrollRequest?

    /// While true nothing starts (the welcome flow is up).
    var isSuspended = false {
        didSet { if oldValue != isSuspended { pump() } }
    }

    /// 0 = the tab screens; each full-screen cover adds one.
    private(set) var surfaceDepth = 0

    private struct Pending {
        let id: TutorialID
        let depth: Int
        let isRelevant: () -> Bool
        let steps: [TutorialStep]
    }

    private var queue: [Pending] = []
    private var isStarting = false

    private init() {}

    // MARK: Persistence

    func hasSeen(_ id: TutorialID) -> Bool {
        UserDefaults.standard.bool(forKey: id.storageKey)
    }

    private func markSeen(_ id: TutorialID) {
        UserDefaults.standard.set(true, forKey: id.storageKey)
    }

    /// Settings' replay: every page shows its tour again on next visit.
    func resetAll() {
        for id in TutorialID.allCases {
            UserDefaults.standard.removeObject(forKey: id.storageKey)
        }
        queue.removeAll()
    }

    // MARK: Frames

    func setFrame(_ frame: CGRect?, for id: String) {
        let changed: Bool
        if let frame, frame.width > 0, frame.height > 0 {
            changed = frameStore[id] != frame
            if changed { frameStore[id] = frame }
        } else {
            changed = frameStore[id] != nil
            if changed { frameStore[id] = nil }
        }
        if changed, activeID != nil { frameRevision &+= 1 }
    }

    // MARK: Surfaces

    func pushSurface() {
        surfaceDepth += 1
    }

    func popSurface() {
        surfaceDepth = max(0, surfaceDepth - 1)
        // A tour asked for inside the cover can't run any more.
        queue.removeAll { $0.depth > surfaceDepth }
        pump()
    }

    // MARK: Requests

    /// Queue `id` unless it has been seen. `isRelevant` is re-checked
    /// right before it starts (e.g. "is the Stats tab still selected").
    func request(
        _ id: TutorialID,
        isRelevant: @escaping () -> Bool = { true },
        steps: [TutorialStep]
    ) {
        guard !hasSeen(id),
              activeID != id,
              !queue.contains(where: { $0.id == id })
        else { return }
        queue.append(Pending(id: id, depth: surfaceDepth, isRelevant: isRelevant, steps: steps))
        pump()
    }

    private func pump() {
        guard activeID == nil, !isStarting, !isSuspended else { return }
        guard let index = queue.firstIndex(where: { $0.depth == surfaceDepth }) else { return }
        let pending = queue.remove(at: index)
        isStarting = true
        Task { await start(pending) }
    }

    /// Lets the page settle (data loads, push animations), then keeps
    /// only steps whose targets are on screen.
    private func start(_ pending: Pending) async {
        defer {
            isStarting = false
            pump()
        }

        let targeted = pending.steps.compactMap(\.target)
        // Up to ~4s for the first target to appear (a feed still loading).
        for _ in 0 ..< 16 {
            try? await Task.sleep(for: .milliseconds(250))
            if targeted.isEmpty || targeted.contains(where: { frames[$0] != nil }) { break }
        }
        // One more beat so push/slide animations finish moving things.
        try? await Task.sleep(for: .milliseconds(350))

        guard !hasSeen(pending.id) else { return }
        // A cover opened (or the welcome came back) while we waited —
        // park it until that surface is on top again.
        guard !isSuspended, pending.depth == surfaceDepth else {
            if pending.depth <= surfaceDepth { queue.append(pending) }
            return
        }
        guard pending.isRelevant() else { return }

        let available = pending.steps.filter { step in
            guard let target = step.target else { return true }
            return frames[target] != nil
        }
        // Nothing to point at (an error state, say) — try another visit.
        guard available.contains(where: { $0.target != nil }) || targeted.isEmpty else { return }

        steps = available
        stepIndex = 0
        frameRevision &+= 1
        isClosing = false
        activeID = pending.id
        requestScrollIfNeeded()
        TutorialWindowController.shared.show()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Navigation

    var currentStep: TutorialStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    func next() {
        guard activeID != nil else { return }
        if stepIndex + 1 < steps.count {
            UISelectionFeedbackGenerator().selectionChanged()
            stepIndex += 1
            requestScrollIfNeeded()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finish()
        }
    }

    func back() {
        guard activeID != nil, stepIndex > 0 else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        stepIndex -= 1
        requestScrollIfNeeded()
    }

    func skip() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        finish()
    }

    private func finish() {
        guard let id = activeID, !isClosing else { return }
        markSeen(id)
        isClosing = true
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            TutorialWindowController.shared.hide()
            activeID = nil
            steps = []
            stepIndex = 0
            isClosing = false
            scrollRequest = nil
            pump()
        }
    }

    private func requestScrollIfNeeded() {
        guard let step = currentStep, step.scrolls, let target = step.target else { return }
        scrollRequest = TutorialScrollRequest(target: target)
    }
}

// MARK: - Overlay window

/// Hosts the overlay in a window above the app so it covers the tab
/// bar and full-screen covers too. Exists only while a tour runs.
@MainActor
final class TutorialWindowController {
    static let shared = TutorialWindowController()

    private var window: UIWindow?

    private init() {}

    func show() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear

        let host = UIHostingController(rootView: TutorialOverlayView())
        host.view.backgroundColor = .clear
        // VoiceOver stays inside the card while the tour is up.
        host.view.accessibilityViewIsModal = true
        window.rootViewController = host
        window.isHidden = false
        self.window = window

        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func hide() {
        window?.isHidden = true
        window = nil
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }
}

// MARK: - View modifiers

private struct TutorialAnchorModifier: ViewModifier {
    let id: String

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                TutorialCenter.shared.setFrame(frame, for: id)
            }
            .onDisappear {
                TutorialCenter.shared.setFrame(nil, for: id)
            }
    }
}

private struct TutorialScrollHostModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: TutorialCenter.shared.scrollRequest) { _, request in
                    guard let request else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                        proxy.scrollTo(request.target, anchor: .center)
                    }
                }
        }
    }
}

/// Counts a full-screen cover as its own surface, so tours asked for
/// underneath wait until it closes.
private struct TutorialSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { TutorialCenter.shared.pushSurface() }
            .onDisappear { TutorialCenter.shared.popSurface() }
    }
}

extension View {
    /// Tags this view as a spotlight target. `scrollable` also gives it
    /// a scroll id so a tour step can bring it on screen.
    /// nil leaves the view untagged (e.g. every card but the first).
    @ViewBuilder
    func tutorialAnchor(_ id: String?, scrollable: Bool = false) -> some View {
        if let id, scrollable {
            modifier(TutorialAnchorModifier(id: id)).id(id)
        } else if let id {
            modifier(TutorialAnchorModifier(id: id))
        } else {
            self
        }
    }

    /// Put on a ScrollView whose content holds scrollable anchors.
    func tutorialScrollHost() -> some View {
        modifier(TutorialScrollHostModifier())
    }

    /// Put on the root of a full-screen cover.
    func tutorialSurface() -> some View {
        modifier(TutorialSurfaceModifier())
    }
}

/// A tiny reference flag a screen flips on appear/disappear, so a tour
/// queued from it can check later whether the screen is still up.
@MainActor
final class TutorialPresence {
    var isVisible = false
}
