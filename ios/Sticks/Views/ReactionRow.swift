//
//  Reactions.swift
//  Sticks
//
//  Slice 93: the five-emoji reaction row. The emoji ARE the affordance —
//  there is never a "+" or "add reaction" button. Unused emoji sit at
//  45% opacity, used ones show their count, and the caller's own gets a
//  green outline. Emoji order is the server's `reactionEmoji` (detail)
//  or the client constant (cards).
//

import SwiftUI
import UIKit

struct ReactionRow: View {
    /// Emoji in render order — never re-sorted client-side.
    let emojis: [String]
    /// The target's tallies from the latest server payload.
    let tallies: [Reaction]
    let onToggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(emojis, id: \.self) { emoji in
                chip(emoji)
            }
        }
    }

    private func tally(for emoji: String) -> Reaction? {
        tallies.first { $0.emoji == emoji }
    }

    @ViewBuilder
    private func chip(_ emoji: String) -> some View {
        let tally = tally(for: emoji)
        let isUsed = (tally?.count ?? 0) > 0
        let isMine = tally?.mine == true

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onToggle(emoji)
        } label: {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 15))
                if isUsed {
                    Text("\(tally?.count ?? 0)")
                        .font(SticksFont.mono(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksInk)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(isMine ? Color.sticksGreen.opacity(0.1) : Color.sticksPanel2)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(
                    isMine ? Color.sticksGreen.opacity(0.55) : Color.sticksHairline,
                    lineWidth: 1
                )
            )
            .opacity(isUsed || isMine ? 1 : 0.45)
            .contentShape(.capsule)
        }
        .buttonStyle(ReactionChipButtonStyle())
        .animation(.easeOut(duration: 0.15), value: tally)
        .accessibilityLabel("\(emoji) reaction\(isUsed ? ", \(tally?.count ?? 0)" : "")")
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }
}

private struct ReactionChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Highlight row

/// One highlights row (slice 93): the player, the server's label in the
/// tone's color, the hole math, and the hole's own reaction row. Copy
/// and order come straight from the server — nothing computed here.
struct HighlightRow: View {
    let highlight: MatchHighlight
    let tallies: [Reaction]
    let emojiSet: [String]
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(highlight.displayName)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text(highlight.label)
                    .font(SticksFont.label(11, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(toneColor)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("HOLE \(highlight.hole)")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksMuted)
            }

            Text("\(highlight.strokes) \(highlight.strokes == 1 ? "stroke" : "strokes") · par \(highlight.par)")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)

            ReactionRow(emojis: emojiSet, tallies: tallies, onToggle: onToggle)
        }
        .padding(.vertical, 10)
    }

    private var toneColor: Color {
        highlight.tone == "bad" ? .sticksError : .sticksGreen
    }
}
