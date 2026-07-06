//
//  SplashView.swift
//  Sticks
//
//  Full-screen branded splash matching the web app, shown over the root
//  while the token check runs on cold launch. Cream background with a
//  faint accent grid under a radial fade, the three vector clubs popping
//  in staggered (each dropping onto its own baseline with an overshoot
//  spring), the lowercase "sticks" wordmark with a forever-pulsing
//  accent dot fading up next, and the tagline last. ContentView owns
//  the hold (≥2.5s or until data is ready) and the 240ms fade-out.
//  Respects Reduce Motion: entrances are skipped and the finished
//  vector mark renders static.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var clubsVisible: [Bool] = [false, false, false]
    @State private var wordmarkVisible = false
    @State private var taglineVisible = false
    @State private var isPulsing = false

    /// Per-club stagger, matching the web: 0s / 0.13s / 0.26s.
    private static let clubDelays: [Double] = [0, 0.13, 0.26]

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
            clubsVisible = [true, true, true]
            wordmarkVisible = true
            taglineVisible = true
            return
        }
        // All entrances are driven by scoped `.animation(value:)` modifiers
        // with their own delays — one state flip kicks off the sequence.
        clubsVisible = [true, true, true]
        wordmarkVisible = true
        taglineVisible = true
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

    /// The vector clubs, each popping in with its own delay: an 0.82s
    /// overshoot spring rising 18pt from 82% scale anchored at that
    /// club's own bottom-center, while the fill fades in over the first
    /// ~60% of the pop.
    private var mark: some View {
        ZStack {
            ForEach(SticksClub.allCases) { club in
                clubView(club)
            }
        }
        .frame(width: 120, height: 120)
        .accessibilityHidden(true)
    }

    private func clubView(_ club: SticksClub) -> some View {
        let index = club.rawValue
        let visible = clubsVisible[index]
        let delay = Self.clubDelays[index]

        return SticksClubShape(club: club)
            .fill(Color.sticksGreen)
            .opacity(visible ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.5).delay(delay),
                value: visible
            )
            .scaleEffect(visible ? 1 : 0.82, anchor: club.baselineAnchor)
            .offset(y: visible ? 0 : 18)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.82, bounce: 0.38).delay(delay),
                value: visible
            )
    }

    // MARK: - Wordmark

    /// Fades up over 0.6s starting at 0.64s; the dot's pulse starts
    /// with it.
    private var wordmark: some View {
        HStack(alignment: .bottom, spacing: 7) {
            Text("sticks")
                .font(SticksFont.display(56, weight: .bold))
                .tracking(-1.5)
                .foregroundStyle(Color.sticksInk)
            pulsingDot
                .padding(.bottom, 15)
        }
        .opacity(wordmarkVisible ? 1 : 0)
        .offset(y: wordmarkVisible ? 0 : 8)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.64),
            value: wordmarkVisible
        )
        .accessibilityLabel("Sticks")
    }

    /// 10pt accent dot with a soft ring expanding to ~12pt+ and fading,
    /// on a forever 2.4s cycle starting with the wordmark. Static under
    /// Reduce Motion.
    private var pulsingDot: some View {
        ZStack {
            Circle()
                .stroke(Color.sticksGreen.opacity(isPulsing ? 0 : 0.55), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.5 : 1)
                .animation(
                    .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.64),
                    value: isPulsing
                )
            Circle()
                .fill(Color.sticksGreen)
                .frame(width: 10, height: 10)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Tagline

    /// Fades up starting at 1.02s.
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
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.6).delay(1.02),
            value: taglineVisible
        )
    }
}

#Preview {
    SplashView()
}
