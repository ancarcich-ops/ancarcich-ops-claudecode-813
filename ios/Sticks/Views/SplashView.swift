//
//  SplashView.swift
//  Sticks
//
//  Full-screen branded splash matching the web app, shown over the root
//  while the token check runs on cold launch. Cream background with a
//  faint accent grid under a radial fade, the three vector clubs popping
//  in staggered (each dropping onto its own baseline with an overshoot
//  spring), the "Sticks" wordmark with a forever-pulsing
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
    @State private var pulseStart: Date?

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
        pulseStart = Date()
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
            Text("Sticks")
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

    /// The pulse cycle length; two rings ride the same cycle, the second
    /// phase-offset by half of it, so a new ripple begins as the previous
    /// one finishes fading — no dead gap.
    private static let pulseCycle: Double = 2.4

    /// The pulse waits for the wordmark's fade-up before rippling.
    private static let pulseDelay: Double = 0.64

    /// 10pt solid accent dot with a concentric aura rippling outward:
    /// soft blurred rings expanding from the dot's size to ~3.5× while
    /// fading from 0.5 to 0 on an ease-out 2.4s cycle, forever. Built as
    /// an overlay on the dot itself so the rings share its exact center.
    /// Static solid dot only under Reduce Motion.
    private var pulsingDot: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 10, height: 10)
            .overlay(alignment: .center) {
                if let pulseStart, !reduceMotion {
                    auraRipple(since: pulseStart)
                }
            }
            .accessibilityHidden(true)
    }

    /// Two phase-offset rings driven off the shared clock, radiating
    /// away from the dot behind it.
    private func auraRipple(since start: Date) -> some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start) - Self.pulseDelay
            ZStack {
                auraRing(elapsed: elapsed)
                auraRing(elapsed: elapsed - Self.pulseCycle / 2)
            }
        }
        .allowsHitTesting(false)
    }

    /// One ring of the ripple at the given point in its own timeline.
    /// Before its start it stays hidden; afterwards it loops the 2.4s
    /// expand-and-fade with an ease-out curve.
    @ViewBuilder
    private func auraRing(elapsed: TimeInterval) -> some View {
        if elapsed >= 0 {
            let linear = elapsed.truncatingRemainder(dividingBy: Self.pulseCycle) / Self.pulseCycle
            // Ease-out cubic: fast expansion at the start, gentle finish.
            let progress = 1 - pow(1 - linear, 3)
            Circle()
                .stroke(Color.sticksGreen, lineWidth: 2)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + 2.5 * progress)
                .opacity(0.5 * (1 - progress))
                .blur(radius: 2.5)
        }
    }

    // MARK: - Tagline

    /// Fades up starting at 1.02s.
    private var tagline: some View {
        VStack(spacing: 2) {
            Text("All your games")
                .foregroundStyle(Color.sticksInk)
            Text("One app")
                .foregroundStyle(Color.sticksGreen)
        }
        .font(SticksFont.sans(15, weight: .medium))
        .multilineTextAlignment(.center)
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
