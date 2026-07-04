//
//  SplashView.swift
//  Sticks
//
//  Full-screen branded splash matching the web app, shown over the root
//  while the token check runs on cold launch. Cream background with a
//  faint accent grid under a radial fade, the clubs mark popping in with
//  an overshoot spring, the lowercase "sticks" wordmark with a forever-
//  pulsing accent dot, and the tagline fading up last. ContentView owns
//  the hold (≥2.5s or until data is ready) and the 240ms fade-out.
//  Respects Reduce Motion: entrances are skipped and the finished
//  layout renders static.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markVisible = false
    @State private var taglineVisible = false
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            accentGrid

            VStack(spacing: 26) {
                mark
                wordmark
                tagline
            }
            .offset(y: -24)
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !reduceMotion else {
            // Reduce Motion: finished layout, static — no entrances, no pulse.
            markVisible = true
            taglineVisible = true
            return
        }
        // Overshoot spring: 0.82s, rising 18pt from 82% scale.
        withAnimation(.spring(duration: 0.82, bounce: 0.38)) {
            markVisible = true
        }
        // Tagline fades up 0.6s after the wordmark.
        withAnimation(.easeOut(duration: 0.6).delay(0.6)) {
            taglineVisible = true
        }
        isPulsing = true
    }

    // MARK: - Background grid

    /// 32pt squares, accent at 5%, masked by a radial fade centered
    /// slightly above center.
    private var accentGrid: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += 32
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += 32
            }
            context.stroke(path, with: .color(Color.sticksGreen.opacity(0.05)), lineWidth: 1)
        }
        .mask(
            RadialGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.7), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 30,
                endRadius: 360
            )
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Mark

    private var mark: some View {
        Image("SticksMark")
            .resizable()
            .scaledToFit()
            .frame(width: 135, height: 135)
            .clipShape(.rect(cornerRadius: 30))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            .scaleEffect(markVisible ? 1 : 0.82)
            .offset(y: markVisible ? 0 : 18)
            .opacity(markVisible ? 1 : 0)
            .accessibilityHidden(true)
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        HStack(alignment: .bottom, spacing: 7) {
            Text("sticks")
                .font(SticksFont.display(56, weight: .bold))
                .tracking(-1.5)
                .foregroundStyle(Color.sticksInk)
            pulsingDot
                .padding(.bottom, 15)
        }
        .scaleEffect(markVisible ? 1 : 0.94)
        .opacity(markVisible ? 1 : 0)
        .accessibilityLabel("Sticks")
    }

    /// 10pt accent dot with a soft ring expanding to ~12pt+ and fading,
    /// on a forever 2.4s cycle. Static under Reduce Motion.
    private var pulsingDot: some View {
        ZStack {
            Circle()
                .stroke(Color.sticksGreen.opacity(isPulsing ? 0 : 0.55), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.5 : 1)
                .animation(
                    .easeOut(duration: 2.4).repeatForever(autoreverses: false),
                    value: isPulsing
                )
            Circle()
                .fill(Color.sticksGreen)
                .frame(width: 10, height: 10)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Tagline

    private var tagline: some View {
        HStack(spacing: 5) {
            Text("All your games.")
                .foregroundStyle(Color.sticksInk)
            Text("One app.")
                .foregroundStyle(Color.sticksGreen)
        }
        .font(SticksFont.sans(15, weight: .medium))
        .opacity(taglineVisible ? 1 : 0)
        .offset(y: taglineVisible ? 0 : 8)
    }
}

#Preview {
    SplashView()
}
