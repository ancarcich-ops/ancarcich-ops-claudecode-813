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

/// Slice 35: which lens the scorecard shows scores through.
enum ScoreView {
    case gross
    case net
}

struct ScorecardGrid: View {
    let detail: MatchDetail
    let players: [MatchDetailPlayer]
    /// Round index of the current hole — nil when the match isn't live.
    let currentHoleIndex: Int?
    let onSelect: (ScoreCellSelection) -> Void

    /// Slice 35: gross/net lens — defaults to the round's scoring mode.
    @State private var scoreView: ScoreView

    init(
        detail: MatchDetail,
        players: [MatchDetailPlayer],
        currentHoleIndex: Int?,
        onSelect: @escaping (ScoreCellSelection) -> Void
    ) {
        self.detail = detail
        self.players = players
        self.currentHoleIndex = currentHoleIndex
        self.onSelect = onSelect
        _scoreView = State(
            initialValue: detail.scoringMode.uppercased() == "NET" ? .net : .gross
        )
    }

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
        HStack(spacing: 8) {
            Text("Scorecard")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)
            Spacer(minLength: 4)
            meta
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsToggle {
                modeToggle
            }
        }
    }

    // MARK: - Gross/Net toggle (slice 35)

    /// Net view is meaningless on a GROSS round — hide the toggle there.
    private var showsToggle: Bool {
        detail.scoringMode.uppercased() != "GROSS"
    }

    private var showsNet: Bool {
        showsToggle && scoreView == .net
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleChip("GROSS", mode: .gross)
            toggleChip("NET", mode: .net)
        }
        .padding(2)
        .background(Color.sticksPanel2, in: Capsule())
        .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
    }

    private func toggleChip(_ label: String, mode: ScoreView) -> some View {
        let isActive = scoreView == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                scoreView = mode
            }
        } label: {
            Text(label)
                .font(SticksFont.mono(8.5, weight: isActive ? .bold : .regular))
                .kerning(0.5)
                .foregroundStyle(isActive ? Color.sticksCream : Color.sticksMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(isActive ? Color.sticksGreen : Color.clear, in: Capsule())
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label == "NET" ? "Net" : "Gross") scores")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// Strokes the player receives on the hole at 0-based round position
    /// `index` — the exact engine formula: extra strokes fall on the
    /// opening holes of the round (no stroke-index lookup).
    private func strokesReceived(for player: MatchDetailPlayer, at index: Int) -> Int {
        let handicap = player.handicap ?? 0
        guard handicap > 0, detail.holes > 0 else { return 0 }
        let base = (handicap / Double(detail.holes)).rounded(.down)
        let extra = handicap - base * Double(detail.holes)
        return Int(base) + (Double(index) < extra ? 1 : 0)
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
        let gross = player.scoresByHole[hole]
        let strokes = showsNet ? strokesReceived(for: player, at: index) : 0
        let display = showsNet ? gross.map { $0 - strokes } : gross

        return Button {
            onSelect(ScoreCellSelection(player: player, hole: hole, par: par))
        } label: {
            cellBody(score: display, par: par, isCurrent: isCurrent, hasStroke: strokes > 0)
                .frame(width: holeWidth, height: rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!detail.canEnterScores)
    }

    @ViewBuilder
    private func cellBody(score: Int?, par: Int, isCurrent: Bool, hasStroke: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)

        if isCurrent, let score {
            // Current hole, scored: accent text, page bg, 1.5px solid accent.
            cellDigits("\(score)", color: .sticksGreen)
                .frame(width: cellSize.width, height: cellSize.height)
                .background(Color.sticksBg, in: shape)
                .overlay(shape.stroke(Color.sticksGreen, lineWidth: 1.5))
                .overlay(alignment: .topTrailing) { strokeDot(hasStroke) }
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
                .overlay(alignment: .topTrailing) { strokeDot(hasStroke) }
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
                .overlay(alignment: .topTrailing) { strokeDot(hasStroke) }
        }
    }

    /// Net-mode marker: a single subtle dot on holes where the player
    /// receives at least one stroke (capped at one dot).
    @ViewBuilder
    private func strokeDot(_ show: Bool) -> some View {
        if show {
            Circle()
                .fill(Color.sticksGreen.opacity(0.7))
                .frame(width: 3.5, height: 3.5)
                .padding(3)
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
        let gross = (0 ..< detail.holes)
            .compactMap { player.scoresByHole[detail.holeNumber(at: $0)] }
            .reduce(0, +)
        // Net total = gross − full handicap, matching the web's Net column.
        let net = Double(gross) - (player.handicap ?? 0)
        return Group {
            if gross > 0 {
                VStack(spacing: 1) {
                    Text(showsNet ? formatNetTotal(net) : "\(gross)")
                        .font(SticksFont.display(14, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.sticksInk)
                    if showsToggle {
                        Text(showsNet ? "G \(gross)" : "N \(formatNetTotal(net))")
                            .font(SticksFont.mono(8))
                            .foregroundStyle(Color.sticksMuted.opacity(0.75))
                    }
                }
            } else {
                Text("–")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted.opacity(0.45))
            }
        }
        .frame(width: totWidth, height: rowHeight)
    }

    /// "73" for whole nets, "72.6" for fractional handicaps.
    private func formatNetTotal(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
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
