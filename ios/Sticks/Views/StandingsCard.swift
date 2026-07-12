//
//  StandingsCard.swift
//  Sticks
//
//  Slice 13: live standings — the Overall tab (rank-ordered players
//  with win bars fed by the odds engine) plus one segmented tab per
//  side-game kind rendering the server's pre-formatted leaderboards.
//

import SwiftUI

struct StandingsCard: View {
    let detail: MatchDetail
    /// Win probabilities keyed by matchPlayerId — empty hides bars/%/trend.
    let probabilities: [String: Double]
    let sideGames: [SideGame]
    /// Slice 50: opens the per-hole event editor for event-driven games
    /// (Snake, BBB, Match press). Nil hides the button — spectators
    /// and completed rounds.
    var onRecordEvents: ((SideGame) -> Void)? = nil

    /// nil = Overall; otherwise a side-game kind.
    @State private var selectedKind: String?

    private var showsWin: Bool {
        !probabilities.isEmpty && detail.players.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if !sideGames.isEmpty {
                tabs
                    .padding(.top, 12)
            }

            Group {
                if let kind = selectedKind,
                   let game = sideGames.first(where: { $0.kind == kind }) {
                    sideGameBody(game)
                } else {
                    overallRows
                }
            }
            .padding(.top, 10)

            if sideGames.isEmpty {
                Text("No side games on this round — set them up on the web.")
                    .font(SticksFont.mono(10))
                    .kerning(0.5)
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }

            Color.clear.frame(height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Standings")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            Spacer()

            if !probabilities.isEmpty {
                HStack(spacing: 5) {
                    RepricingDot()
                    Text("REPRICING")
                        .font(SticksFont.mono(10))
                        .kerning(1)
                }
                .foregroundStyle(Color.sticksGreen)
            }
        }
    }

    // MARK: - Tabs

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                tabChip(label: "Overall", kind: nil)
                ForEach(sideGames) { game in
                    tabChip(label: MatchDetailMath.kindLabel(game.kind), kind: game.kind)
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)
        }
    }

    private func tabChip(label: String, kind: String?) -> some View {
        let isActive = selectedKind == kind
        return Button {
            guard selectedKind != kind else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.15)) { selectedKind = kind }
        } label: {
            VStack(spacing: 6) {
                Text(label)
                    .font(SticksFont.mono(11))
                    .foregroundStyle(isActive ? Color.sticksInk : Color.sticksMuted)
                Rectangle()
                    .fill(isActive ? Color.sticksGreen : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Overall rows

    private var overallRows: some View {
        let ranked = MatchDetailMath.rankedPlayers(in: detail)
        let leaderIds = leaderIds(ranked: ranked)

        return VStack(spacing: 0) {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { position, player in
                if position > 0 {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
                overallRow(player, isLeader: leaderIds.contains(player.id))
            }
        }
    }

    /// The current leader(s): rank-1 players with at least one score.
    private func leaderIds(ranked: [MatchDetailPlayer]) -> Set<String> {
        let scored = ranked.filter { MatchDetailMath.holesPlayed(for: $0, in: detail) > 0 }
        guard let best = scored.first.map({ MatchDetailMath.rankMetric(for: $0, in: detail) }) else {
            return []
        }
        return Set(
            scored
                .filter { abs(MatchDetailMath.rankMetric(for: $0, in: detail) - best) < 0.000001 }
                .map(\.id)
        )
    }

    private func overallRow(_ player: MatchDetailPlayer, isLeader: Bool) -> some View {
        let isMe = player.id == detail.myMatchPlayerId
        let toPar = MatchDetailMath.grossToPar(for: player, in: detail)
        let probability = probabilities[player.id]

        return HStack(spacing: 8) {
            StandingsAvatar(player: player)

            Text(player.displayName)
                .font(SticksFont.sans(13, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            if isLeader {
                LeadChip()
            }

            Spacer(minLength: 8)

            Text(MatchDetailMath.toParLabel(toPar))
                .font(SticksFont.display(13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(toParColor(toPar))

            if showsWin {
                WinBar(
                    probability: probability,
                    fill: isMe
                        ? Color(red: 74 / 255, green: 96 / 255, blue: 122 / 255)
                        : .sticksGreen
                )

                Text(percentText(probability))
                    .font(SticksFont.display(12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
                    .frame(width: 34, alignment: .trailing)

                trendGlyph(probability)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isMe ? Color.sticksGreen.opacity(0.05) : .clear)
    }

    private func toParColor(_ diff: Int?) -> Color {
        guard let diff, diff != 0 else { return .sticksMuted }
        return diff < 0 ? .sticksGreen : .sticksError
    }

    private func percentText(_ probability: Double?) -> String {
        guard let probability else { return "—" }
        return "\(Int((probability * 100).rounded()))%"
    }

    /// ▲ accent (p ≥ .40), — faint (≥ .20), ▼ danger.
    private func trendGlyph(_ probability: Double?) -> some View {
        let p = probability ?? 0
        let (glyph, color): (String, Color) = p >= 0.40
            ? ("▲", .sticksGreen)
            : (p >= 0.20 ? ("—", .sticksFaint) : ("▼", .sticksError))
        return Text(glyph)
            .font(SticksFont.mono(11))
            .foregroundStyle(color)
    }

    // MARK: - Side-game tabs

    private func sideGameBody(_ game: SideGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if MatchDetailMath.hasNativeEditor(game.kind), let onRecordEvents {
                recordEventsButton(game: game, open: onRecordEvents)
            }
            ForEach(game.leaderboards) { board in
                leaderboardSection(board)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// Event-driven games fill from per-hole taps, not the scorecard —
    /// this is the way in. Config-only Targets gets a settings variant.
    private func recordEventsButton(game: SideGame, open: @escaping (SideGame) -> Void) -> some View {
        let isConfigOnly = MatchDetailMath.eventGameKey(game.kind) == "TARGETS"
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            open(game)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isConfigOnly ? "gearshape.fill" : "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(isConfigOnly ? "GAME SETTINGS" : "RECORD EVENTS")
                    .font(SticksFont.mono(10.5))
                    .kerning(1)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.sticksGreen)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color.sticksGreen.opacity(0.08))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.sticksGreen.opacity(0.35), lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(
            MatchDetailMath.eventGameKey(game.kind) == "TARGETS"
                ? "\(MatchDetailMath.kindLabel(game.kind)) settings"
                : "Record \(MatchDetailMath.kindLabel(game.kind)) events"
        )
    }

    private func leaderboardSection(_ board: SideGameLeaderboard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(board.title)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                if let subtitle = board.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(board.rows.enumerated()), id: \.offset) { position, row in
                    if position > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline)
                            .frame(height: 1)
                    }
                    leaderboardRow(row)
                }
            }
        }
    }

    private func leaderboardRow(_ row: SideGameRow) -> some View {
        HStack(spacing: 8) {
            Text(row.player)
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            if row.isLeader {
                LeadChip()
            }

            Spacer(minLength: 8)

            // Pre-formatted by the server — displayed verbatim.
            Text(row.value)
                .font(SticksFont.mono(13))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Pieces

/// 18pt avatar — profile photo when avatarUrl is set, else an initials
/// bubble on the player's seat color.
private struct StandingsAvatar: View {
    let player: MatchDetailPlayer

    var body: some View {
        Group {
            if let urlString = player.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        initialsBubble
                    }
                }
            } else {
                initialsBubble
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(.circle)
    }

    private var initialsBubble: some View {
        Text(initials)
            .font(SticksFont.label(7, weight: .bold))
            .foregroundStyle(Color.sticksCream)
            .frame(width: 18, height: 18)
            .background(MatchCardMath.seatColor(player.seat))
    }

    private var initials: String {
        let parts = player.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// Gold "LEAD" chip on the current leader's row.
private struct LeadChip: View {
    var body: some View {
        Text("LEAD")
            .font(SticksFont.mono(8))
            .kerning(0.8)
            .foregroundStyle(Color.sticksGold)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.sticksGold.opacity(0.1))
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(Color.sticksGold.opacity(0.3), lineWidth: 1)
            )
    }
}

/// 7pt win-probability bar — panel2 track with a hairline border; the
/// fill width is the probability with a 2% floor.
private struct WinBar: View {
    let probability: Double?
    let fill: Color

    private let width: CGFloat = 54

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color.sticksPanel2)
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )

            if let probability {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(fill)
                    .frame(width: width * max(min(probability, 1), 0.02))
                    .animation(.easeOut(duration: 0.35), value: probability)
            }
        }
        .frame(width: width, height: 7)
    }
}

/// Pulsing accent dot for the REPRICING badge.
private struct RepricingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
