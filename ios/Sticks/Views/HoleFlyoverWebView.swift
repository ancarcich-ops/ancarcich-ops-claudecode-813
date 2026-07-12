//
//  HoleFlyoverWebView.swift
//  Sticks
//
//  Hosts FlyoverService's single long-lived WKWebView (the production
//  web embed at /embed/hole-flyover — Google 3D Tiles with a cinematic
//  tee→green intro). The WebView is preloaded and kept alive by the
//  service, so this view only re-parents it: entering 3D mode attaches
//  an already-streaming (often already-finished) scene instead of
//  starting a cold page load. The user can pan/zoom the mesh with
//  gestures; all native overlays render on top of it.
//

import SwiftUI
import WebKit

struct HoleFlyoverWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        attachWebView(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        attachWebView(to: container)
    }

    /// Re-parents the shared WebView into `container` (a no-op when it's
    /// already there). The service keeps the WebView alive when SwiftUI
    /// tears this view down, preserving the loaded scene.
    private func attachWebView(to container: UIView) {
        let webView = FlyoverService.shared.webView
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}
