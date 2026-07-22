//
//  MarketCard.swift
//  Sticks
//
//  Slice 41: the Market — the web's Live odds view. Blend header
//  (model/crowd/live), the win-probability graph upgraded with soft
//  area fills + latest-hole dots, per-player rows (win %, hcp chip,
//  bar, call count, projected net), and "Place your call" — one crowd
//  call per user via POST /matches/:id/call, applied optimistically.
//  Replaces the plain "Win odds" card from slice 34.
//  Slice 47: scrub tooltip (hole + per-player win %) with a vertical
//  indicator, and a pulsing halo on the latest-hole dots — both drawn
//  natively over Swift Charts via chartOverlay.
//  Slice 71: web parity — blend line inline in the header, a wrapping
//  market chip row (Win % + one chip per side-game leaderboard), the
//  chart pinned to the full 1…18 hole domain with dotted gridlines
//  and 25/50/75 axis labels, bordered per-player rows in web market
//  colors (green/blue/gold/red by seat order) with "wagers" wording.
//  Slice 71 (graphs): the chips become a real market picker — each
//  side game draws its own cumulative line chart (SideGameLineChart,
//  fed by the server's sideGameSeries) in place of the win graph. Only
//  the chart swaps: the Win % player rows and "Place your call" stay
//  put, and per-game standings live in the Scorecard tab's Standings.
//

import SwiftUI
import Charts
import UIKit

struct MarketCard: View {
    let detail: MatchDetail
    let odds: MatchOdds
    /// Cumulative per-hole chart series for each enabled side game —
    /// drives the market picker; absent games simply don't get a pill.
    var sideGameSeries: SideGameSeries? = nil
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    /// matchPlayerId of the in-flight call POST — blocks double taps.
    @State private var pendingCallId: String?
    @State private var callError: String?

    /// Hole bucket under the user's finger while scrubbing the chart.
    @State private var selectedHole: Int?
    /// True between touch-down and release — hides the latest-dot pulse.
    @State private var isScrubbing = false

    /// Active market pill — Win % by default.
    @State private var market: GraphMarket = .win

    /// One player's polyline through the series buckets.
    private struct PlayerLine: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [(hole: Int, pct: Double)]
    }

    /// Players ranked by blended win probability, best first — used by
    /// the call section only; the market rows keep seat order like web.
    private var rankedPlayers: [MatchDetailPlayer] {
        detail.players.sorted {
            (odds.probabilities[$0.id] ?? 0) > (odds.probabilities[$1.id] ?? 0)
        }
    }

    /// Web market identity colors, assigned by seat order.
    private func marketColor(_ index: Int) -> Color {
        MarketPalette.color(index)
    }

    /// Player index in seat order — drives the market color.
    private func playerIndex(_ player: MatchDetailPlayer) -> Int {
        detail.players.firstIndex(where: { $0.id == player.id }) ?? 0
    }

    private var lines: [PlayerLine] {
        guard let series = odds.series else { return [] }
        return detail.players.enumerated().compactMap { index, player in
            // The chart domain starts at hole 1 — pre-round buckets
            // (hole 0) are dropped like the web.
            let points: [(hole: Int, pct: Double)] = series.compactMap { row in
                guard row.hole >= 1, let probability = row.probabilities[player.id] else { return nil }
                return (row.hole, probability * 100)
            }
            guard !points.isEmpty else { return nil }
            return PlayerLine(
                id: player.id,
                name: player.displayName,
                color: marketColor(index),
                points: points
            )
        }
    }

    /// "model 29% · crowd 0% · live 71%" from odds.weights, web order.
    private var blendLine: String? {
        guard let weights = odds.weights else { return nil }
        let parts: [String] = [("model", weights["model"]), ("crowd", weights["crowd"]), ("live", weights["live"])]
            .compactMap { name, value in
                value.map { "\(name) \(Int(($0 * 100).rounded()))%" }
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Win % first, then only the side games with a non-empty series —
    /// same order as the web. Drives which pills show.
    private var availableMarkets: [GraphMarket] {
        var out: [GraphMarket] = [.win]
        for m in GraphMarket.sideGameOrder where !(m.rows(sideGameSeries)?.isEmpty ?? true) {
            out.append(m)
        }
        return out
    }

    var body: some View {
        let markets = availableMarkets
        // Fall back to Win % if a refetch drops the selected series.
        let active: GraphMarket = markets.contains(market) ? market : .win

        VStack(alignment: .leading, spacing: 14) {
            header

            if markets.count > 1 {
                MarketChipFlow(spacing: 8, rowSpacing: 8) {
                    ForEach(markets) { m in
                        marketChip(m, isActive: m == active)
                    }
                }
            }

            // Only the graph swaps with the picker — the player rows
            // and the call market underneath are always Win %.
            chartArea(for: active)

            playerRows

            Rectangle()
                .fill(Color.sticksHairline.opacity(0.6))
                .frame(height: 1)

            callSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .alert(
            "Couldn't place that call",
            isPresented: Binding(
                get: { callError != nil },
                set: { if !$0 { callError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(callError ?? "")
        }
    }

    /// The swappable graph: the win-probability chart (scrub tooltip,
    /// pulsing dots) for Win %, a cumulative side-game line chart for
    /// everything else.
    @ViewBuilder
    private func chartArea(for market: GraphMarket) -> some View {
        if market == .win {
            let lines = self.lines
            if lines.contains(where: { $0.points.count >= 2 }) {
                chart(lines)
                    .frame(height: 190)
            }
        } else if let rows = market.rows(sideGameSeries) {
            SideGameLineChart(detail: detail, rows: rows, market: market)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Market")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            Spacer(minLength: 12)

            if !odds.open {
                Text("CLOSED")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksMuted)
            } else if let blendLine {
                Text(blendLine)
                    .font(SticksFont.mono(10))
                    .kerning(0.5)
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - Market chips

    private func marketChip(_ target: GraphMarket, isActive: Bool) -> some View {
        Button {
            guard market != target else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.15)) { market = target }
        } label: {
            Text(target.label)
                .font(SticksFont.mono(11))
                .foregroundStyle(isActive ? Color.sticksGreen : Color.sticksMuted)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(isActive ? Color.sticksGreen.opacity(0.08) : Color.clear)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(
                        isActive ? Color.sticksGreen.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Chart (slice 34, upgraded)

    /// X-axis tick holes — 1/6/12/18 for full rounds, 1/3/6/9 for nine.
    private var xAxisTicks: [Int] {
        let candidates = detail.holes <= 9 ? [1, 3, 6, 9] : [1, 6, 12, 18]
        return candidates.filter { $0 <= max(detail.holes, 2) }
    }

    private func chart(_ lines: [PlayerLine]) -> some View {
        // Every hole bucket that appears in any line, for scrub snapping.
        let allHoles: [Int] = Array(Set(lines.flatMap { $0.points.map(\.hole) })).sorted()

        return Chart {
            // Faint dotted gridlines framing the plot at 0/25/75/100 —
            // the 50% even-odds line dash-dotted and stronger, like web.
            ForEach([0, 25, 75, 100], id: \.self) { level in
                RuleMark(y: .value("Grid", level))
                    .foregroundStyle(Color.sticksHairline.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            RuleMark(y: .value("Grid", 50))
                .foregroundStyle(Color.sticksMuted.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [8, 4, 2, 4]))

            ForEach(lines) { line in
                ForEach(line.points, id: \.hole) { point in
                    // Soft area fill under the line. Explicit yStart
                    // keeps areas independent (no stacking).
                    AreaMark(
                        x: .value("Hole", point.hole),
                        yStart: .value("Base", 0),
                        yEnd: .value("Win %", point.pct),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [line.color.opacity(0.16), line.color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Hole", point.hole),
                        y: .value("Win %", point.pct),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(line.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Dot on the latest bucket.
                if let last = line.points.last {
                    PointMark(
                        x: .value("Hole", last.hole),
                        y: .value("Win %", last.pct)
                    )
                    .foregroundStyle(line.color)
                    .symbolSize(38)
                }
            }

            // Scrub state: vertical indicator + emphasized points.
            if let selectedHole {
                RuleMark(x: .value("Hole", selectedHole))
                    .foregroundStyle(Color.sticksHairline)
                    .lineStyle(StrokeStyle(lineWidth: 1))

                ForEach(lines) { line in
                    if let point = line.points.first(where: { $0.hole == selectedHole }) {
                        PointMark(
                            x: .value("Hole", point.hole),
                            y: .value("Win %", point.pct)
                        )
                        .foregroundStyle(line.color)
                        .symbolSize(54)
                    }
                }
            }
        }
        // Pinned to the full round like the web — the lines occupy only
        // the played span, leaving the rest of the 18 holes open.
        .chartXScale(domain: 1 ... max(detail.holes, 2))
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [25, 50, 75]) { value in
                AxisValueLabel {
                    if let pct = value.as(Int.self) {
                        Text("\(pct)%")
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisTicks) { value in
                AxisValueLabel {
                    if let hole = value.as(Int.self) {
                        Text("\(hole)")
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                chartOverlayContent(lines: lines, allHoles: allHoles, proxy: proxy, geo: geo)
            }
        }
    }

    /// The native layer over the plot: pulsing halos on the latest
    /// dots, the scrub gesture surface, and the floating tooltip.
    @ViewBuilder
    private func chartOverlayContent(
        lines: [PlayerLine],
        allHoles: [Int],
        proxy: ChartProxy,
        geo: GeometryProxy
    ) -> some View {
        let plotFrame: CGRect = proxy.plotFrame.map { geo[$0] } ?? .zero

        ZStack(alignment: .topLeading) {
            // Pulsing halo on each line's latest point. Hidden while
            // scrubbing — the scrub dots take over.
            if !isScrubbing {
                ForEach(lines) { line in
                    if let last = line.points.last,
                       let x = proxy.position(forX: last.hole),
                       let y = proxy.position(forY: last.pct) {
                        MarketPulseHalo(color: line.color)
                            .position(x: plotFrame.minX + x, y: plotFrame.minY + y)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Scrub surface — fires on touch-down and follows the drag.
            Rectangle()
                .fill(Color.clear)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let xInPlot = value.location.x - plotFrame.minX
                            guard let raw: Double = proxy.value(atX: xInPlot) else { return }
                            let nearest = allHoles.min {
                                abs(Double($0) - raw) < abs(Double($1) - raw)
                            }
                            if !isScrubbing {
                                isScrubbing = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            if nearest != selectedHole {
                                selectedHole = nearest
                            }
                        }
                        .onEnded { _ in
                            isScrubbing = false
                            selectedHole = nil
                        }
                )

            // Tooltip card near the top of the plot, following the
            // scrub x, clamped to stay on-screen.
            if let selectedHole {
                let tooltipWidth: CGFloat = 150
                let dotX = plotFrame.minX + (proxy.position(forX: selectedHole) ?? 0)
                let clampedX = min(
                    max(dotX - tooltipWidth / 2, plotFrame.minX + 2),
                    max(plotFrame.minX + 2, plotFrame.maxX - tooltipWidth - 2)
                )

                MarketScrubTooltip(
                    hole: selectedHole,
                    rows: tooltipRows(lines: lines, hole: selectedHole),
                    width: tooltipWidth
                )
                .offset(x: clampedX, y: plotFrame.minY + 2)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: selectedHole)
    }

    /// Per-player tooltip rows at a hole, sorted by win % descending.
    private func tooltipRows(lines: [PlayerLine], hole: Int) -> [MarketScrubTooltip.Row] {
        lines.compactMap { line in
            line.points.first(where: { $0.hole == hole }).map {
                MarketScrubTooltip.Row(id: line.id, name: line.name, color: line.color, pct: $0.pct)
            }
        }
        .sorted { $0.pct > $1.pct }
    }

    // MARK: - Per-player rows

    private var playerRows: some View {
        VStack(spacing: 10) {
            // Seat order like the web, each row its own bordered card.
            ForEach(Array(detail.players.enumerated()), id: \.element.id) { index, player in
                playerRow(player, color: marketColor(index))
            }
        }
    }

    private func playerRow(_ player: MatchDetailPlayer, color: Color) -> some View {
        let probability = odds.probabilities[player.id] ?? 0
        let wagers = odds.wagerCounts[player.id] ?? 0
        let projNet = odds.projNet[player.id]

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                MarketAvatar(player: player, fallback: color)

                Text(player.displayName)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                if let handicap = player.handicap {
                    Text("hcp \(handicapText(handicap))")
                        .font(SticksFont.mono(9))
                        .foregroundStyle(Color.sticksMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.sticksPanel2)
                        .clipShape(.capsule)
                        .overlay(
                            Capsule().stroke(Color.sticksHairline, lineWidth: 1)
                        )
                }

                Spacer(minLength: 8)

                Text("\(Int((probability * 100).rounded()))%")
                    .font(SticksFont.display(18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
            }

            // Full-width win bar in the player's identity color.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sticksPanel2)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * min(max(probability, 0), 1), 4))
                        .animation(.easeOut(duration: 0.35), value: probability)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(wagers) \(wagers == 1 ? "wager" : "wagers")")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)

                Spacer()

                if let projNet {
                    Text("proj net \(String(format: "%.1f", projNet))")
                        .font(SticksFont.mono(10))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        }
        .padding(12)
        .background(Color.sticksPanel2.opacity(0.25))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    /// "12" for whole-number handicaps, "8.4" otherwise.
    private func handicapText(_ handicap: Double) -> String {
        handicap.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(handicap))
            : String(format: "%.1f", handicap)
    }

    // MARK: - Place your call

    private var callSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Place your call")
                    .font(SticksFont.display(13, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                if odds.totalCalls > 0 {
                    Text("\(odds.totalCalls) TOTAL")
                        .font(SticksFont.mono(10))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksMuted)
                }
            }

            if !odds.open {
                Text("Market closed — this round is final.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
            }

            VStack(spacing: 8) {
                ForEach(rankedPlayers) { player in
                    callRow(player)
                }
            }

            if odds.open {
                Text(odds.myCall == nil
                    ? "Tap a player to call the winner — one call per person."
                    : "Tap your pick again to withdraw your call.")
                    .font(SticksFont.sans(11))
                    .foregroundStyle(Color.sticksFaint)
            }
        }
    }

    private func callRow(_ player: MatchDetailPlayer) -> some View {
        let isMine = odds.myCall == player.id
        let probability = odds.probabilities[player.id] ?? 0
        let calls = odds.wagerCounts[player.id] ?? 0

        return Button {
            placeCall(player)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMine ? Color.sticksGreen : Color.sticksFaint)

                Text(player.displayName)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if pendingCallId == player.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.sticksGreen)
                }

                Text("\(Int((probability * 100).rounded()))%")
                    .font(SticksFont.display(13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)

                Text("\(calls) \(calls == 1 ? "call" : "calls")")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isMine ? Color.sticksGreen.opacity(0.08) : Color.sticksPanel2.opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isMine ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!odds.open || pendingCallId != nil)
        .opacity(odds.open ? 1 : 0.6)
        .accessibilityLabel("\(isMine ? "Withdraw call on" : "Call") \(player.displayName)")
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }

    /// Tapping your current pick withdraws it (pickedPlayerId: null);
    /// anyone else places/moves the call. The response applies to the
    /// odds in place — no full refetch. Light haptic on success.
    private func placeCall(_ player: MatchDetailPlayer) {
        guard odds.open, pendingCallId == nil else { return }
        let picked: String? = odds.myCall == player.id ? nil : player.id
        pendingCallId = player.id
        Task {
            defer { pendingCallId = nil }
            do {
                try await viewModel.placeCall(pickedPlayerId: picked, session: session)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch let error as APIError {
                callError = error.message
            } catch {
                callError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}

// MARK: - Pieces

/// Left-aligned wrapping row for the market chips — pills flow onto
/// the next line when they run out of width, like the web.
nonisolated private struct MarketChipFlow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(
            width: maxWidth == .infinity ? usedWidth : maxWidth,
            height: y + rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 18pt avatar — profile photo when set, else initials on the
/// player's market color.
private struct MarketAvatar: View {
    let player: MatchDetailPlayer
    let fallback: Color

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
            .background(fallback)
    }

    private var initials: String {
        let parts = player.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// Floating scrub readout: "HOLE n" + a swatch/name/win % row per
/// player, styled like the app's small cream cards.
private struct MarketScrubTooltip: View {
    struct Row: Identifiable {
        let id: String
        let name: String
        let color: Color
        let pct: Double
    }

    let hole: Int
    let rows: [Row]
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("HOLE \(hole)")
                .font(SticksFont.mono(9))
                .kerning(1)
                .foregroundStyle(Color.sticksMuted)

            ForEach(rows) { row in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(row.color)
                        .frame(width: 10, height: 4)

                    Text(row.name)
                        .font(SticksFont.sans(11, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(Int(row.pct.rounded()))%")
                        .font(SticksFont.mono(10))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksInk)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
    }
}

/// Solid dot + repeating halo that scales up and fades out — the
/// live-odds pulse on the chart's latest bucket.
private struct MarketPulseHalo: View {
    let color: Color

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.5))
                .frame(width: 9, height: 9)
                .scaleEffect(isPulsing ? 2.2 : 1)
                .opacity(isPulsing ? 0 : 0.5)
                .animation(
                    .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                    value: isPulsing
                )

            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .onAppear { isPulsing = true }
    }
}
