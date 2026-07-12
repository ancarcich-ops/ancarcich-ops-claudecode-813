//
//  SideGameScoreCard.swift
//  Sticks
//
//  Slice 52: discoverable entry points for scoring the event-driven
//  side games (Snake 3-putts, BBB awards, Match presses). One prominent
//  card per enabled game sits right under the scorecard — matching the
//  web, where the editor is inline on the match page — and opens the
//  slice-50 per-hole editor. Standings tabs keep the leaderboards.
//

import SwiftUI
import UIKit

struct SideGameScoreCard: View {
    let game: SideGame
    /// Recorded events for THIS game — drives the current-state line.
    let eventCount: Int
    /// Slice 53: overrides the event-count state line — config-driven
    /// games (Targets, unconfigured Wolf) describe their settings instead.
    var stateOverride: String? = nil
    let onOpen: (SideGame) -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(game)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 32, height: 32)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SticksFont.mono(10.5))
                        .kerning(1)
                        .foregroundStyle(Color.sticksGreen)

                    Text(hint)
                        .font(SticksFont.sans(14, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(stateLine)
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Score \(MatchDetailMath.kindLabel(game.kind))")
        .accessibilityHint(hint)
    }

    // MARK: - Per-game copy

    private var gameKey: String {
        MatchDetailMath.eventGameKey(game.kind)
    }

    private var title: String {
        switch gameKey {
        case "SNAKE": return "SNAKE · 3-PUTTS"
        case "BBB": return "BINGO BANGO BONGO"
        case "MATCH": return "MATCH · PRESSES"
        case "WOLF": return "WOLF"
        case "TARGETS": return "TARGETS"
        default: return MatchDetailMath.kindLabel(game.kind).uppercased()
        }
    }

    private var hint: String {
        switch gameKey {
        case "SNAKE": return "Tap in who 3-putted each hole"
        case "BBB": return "Record bingo / bango / bongo per hole"
        case "MATCH": return "Add or remove a press per hole"
        case "WOLF": return "Record the wolf's partner or lone-wolf call"
        case "TARGETS": return "Set the stat, target and ante"
        default: return "Record what happened each hole"
        }
    }

    private var stateLine: String {
        if let stateOverride { return stateOverride }
        switch eventCount {
        case 0: return "No events yet — tap to score"
        case 1: return "1 event recorded"
        default: return "\(eventCount) events recorded"
        }
    }

    private var iconName: String {
        switch gameKey {
        case "SNAKE": return "pencil"
        case "BBB": return "dice"
        case "MATCH": return "bolt"
        case "WOLF": return "pawprint"
        case "TARGETS": return "target"
        default: return "pencil"
        }
    }
}
