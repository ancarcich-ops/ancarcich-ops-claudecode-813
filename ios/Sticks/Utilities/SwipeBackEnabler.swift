//
//  SwipeBackEnabler.swift
//  Sticks
//
//  Restores the native left-edge swipe-back gesture on pushed screens
//  that hide the system back button for a custom "← BACK" chip —
//  `.navigationBarBackButtonHidden(true)` silently disables
//  UINavigationController's interactivePopGestureRecognizer, so this
//  re-attaches it with a delegate that only allows the gesture when
//  there is somewhere to pop back to.
//

import SwiftUI
import UIKit

extension View {
    /// Re-enables the iOS edge swipe-to-go-back gesture on screens that
    /// use `.navigationBarBackButtonHidden(true)`. Apply after the
    /// navigation modifiers on the pushed screen's root view.
    func swipeBackEnabled() -> some View {
        background(SwipeBackEnablerRepresentable())
    }
}

private struct SwipeBackEnablerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackEnablerController {
        SwipeBackEnablerController()
    }

    func updateUIViewController(_ controller: SwipeBackEnablerController, context: Context) {}
}

private final class SwipeBackEnablerController: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        attachToPopGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The navigation controller may not be resolvable in didMove —
        // re-attach once the screen is actually on screen.
        attachToPopGesture()
    }

    private func attachToPopGesture() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        gesture.delegate = self
        gesture.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Never begin on the stack root — swiping there would freeze the UI.
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}
