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
//  Who-reacted: a LONG-PRESS on a used chip (count > 0) opens the
//  reactors sheet — tap still toggles the caller's own reaction. The
//  closure is optional; surfaces without identities (feed cards) pass
//  nothing and the gesture simply doesn't exist.
//

import SwiftUI
import UIKit

struct ReactionRow: View {
    /// Emoji in render order — never re-sorted client-side.
    let emojis: [String]
    /// The target's tallies from the latest server payload.
    let tallies: [Reaction]
    /// Long-press a used chip → the reactors sheet. Nil = no gesture.
    var onWhoReacted: ((String) -> Void)? = nil
    let onToggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(emojis, id: \.self) { emoji in
                ReactionChip(
                    emoji: emoji,
                    tally: tallies.first { $0.emoji == emoji },
                    onWhoReacted: onWhoReacted,
                    onToggle: onToggle
                )
            }
        }
    }
}

/// One emoji chip. Tap toggles the caller's own reaction; a long-press
/// on a used chip opens the reactors sheet INSTEAD of toggling. The
/// flag matters because a Button fires on touch-up inside — releasing
/// after a long hold would otherwise toggle too, so the gesture marks
/// the touch consumed and the action drops it.
private struct ReactionChip: View {
    let emoji: String
    let tally: Reaction?
    var onWhoReacted: ((String) -> Void)?
    let onToggle: (String) -> Void

    @State private var longPressConsumed = false

    private var isUsed: Bool { (tally?.count ?? 0) > 0 }
    private var isMine: Bool { tally?.mine == true }

    var body: some View {
        Button {
            if longPressConsumed {
                longPressConsumed = false
                return
            }
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
        .simultaneousGesture(whoReactedGesture)
        .accessibilityLabel("\(emoji) reaction\(isUsed ? ", \(tally?.count ?? 0)" : "")")
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
        .accessibilityAction(named: "See who reacted") {
            onWhoReacted?(emoji)
        }
    }

    /// Long-press opens the reactors sheet — only on used chips, only
    /// when the caller can show it.
    private var whoReactedGesture: AnyGesture<Void> {
        let gesture = LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                guard isUsed else { return }
                longPressConsumed = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onWhoReacted?(emoji)
            }
        return AnyGesture(gesture.map { _ in () })
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
    /// Slice 96: the account's "Show reactions" setting — false drops
    /// this row's emoji chips while the highlight itself stays.
    var showsReactions: Bool = true
    /// Who-reacted passthrough — the sheet opens on this hole's target.
    var onWhoReacted: ((String) -> Void)? = nil
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

            if showsReactions {
                ReactionRow(
                    emojis: emojiSet,
                    tallies: tallies,
                    onWhoReacted: onWhoReacted,
                    onToggle: onToggle
                )
            }
        }
        .padding(.vertical, 10)
    }

    private var toneColor: Color {
        highlight.tone == "bad" ? .sticksError : .sticksGreen
    }
}
