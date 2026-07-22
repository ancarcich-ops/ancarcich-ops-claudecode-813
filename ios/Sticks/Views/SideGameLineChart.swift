//
//  SideGameLineChart.swift
//  Sticks
//
//  Slice 71: the side-game market graph — one cumulative line per
//  player through a game's per-hole series (skins won, Stableford
//  points, Nassau net-vs-par, …), styled to read as one component
//  with the Win % chart: soft area fills, latest-hole dots, the same
//  pinned 1…18 hole domain, plus a legend and a y-axis caption
//  formatted for the market. No scrub/tooltip in v1.
//

import SwiftUI
import Charts

struct SideGameLineChart: View {
    let detail: MatchDetail
    let rows: [SideGameSeriesRow]
    let market: GraphMarket

    private struct Line: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [(hole: Int, value: Double)]
    }

    /// One line per seated player, colored by seat order like the Win %
    /// market. A player missing early holes just starts where they have
    /// a value — those rows are skipped, not zero-filled.
    private var lines: [Line] {
        detail.players.enumerated().compactMap { index, player in
            let points: [(hole: Int, value: Double)] = rows.compactMap { row in
                guard row.hole >= 1, let value = row.values[player.id] else { return nil }
                return (row.hole, value)
            }
            guard !points.isEmpty else { return nil }
            return Line(
                id: player.id,
                name: player.displayName,
                color: MarketPalette.color(index),
                points: points
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if lines.contains(where: { !$0.points.isEmpty }) {
                chart
                    .frame(height: 170)

                Text(market.yLabel.uppercased())
                    .font(SticksFont.mono(9))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksMuted)

                legend
            } else {
                Text("No \(market.label) results yet.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    // MARK: - Chart

    /// X-axis tick holes — 1/6/12/18 for full rounds, 1/3/6/9 for nine,
    /// matching the Win % chart.
    private var xAxisTicks: [Int] {
        let candidates = detail.holes <= 9 ? [1, 3, 6, 9] : [1, 6, 12, 18]
        return candidates.filter { $0 <= max(detail.holes, 2) }
    }

    private var chart: some View {
        Chart {
            ForEach(lines) { line in
                ForEach(line.points, id: \.hole) { point in
                    // Soft area fill under the line. Explicit yStart
                    // keeps areas independent (no stacking).
                    AreaMark(
                        x: .value("Hole", point.hole),
                        yStart: .value("Base", 0),
                        yEnd: .value("Value", point.value),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [line.color.opacity(0.14), line.color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Hole", point.hole),
                        y: .value("Value", point.value),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(line.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Dot on the latest hole with a value.
                if let last = line.points.last {
                    PointMark(
                        x: .value("Hole", last.hole),
                        y: .value("Value", last.value)
                    )
                    .foregroundStyle(line.color)
                    .symbolSize(38)
                }
            }

            // Zero reference line for the markets that go negative
            // (Nassau net-vs-par, Match/Sixes dots).
            if crossesZero {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.sticksHairline.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        // Pinned to the full round like the Win % chart — the lines
        // occupy only the played span.
        .chartXScale(domain: 1 ... max(detail.holes, 2))
        .chartXAxis {
            AxisMarks(values: xAxisTicks) { value in
                AxisGridLine()
                    .foregroundStyle(Color.sticksHairline.opacity(0.4))
                AxisValueLabel {
                    if let hole = value.as(Int.self) {
                        Text("\(hole)")
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color.sticksHairline.opacity(0.3))
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text(market.format(n))
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
    }

    /// True when any point dips negative — draws the dashed zero rule.
    private var crossesZero: Bool {
        lines.flatMap { $0.points.map(\.value) }.contains(where: { $0 < 0 })
    }

    // MARK: - Legend

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(lines) { line in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(line.color)
                        .frame(width: 14, height: 4)

                    Text(line.name)
                        .font(SticksFont.sans(11))
                        .foregroundStyle(Color.sticksMuted)
                        .lineLimit(1)

                    if let last = line.points.last {
                        Text(market.format(last.value))
                            .font(SticksFont.mono(10))
                            .monospacedDigit()
                            .foregroundStyle(Color.sticksInk)
                    }
                }
            }
        }
    }
}
