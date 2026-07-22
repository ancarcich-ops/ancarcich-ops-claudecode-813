//
//  ScoreCelebrationView.swift
//  SticksWatch
//
//  Birdie-or-better celebration for the score sheet: an expanding ring
//  burst + particle flourish in green (birdie) or gold (eagle+), with
//  the par-relative label landing large. Presentation-only — no data.
//

import SwiftUI

struct ScoreCelebrationView: View {
    /// Particle/ring tint — bright green for birdie, gold for eagle+.
    let accent: Color
    /// Par-relative label that lands large ("BIRDIE", "EAGLE", "ACE"…).
    let label: String

    @State private var burst = false

    /// Fixed particle fan — precomputed so the layout is stable across
    /// re-renders; only `burst` animates.
    private static let particles: [Particle] = (0..<14).map { index in
        let angle = Double(index) / 14 * 2 * .pi
        return Particle(
            angle: angle,
            distance: 62 + Double((index * 13) % 22),
            size: 3 + Double((index * 7) % 4)
        )
    }

    struct Particle {
        let angle: Double
        let distance: Double
        let size: Double
    }

    var body: some View {
        ZStack {
            // Expanding rings.
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(accent.opacity(0.85 - Double(ring) * 0.2), lineWidth: 2.5 - Double(ring) * 0.5)
                    .frame(width: 44, height: 44)
                    .scaleEffect(burst ? 2.4 + Double(ring) * 0.7 : 0.3)
                    .opacity(burst ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 0.9).delay(Double(ring) * 0.12),
                        value: burst
                    )
            }

            // Particle flourish.
            ForEach(Array(Self.particles.enumerated()), id: \.offset) { index, particle in
                Circle()
                    .fill(accent)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: burst ? cos(particle.angle) * particle.distance : 0,
                        y: burst ? sin(particle.angle) * particle.distance : 0
                    )
                    .opacity(burst ? 0 : 1)
                    .animation(
                        .easeOut(duration: 0.8).delay(Double(index % 5) * 0.03),
                        value: burst
                    )
            }

            // The relative label lands large.
            Text(label)
                .font(.system(size: 24, weight: .heavy))
                .kerning(2.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .scaleEffect(burst ? 1 : 0.4)
                .opacity(burst ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.6).delay(0.08), value: burst)
        }
        .onAppear { burst = true }
        .allowsHitTesting(false)
    }
}
