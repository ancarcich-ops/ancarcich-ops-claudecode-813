//
//  OddsGraphCard.swift
//  Sticks
//
//  Slice 34: win-probability graph — one line per player showing win
//  odds across the round, fed by odds.series from GET /matches/:id.
//  Rendered only when the series has ≥ 2 points and the match has
//  more than one player; colors match the Standings seat colors.
//

import SwiftUI
import Charts

struct OddsGraphCard: View {
    let detail: MatchDetail
    let series: [OddsSeriesPoint]

    /// One player's polyline through the series buckets.
    private struct PlayerLine: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [(hole: Int, pct: Double)]
    }

    private var lines: [PlayerLine] {
        detail.players.compactMap { player in
            let points: [(hole: Int, pct: Double)] = series.compactMap { row in
                guard let probability = row.probabilities[player.id] else { return nil }
                return (row.hole, probability * 100)
            }
            guard !points.isEmpty else { return nil }
            return PlayerLine(
                id: player.id,
                name: player.displayName,
                color: MatchCardMath.seatColor(player.seat),
                points: points
            )
        }
    }

    var body: some View {
        let lines = self.lines

        VStack(alignment: .leading, spacing: 12) {
            Text("Win odds")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            chart(lines)
                .frame(height: 170)

            legend(lines)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    // MARK: - Chart

    private func chart(_ lines: [PlayerLine]) -> some View {
        Chart {
            // Even-odds reference at 50%.
            RuleMark(y: .value("Even", 50))
                .foregroundStyle(Color.sticksHairline)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            ForEach(lines) { line in
                ForEach(line.points, id: \.hole) { point in
                    LineMark(
                        x: .value("Hole", point.hole),
                        y: .value("Win %", point.pct),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(line.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(Color.sticksHairline.opacity(0.6))
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
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
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
    }

    // MARK: - Legend

    private func legend(_ lines: [PlayerLine]) -> some View {
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
                }
            }
        }
    }
}
