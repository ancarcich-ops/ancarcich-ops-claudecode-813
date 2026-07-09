//
//  HoleFlyoverWebView.swift
//  Sticks
//
//  Slice 30: WKWebView wrapper for the photorealistic 3D hole flyover
//  (the production web embed at /embed/hole-flyover — Google 3D Tiles
//  with a cinematic tee→green intro). Purely the remote page: no native
//  map SDKs, no downloads. The user can pan/zoom the mesh with gestures;
//  all native overlays render on top of it.
//

import SwiftUI
import WebKit

struct HoleFlyoverWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparent so the native loading treatment (dark backdrop +
        // spinner) shows through until the page paints its own scrim.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.lastURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the target URL actually changed (hole switch)
        // — SwiftUI calls this on unrelated state updates too.
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var lastURL: URL?
    }
}
