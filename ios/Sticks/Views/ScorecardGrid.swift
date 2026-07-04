//
//  ScorecardGrid.swift
//  Sticks
//
//  Match-detail scorecard matching the web app: a card header row
//  ("Scorecard" + mono meta with the caller's to-par), then a split
//  layout — pinned player-name column outside a horizontal scroller,
//  44pt hole columns and a 56pt Tot column inside it. Cells are
//  outline-style (no solid fills — those belong to the GPS hole rail
//  and score-entry chips), with display-bold tabular digits. The
//  current hole's column auto-centers on appear and when it advances.
//

import SwiftUI

/// A tapped scorecard cell, driving the score entry sheet.
struct ScoreCellSelection: Identifiable {
    let player: MatchDetailPlayer
    let hole: Int
    let par: Int
    var id: String { "\(player.id)-\(hole)" }
}

struct ScorecardGrid: View {
    let detail: MatchDetail
    let players: [MatchDetailPlayer]
    /// Round index of the current hole — nil when the match isn't live.
    let currentHoleIndex: Int?
    let onSelect: (ScoreCellSelection) -> Void

    private let nameWidth: CGFloat = 88
    private let holeWidth: CGFloat = 44
    private let totWidth: CGFloat = 56
    private let headerHeight: CGFloat = 34
    private let rowHeight: CGFloat = 38
    private let cellSize = CGSize(width: 36, height: 30)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            splitGrid
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Scorecard")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)
            Spacer()
            meta
        }
    }

    /// "FRONT · +2 THRU 4" — the to-par part in accent, bold.
    private var meta: some View {
        let thru = thruCount
        return (
            Text("\(nineLabel) · ")
                .foregroundStyle(Color.sticksMuted)
            + Text(toParText)
                .font(SticksFont.mono(10, weight: .bold))
                .foregroundStyle(Color.sticksGreen)
            + Text(" THRU \(thru)")
                .foregroundStyle(Color.sticksMuted)
        )
        .font(SticksFont.mono(10))
        .kerning(0.5)
        .textCase(.uppercase)
    }

    /// FRONT/BACK from the hole the round is at (or last played).
    private var nineLabel: String {
        let index = currentHoleIndex ?? lastPlayedIndex ?? 0
        return detail.holeNumber(at: index) <= 9 ? "FRONT" : "BACK"
    }

    /// The caller's row when seated, else the top row.
    private var metaPlayer: MatchDetailPlayer? {
        players.first { $0.id == detail.myMatchPlayerId } ?? players.first
    }

    private var thruCount: Int {
        guard let player = metaPlayer else { return 0 }
        return (0 ..< detail.holes)
            .filter { player.scoresByHole[detail.holeNumber(at: $0)] != nil }
            .count
    }

    private var toParText: String {
        guard let player = metaPlayer else { return "E" }
        let diff = (0 ..< detail.holes).reduce(0) { partial, index in
            guard let score = player.scoresByHole[detail.holeNumber(at: index)] else {
                return partial
            }
            return partial + score - detail.par(at: index)
        }
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private var lastPlayedIndex: Int? {
        guard let player = metaPlayer else { return nil }
        return (0 ..< detail.holes)
            .last { player.scoresByHole[detail.holeNumber(at: $0)] != nil }
    }

    // MARK: - Split grid

    private var splitGrid: some View {
        HStack(alignment: .top, spacing: 0) {
            nameColumn
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0 ..< detail.holes, id: \.self) { index in
                            holeColumn(index)
                                .id(index)
                        }
                        totColumn
                    }
                }
                .onAppear {
                    if let index = currentHoleIndex {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onChange(of: currentHoleIndex) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Pinned name column

    private var nameColumn: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: nameWidth, height: headerHeight)
            ForEach(players) { player in
                nameCell(for: player)
            }
        }
        .frame(width: nameWidth)
    }

    private func nameCell(for player: MatchDetailPlayer) -> some View {
        HStack(spacing: 6) {
            avatarBubble(for: player)
            Text(player.displayName)
                .font(SticksFont.sans(12, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(width: nameWidth, height: rowHeight, alignment: .leading)
    }

    /// 14pt circle, initials fallback — accent for the caller's row.
    private func avatarBubble(for player: MatchDetailPlayer) -> some View {
        Text(initial(of: player.displayName))
            .font(SticksFont.sans(7, weight: .bold))
            .foregroundStyle(Color.sticksCream)
            .frame(width: 14, height: 14)
            .background(isMe(player) ? Color.sticksGreen : Color.sticksMuted)
            .clipShape(.circle)
    }

    // MARK: - Hole columns

    private func holeColumn(_ index: Int) -> some View {
        let isCurrent = index == currentHoleIndex
        return VStack(spacing: 0) {
            columnHeader(index, isCurrent: isCurrent)
            ForEach(players) { player in
                scoreCell(for: player, index: index, isCurrent: isCurrent)
            }
        }
        .frame(width: holeWidth)
    }

    private func columnHeader(_ index: Int, isCurrent: Bool) -> some View {
        VStack(spacing: 2) {
            Text("\(detail.holeNumber(at: index))")
                .font(SticksFont.mono(9, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.sticksGreen : Color.sticksMuted.opacity(0.8))
            Text("P\(detail.par(at: index))")
                .font(SticksFont.mono(8))
                .foregroundStyle(Color.sticksMuted.opacity(0.65))
        }
        .frame(width: holeWidth, height: headerHeight)
        .background {
            // Current hole's column cap: accent at 7%, rounded top.
            if isCurrent {
                UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                    .fill(Color.sticksGreen.opacity(0.07))
            }
        }
    }

    // MARK: - Cells

    private func scoreCell(for player: MatchDetailPlayer, index: Int, isCurrent: Bool) -> some View {
        let hole = detail.holeNumber(at: index)
        let par = detail.par(at: index)
        let score = player.scoresByHole[hole]

        return Button {
            onSelect(ScoreCellSelection(player: player, hole: hole, par: par))
        } label: {
            cellBody(score: score, par: par, isCurrent: isCurrent)
                .frame(width: holeWidth, height: rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!detail.canEnterScores)
    }

    @ViewBuilder
    private func cellBody(score: Int?, par: Int, isCurrent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)

        if isCurrent, let score {
            // Current hole, scored: accent text, page bg, 1.5px solid accent.
            cellDigits("\(score)", color: .sticksGreen)
                .frame(width: cellSize.width, height: cellSize.height)
                .background(Color.sticksBg, in: shape)
                .overlay(shape.stroke(Color.sticksGreen, lineWidth: 1.5))
        } else if isCurrent {
            // Current hole, unscored: "+" prompt, 1.5px dashed accent.
            Text("+")
                .font(SticksFont.sans(16, weight: .semibold))
                .foregroundStyle(Color.sticksGreen)
                .frame(width: cellSize.width, height: cellSize.height)
                .background(Color.sticksBg, in: shape)
                .overlay(
                    shape.stroke(
                        Color.sticksGreen.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
                    )
                )
        } else if let score {
            let diff = score - par
            let text: Color = diff < 0 ? .sticksGreen : (diff > 0 ? .sticksError : .sticksInk)
            let fill: Color = diff < 0
                ? Color.sticksGreen.opacity(0.10)
                : (diff > 0 ? Color.sticksError.opacity(0.08) : .sticksPanel2)
            let border: Color = diff < 0
                ? Color.sticksGreen.opacity(0.4)
                : (diff > 0 ? Color.sticksError.opacity(0.4) : .sticksHairline)
            cellDigits("\(score)", color: text)
                .frame(width: cellSize.width, height: cellSize.height)
                .background(fill, in: shape)
                .overlay(shape.stroke(border, lineWidth: 1))
        } else {
            // Unplayed (past or future): dashed outline, faint em-dash.
            Text("–")
                .font(SticksFont.mono(10))
                .foregroundStyle(Color.sticksMuted.opacity(0.45))
                .frame(width: cellSize.width, height: cellSize.height)
                .overlay(
                    shape.stroke(
                        Color.sticksHairline,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                    )
                )
        }
    }

    private func cellDigits(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SticksFont.display(13, weight: .bold).monospacedDigit())
            .foregroundStyle(color)
    }

    // MARK: - Tot column

    private var totColumn: some View {
        VStack(spacing: 0) {
            Text("TOT")
                .font(SticksFont.mono(9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color.sticksMuted.opacity(0.8))
                .frame(width: totWidth, height: headerHeight)
            ForEach(players) { player in
                totCell(for: player)
            }
        }
        .frame(width: totWidth)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(width: 1)
        }
    }

    private func totCell(for player: MatchDetailPlayer) -> some View {
        let total = (0 ..< detail.holes)
            .compactMap { player.scoresByHole[detail.holeNumber(at: $0)] }
            .reduce(0, +)
        return Group {
            if total > 0 {
                Text("\(total)")
                    .font(SticksFont.display(14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.sticksInk)
            } else {
                Text("–")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted.opacity(0.45))
            }
        }
        .frame(width: totWidth, height: rowHeight)
    }

    // MARK: - Helpers

    private func isMe(_ player: MatchDetailPlayer) -> Bool {
        player.id == detail.myMatchPlayerId
    }

    private func initial(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}
