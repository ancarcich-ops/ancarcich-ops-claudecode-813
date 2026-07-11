//
//  MatchTickerView.swift
//  Sticks
//
//  Slice 48: scrolling header ticker on home match cards — a slim
//  right-to-left marquee of server-provided odds/event strings
//  ("SEUSS.MD 74% · LEADER -1 THRU 9 · 5 WAGERS"), mirroring the web's
//  HeaderTicker. Content is laid twice and the offset animates from 0
//  to −contentWidth on a linear repeat, so the wrap is seamless.
//  Reduced-motion users get a static strip instead.
//

import SwiftUI

struct MatchTickerView: View {
    let items: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentWidth: CGFloat = 0
    @State private var isScrolling = false

    private static let stripHeight: CGFloat = 24
    private static let loopDuration: Double = 28

    /// One full pass of the items, WITH a trailing separator so the
    /// second copy butts up seamlessly during the wrap.
    private var passText: String {
        items.joined(separator: "  ·  ").uppercased() + "  ·  "
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticStrip
            } else {
                marquee
            }
        }
        .frame(height: Self.stripHeight)
        .frame(maxWidth: .infinity)
        .background(Color.sticksPanel2.opacity(0.6))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.sticksHairline).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.sticksHairline).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.joined(separator: ", "))
    }

    // MARK: - Marquee

    private var marquee: some View {
        HStack(spacing: 0) {
            tickerText
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TickerWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
            tickerText
        }
        .fixedSize()
        .offset(x: isScrolling ? -contentWidth : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(edgeFade)
        .onPreferenceChange(TickerWidthKey.self) { width in
            guard width > 0, abs(width - contentWidth) > 0.5 else { return }
            // Restart the loop cleanly whenever the measured width changes.
            isScrolling = false
            contentWidth = width
            withAnimation(
                .linear(duration: Self.loopDuration)
                    .repeatForever(autoreverses: false)
            ) {
                isScrolling = true
            }
        }
    }

    /// Soft-enter on the right, soft-exit on the left — like the web.
    private var edgeFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Static fallback (reduced motion)

    private var staticStrip: some View {
        Text(items.joined(separator: "  ·  ").uppercased())
            .font(SticksFont.mono(10))
            .kerning(0.8)
            .foregroundStyle(Color.sticksMuted)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared text

    private var tickerText: some View {
        Text(passText)
            .font(SticksFont.mono(10))
            .kerning(0.8)
            .foregroundStyle(Color.sticksMuted)
            .lineLimit(1)
            .fixedSize()
    }
}

private struct TickerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
