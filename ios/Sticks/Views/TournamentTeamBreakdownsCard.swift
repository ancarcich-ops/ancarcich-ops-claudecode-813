//
//  TournamentTeamBreakdownsCard.swift
//  Sticks
//
//  Slice 88: the per-hole derivation behind each side's number — the
//  same thing the web shows. One collapsible row per breakdown.
//
//  Three rules from the spec that the field names do NOT give you:
//  1. Columns come from holes[0].players, NOT the roster. A four-man
//     scramble has ONE column however many players are on the side.
//  2. entry == "shared" labels that column "Team card" — whose row the
//     scorer used is an accident of data entry.
//  3. teamAllowance is ONE number for the side and is never split
//     across players.
//

import SwiftUI

struct TournamentTeamBreakdownsCard: View {
    let breakdowns: [TeamBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown")
                .font(SticksFont.display(19))
                .foregroundStyle(Color.sticksInk)
                .padding(.top, 4)

            VStack(spacing: 12) {
                ForEach(breakdowns, id: \.team) { breakdown in
                    BreakdownRow(breakdown: breakdown)
                }
            }
        }
    }
}

private struct BreakdownRow: View {
    let breakdown: TeamBreakdown
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text("T\(max(breakdown.team, 1))")
                        .font(SticksFont.mono(13))
                        .foregroundStyle(Color.sticksGreen)
                        .frame(width: 40, height: 40)
                        .background(Color.sticksGreen.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(breakdown.members.joined(separator: " + "))
                            .font(SticksFont.sans(14.5, weight: .semibold))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(2)
                        breakdownSubtitle
                    }

                    Spacer(minLength: 8)

                    if let total = breakdown.total {
                        // Points formats rank high-first — mark the unit
                        // so the total never reads as strokes (slice 90).
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(TournamentScoreFormat.score(total))
                                .font(SticksFont.mono(16, weight: .bold))
                                .foregroundStyle(Color.sticksInk)
                            if breakdown.format?.result?.lowercased() == "points" {
                                Text("PTS")
                                    .font(SticksFont.mono(8, weight: .heavy))
                                    .kerning(0.8)
                                    .foregroundStyle(Color.sticksFaint)
                            }
                        }
                    }

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sticksFaint)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    allowanceText

                    if !breakdown.holes.isEmpty {
                        holeTable
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var breakdownSubtitle: some View {
        var parts: [String] = []
        if breakdown.roundNumber > 0 { parts.append("R\(breakdown.roundNumber)") }
        if !breakdown.courseName.isEmpty { parts.append(breakdown.courseName) }
        if let label = breakdown.format?.label, !label.isEmpty { parts.append(label) }
        return Text(parts.joined(separator: " · "))
            .font(SticksFont.mono(9.5))
            .kerning(0.8)
            .foregroundStyle(Color.sticksFaint)
    }

    // MARK: Allowance text

    /// Rule 3: teamAllowance is one number for the side and is never
    /// split. Null → per-player lines; a number → one side-wide line.
    @ViewBuilder
    private var allowanceText: some View {
        if let teamAllowance = breakdown.teamAllowance {
            let handicaps = breakdown.allowances.compactMap(\.handicap).sorted()
            let handicapList = handicaps.map { TournamentScoreFormat.score($0) }.joined(separator: ", ")
            VStack(alignment: .leading, spacing: 3) {
                Text("The side plays off \(TournamentScoreFormat.score(teamAllowance)) strokes — \(breakdown.format?.allowanceLabel ?? "allowance") of \(handicapList)")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
                if let received = breakdown.teamStrokesReceived, !breakdown.holes.isEmpty {
                    Text("\(received) of those fall in this round's \(breakdown.holes.count) holes")
                        .font(SticksFont.sans(12.5))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(breakdown.allowances, id: \.displayName) { allowance in
                    Text(allowanceLine(allowance))
                        .font(SticksFont.sans(12.5))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        }
    }

    private func allowanceLine(_ allowance: TeamBreakdownAllowance) -> String {
        var line = "\(allowance.displayName) handicap"
        if let handicap = allowance.handicap {
            line += " \(TournamentScoreFormat.score(handicap))"
        }
        if let playing = allowance.playingHandicap {
            line += " → plays off \(playing)"
        }
        if let label = breakdown.format?.allowanceLabel, !label.isEmpty {
            line += " at \(label)"
        }
        if let received = allowance.strokesReceived {
            line += " → \(received) stroke\(received == 1 ? "" : "s")"
        }
        return line
    }

    // MARK: Hole table

    /// Columns: Hole, Par, SI, one per holes[0].players entry, Team.
    private var holeTable: some View {
        let headerPlayers = breakdown.holes[0].players
        let isShared = breakdown.format?.entry?.lowercased() == "shared"

        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    columnHeader("HOLE", width: 38)
                    columnHeader("PAR", width: 34)
                    columnHeader("SI", width: 30)
                    ForEach(Array(headerPlayers.enumerated()), id: \.offset) { _, player in
                        // Rule 2: a shared card belongs to the side, not
                        // to whichever player's row it landed on.
                        columnHeader(
                            isShared ? "TEAM CARD" : (player.displayName.isEmpty ? "P" : player.displayName.uppercased()),
                            width: isShared ? 84 : 62
                        )
                    }
                    columnHeader("TEAM", width: 48)
                }

                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(height: 1)
                    .gridCellColumns(3 + headerPlayers.count + 1)

                ForEach(breakdown.holes) { hole in
                    GridRow {
                        cell("\(hole.hole)", width: 38)
                        cell(hole.par.map(String.init) ?? "–", width: 34)
                        cell(hole.strokeIndex.map(String.init) ?? "–", width: 30)
                        ForEach(Array(hole.players.enumerated()), id: \.offset) { _, player in
                            playerCell(player, width: isShared ? 84 : 62)
                        }
                        Text(hole.teamScore.map(String.init) ?? "–")
                            .font(SticksFont.mono(11, weight: .bold))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 48, alignment: .center)
                            .frame(height: 26)
                    }
                    Rectangle()
                        .fill(Color.sticksHairline.opacity(0.5))
                        .frame(height: 0.5)
                        .gridCellColumns(3 + headerPlayers.count + 1)
                }
            }
        }
    }

    private func columnHeader(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(SticksFont.mono(8.5))
            .kerning(0.6)
            .foregroundStyle(Color.sticksFaint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .center)
            .padding(.vertical, 6)
    }

    /// Rule from the spec: strokes render as that many `*` after the
    /// gross — "5* → 4" means a gross 5, one handicap stroke, net 4.
    private func playerCell(_ player: TeamBreakdownPlayerCell, width: CGFloat) -> some View {
        var parts: [String] = []
        if let gross = player.gross {
            parts.append("\(gross)\(String(repeating: "*", count: max(player.strokes ?? 0, 0)))")
        }
        if let net = player.net {
            parts.append("→ \(net)")
        }
        let text = parts.joined(separator: " ")

        return Text(text.isEmpty ? "–" : text)
            .font(SticksFont.mono(10))
            .foregroundStyle(player.counted ? Color.sticksGreen : Color.sticksMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 3)
            .frame(width: width, alignment: .center)
            .frame(height: 26)
            .background(player.counted ? Color.sticksGreen.opacity(0.1) : .clear)
            .clipShape(.rect(cornerRadius: 5))
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5))
            .foregroundStyle(Color.sticksInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: .center)
            .frame(height: 26)
    }
}
