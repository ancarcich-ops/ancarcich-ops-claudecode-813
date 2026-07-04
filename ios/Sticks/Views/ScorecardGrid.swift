//
//  ScorecardGrid.swift
//  Sticks
//
//  Scorecard: rows = players (caller first), columns = holes with a par
//  row, plus OUT/IN subtotals (18 holes) and a total column. The name
//  column is pinned; hole columns scroll horizontally. Score cells use
//  the web app's score-state colors (ScoreStyle) with monospaced digits
//  so columns align.
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
    let onSelect: (ScoreCellSelection) -> Void

    private let nameWidth: CGFloat = 106
    private let holeWidth: CGFloat = 42
    private let subtotalWidth: CGFloat = 52
    private let headerHeight: CGFloat = 30
    private let rowHeight: CGFloat = 48

    private enum GridColumn: Identifiable {
        case hole(index: Int)
        case subtotal(label: String, range: Range<Int>)
        case total

        var id: String {
            switch self {
            case .hole(let index): "h\(index)"
            case .subtotal(let label, _): label
            case .total: "TOT"
            }
        }
    }

    private var columns: [GridColumn] {
        var result: [GridColumn] = []
        for index in 0 ..< detail.holes {
            result.append(.hole(index: index))
            if detail.holes == 18 && index == 8 {
                result.append(.subtotal(label: "OUT", range: 0 ..< 9))
            }
        }
        if detail.holes == 18 {
            result.append(.subtotal(label: "IN", range: 9 ..< 18))
        }
        result.append(.total)
        return result
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            nameColumn
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(width: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    holeNumberRow
                    parRow
                    ForEach(players) { player in
                        scoreRow(for: player)
                    }
                }
            }
        }
    }

    // MARK: - Pinned name column

    private var nameColumn: some View {
        VStack(spacing: 0) {
            labelCell("HOLE")
            labelCell("PAR")
            ForEach(players) { player in
                nameCell(for: player)
            }
        }
        .frame(width: nameWidth)
    }

    private func labelCell(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.label(10, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(Color.sticksMuted)
            .frame(width: nameWidth, height: headerHeight, alignment: .leading)
            .padding(.leading, 2)
            .background(Color.sticksPanel2)
            .rowRule()
    }

    private func nameCell(for player: MatchDetailPlayer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(player.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)
                if isMe(player) {
                    Text("YOU")
                        .font(SticksFont.label(8, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksCream)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.sticksGreen)
                        .clipShape(.capsule)
                }
            }
            if let handicap = player.handicap {
                Text("HCP \(formatted(handicap))")
                    .font(SticksFont.label(9, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksMuted)
            }
        }
        .frame(width: nameWidth, height: rowHeight, alignment: .leading)
        .padding(.leading, 2)
        .background(rowBackground(for: player))
        .rowRule()
    }

    // MARK: - Header rows

    private var holeNumberRow: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                switch column {
                case .hole(let index):
                    Text("\(detail.holeNumber(at: index))")
                        .font(SticksFont.label(11, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                        .frame(width: holeWidth, height: headerHeight)
                case .subtotal(let label, _):
                    Text(label)
                        .font(SticksFont.label(10, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksMuted)
                        .frame(width: subtotalWidth, height: headerHeight)
                        .background(Color.sticksPanel2)
                case .total:
                    Text("TOT")
                        .font(SticksFont.label(10, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksGreen)
                        .frame(width: subtotalWidth, height: headerHeight)
                        .background(Color.sticksGreen.opacity(0.08))
                }
            }
        }
        .rowRule()
    }

    private var parRow: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                switch column {
                case .hole(let index):
                    Text("\(detail.par(at: index))")
                        .font(SticksFont.label(11, weight: .medium))
                        .foregroundStyle(Color.sticksMuted)
                        .frame(width: holeWidth, height: headerHeight)
                case .subtotal(_, let range):
                    Text("\(parSum(range))")
                        .font(SticksFont.label(11, weight: .semibold))
                        .foregroundStyle(Color.sticksMuted)
                        .frame(width: subtotalWidth, height: headerHeight)
                        .background(Color.sticksPanel2)
                case .total:
                    Text("\(parSum(0 ..< detail.holes))")
                        .font(SticksFont.label(11, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                        .frame(width: subtotalWidth, height: headerHeight)
                        .background(Color.sticksGreen.opacity(0.08))
                }
            }
        }
        .rowRule()
    }

    // MARK: - Score rows

    private func scoreRow(for player: MatchDetailPlayer) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                switch column {
                case .hole(let index):
                    scoreCell(for: player, index: index)
                case .subtotal(_, let range):
                    subtotalCell(for: player, range: range)
                        .background(Color.sticksPanel2)
                case .total:
                    totalCell(for: player)
                        .background(Color.sticksGreen.opacity(0.08))
                }
            }
        }
        .background(rowBackground(for: player))
        .rowRule()
    }

    private func scoreCell(for player: MatchDetailPlayer, index: Int) -> some View {
        let hole = detail.holeNumber(at: index)
        let par = detail.par(at: index)
        let score = player.scoresByHole[hole]
        let style = ScoreStyle.forScore(score, par: par)

        return Button {
            onSelect(ScoreCellSelection(player: player, hole: hole, par: par))
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(style.fill)
                    .frame(width: 30, height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(style.border, lineWidth: 1)
                    )
                    .overlay {
                        // Thin glow ring for eagle+ / double bogey+.
                        if let ring = style.ring {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ring.opacity(0.45), lineWidth: 1.5)
                                .frame(width: 36, height: 36)
                        }
                    }

                if let score {
                    Text("\(score)")
                        .font(SticksFont.mono(14, weight: .semibold))
                        .foregroundStyle(style.text)
                } else {
                    Text("·")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.sticksHairline)
                }
            }
            .frame(width: holeWidth, height: rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!detail.canEnterScores)
    }

    private func subtotalCell(for player: MatchDetailPlayer, range: Range<Int>) -> some View {
        Group {
            if let sum = strokeSum(for: player, range: range) {
                Text("\(sum)")
                    .font(SticksFont.mono(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
            } else {
                Text("–")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sticksHairline)
            }
        }
        .frame(width: subtotalWidth, height: rowHeight)
    }

    private func totalCell(for player: MatchDetailPlayer) -> some View {
        VStack(spacing: 1) {
            if let total = strokeSum(for: player, range: 0 ..< detail.holes) {
                Text("\(total)")
                    .font(SticksFont.mono(16, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                Text(toParText(for: player))
                    .font(SticksFont.label(9, weight: .bold))
                    .foregroundStyle(toParColor(for: player))
            } else {
                Text("–")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sticksHairline)
            }
        }
        .frame(width: subtotalWidth, height: rowHeight)
    }

    // MARK: - Math

    private func parSum(_ range: Range<Int>) -> Int {
        range.reduce(0) { $0 + detail.par(at: $1) }
    }

    /// Sum of strokes over played holes in `range`; nil if none played.
    private func strokeSum(for player: MatchDetailPlayer, range: Range<Int>) -> Int? {
        let scores = range.compactMap { player.scoresByHole[detail.holeNumber(at: $0)] }
        return scores.isEmpty ? nil : scores.reduce(0, +)
    }

    /// Strokes vs par across played holes only ("E", "+3", "-2").
    private func toPar(for player: MatchDetailPlayer) -> Int {
        (0 ..< detail.holes).reduce(0) { partial, index in
            guard let score = player.scoresByHole[detail.holeNumber(at: index)] else {
                return partial
            }
            return partial + score - detail.par(at: index)
        }
    }

    private func toParText(for player: MatchDetailPlayer) -> String {
        let diff = toPar(for: player)
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    private func toParColor(for player: MatchDetailPlayer) -> Color {
        let diff = toPar(for: player)
        if diff < 0 { return .sticksGreen }
        if diff > 0 { return .sticksError.opacity(0.85) }
        return .sticksMuted
    }

    // MARK: - Helpers

    private func isMe(_ player: MatchDetailPlayer) -> Bool {
        player.id == detail.myMatchPlayerId
    }

    private func rowBackground(for player: MatchDetailPlayer) -> Color {
        isMe(player) ? Color.sticksGreen.opacity(0.07) : .clear
    }

    private func formatted(_ handicap: Double) -> String {
        handicap == handicap.rounded()
            ? String(Int(handicap))
            : String(format: "%.1f", handicap)
    }
}

private extension View {
    /// Hairline rule under a scorecard row.
    func rowRule() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.sticksHairline.opacity(0.7))
                .frame(height: 0.5)
        }
    }
}
