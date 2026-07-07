//
//  StatsHeroCard.swift
//  Sticks
//
//  Slice 15: the hero index card from the redesign handoff — a green
//  Sticks-index panel (trend pill + trajectory sparkline) beside two
//  stat cells (avg score, best round). Equal-height columns via the
//  fixedSize trick; the left panel is flex ~1.15.
//

import SwiftUI

struct StatsHeroCard: View {
    let stats: PlayerStats
    /// Opens the "Set goal" editor — shown as a pencil on the green panel.
    var onEditGoal: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            IndexPanel(stats: stats, onEditGoal: onEditGoal)
                .containerRelativeFrame(.horizontal) { length, _ in
                    // Card is inset 20pt each side; left = 1.15 / 2.15.
                    max(0, length - 40) * (1.15 / 2.15)
                }
                .frame(maxHeight: .infinity)

            StatCellsPanel(stats: stats)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }
}

// MARK: - Left: the index panel

private struct IndexPanel: View {
    let stats: PlayerStats
    let onEditGoal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STICKS INDEX")
                .font(SticksFont.mono(10))
                .kerning(1.6)
                .foregroundStyle(Color.sticksCream.opacity(0.72))

            if let index = stats.index {
                Text(Self.indexText(index))
                    .font(SticksFont.display(44, weight: .bold))
                    .monospacedDigit()
                    .lineSpacing(-4)
                    .foregroundStyle(Color.sticksCream)

                if let delta = stats.indexDelta30, abs(delta) >= 0.1 {
                    trendPill(delta: delta)
                }

                if let target = stats.targetIndex {
                    targetLine(target: target, index: index)
                }

                if stats.indexTrajectory.count >= 2 {
                    IndexSparkline(values: stats.indexTrajectory)
                        .frame(height: 26)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("pending")
                    .font(SticksFont.displayItalic(34))
                    .foregroundStyle(Color.sticksCream)

                Text("\(stats.indexFromRounds)/3 ROUNDS LOGGED")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksCream.opacity(0.72))
            }

            Text(caption)
                .font(SticksFont.mono(10))
                .kerning(0.6)
                .foregroundStyle(Color.sticksCream.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background {
            ZStack(alignment: .bottomTrailing) {
                Color.sticksGreen

                // Soft decorative radial glow, bleeding past the corner.
                RadialGradient(
                    colors: [Color.white.opacity(0.1), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                )
                .frame(width: 120, height: 120)
                .offset(x: 30, y: 30)
            }
        }
        .clipped()
        .overlay(alignment: .topTrailing) {
            if let onEditGoal {
                Button(action: onEditGoal) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sticksCream.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Color.sticksCream.opacity(0.12))
                        .clipShape(.circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("Set index goal")
            }
        }
    }

    /// "TARGET 9.0 · 2.6 TO GO" — or "· ON TRACK" once the gap closes.
    private func targetLine(target: Double, index: Double) -> some View {
        let gap = index - target
        let suffix = gap <= 0 ? " · ON TRACK" : String(format: " · %.1f TO GO", gap)
        return Text(String(format: "TARGET %.1f", target) + suffix)
            .font(SticksFont.mono(10))
            .kerning(0.6)
            .foregroundStyle(Color.sticksCream.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func trendPill(delta: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(delta > 0 ? .zero : .degrees(180))

            Text(String(format: "%.1f LAST 30 DAYS", abs(delta)))
                .font(SticksFont.mono(10.5))
                .kerning(0.6)
        }
        .foregroundStyle(Color.sticksCream)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.sticksCream.opacity(0.14))
        .clipShape(.capsule)
    }

    private var caption: String {
        let rounds = stats.roundsCompleted == 1
            ? "1 ROUND COMPLETED"
            : "\(stats.roundsCompleted) ROUNDS COMPLETED"
        if let ghin = stats.ghin, !ghin.isEmpty {
            return "\(rounds) · GHIN #\(ghin)"
        }
        return rounds
    }

    /// "+11.4" — always one decimal, + prefix when ≥ 0.
    static func indexText(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}

/// Cream trajectory sparkline — y-scale min…max of the series, so a
/// downward slope means the index (and the golf) is improving.
private struct IndexSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            if let last = points.last {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Color.sticksCream.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                Circle()
                    .fill(Color.sticksCream)
                    .frame(width: 5.2, height: 5.2)
                    .position(last)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2,
              let minValue = values.min(),
              let maxValue = values.max() else { return [] }
        let range = maxValue - minValue
        // Inset so the round caps and end dot don't clip.
        let inset: CGFloat = 3
        let width = size.width - inset * 2
        let height = size.height - inset * 2
        let stepX = width / CGFloat(values.count - 1)
        return values.enumerated().map { offset, value in
            let fraction = range > 0 ? (value - minValue) / range : 0.5
            return CGPoint(
                x: inset + CGFloat(offset) * stepX,
                y: inset + height - CGFloat(fraction) * height
            )
        }
    }
}

// MARK: - Right: stat cells

private struct StatCellsPanel: View {
    let stats: PlayerStats

    var body: some View {
        VStack(spacing: 0) {
            avgScoreCell
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)

            bestCell
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var avgScoreCell: some View {
        HStack(spacing: 10) {
            iconTile(
                systemName: "chart.bar.fill",
                tint: .sticksGreen,
                fill: Color.sticksGreen.opacity(0.1)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("AVG SCORE")
                    .font(SticksFont.mono(8.5))
                    .kerning(0.9)
                    .foregroundStyle(Color.sticksFaint)

                Text(avgScoreText)
                    .font(SticksFont.display(27, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var bestCell: some View {
        HStack(spacing: 10) {
            iconTile(
                systemName: "trophy.fill",
                tint: .sticksGold,
                fill: Color.sticksGold.opacity(0.14)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("BEST")
                    .font(SticksFont.mono(8.5))
                    .kerning(0.9)
                    .foregroundStyle(Color.sticksFaint)

                if let best = stats.bestRound {
                    Text(StatsFormat.vsPar(best.vsPar))
                        .font(SticksFont.display(27, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(StatsFormat.vsParColor(best.vsPar))

                    Text(best.courseName.uppercased())
                        .font(SticksFont.mono(10))
                        .kerning(0.6)
                        .foregroundStyle(Color.sticksGold)
                        .lineLimit(1)

                    if let date = best.scheduledAt {
                        Text(Self.shortDate(date))
                            .font(SticksFont.mono(10))
                            .kerning(0.6)
                            .foregroundStyle(Color.sticksFaint)
                            .lineLimit(1)
                    }
                } else {
                    Text("—")
                        .font(SticksFont.display(27, weight: .bold))
                        .foregroundStyle(Color.sticksFaint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func iconTile(systemName: String, tint: Color, fill: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(fill)
            .clipShape(.rect(cornerRadius: 10))
    }

    private var avgScoreText: String {
        guard let avg = stats.avg18Gross else { return "—" }
        return "\(Int(avg.rounded()))"
    }

    /// "Jul 4" — the best round's date.
    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Shared formatting

/// vs-par formatting shared by the hero's BEST cell and the logged
/// rounds' score chips.
enum StatsFormat {
    /// "E" at even, otherwise a signed integer ("+5" / "-2").
    static func vsPar(_ value: Int) -> String {
        value == 0 ? "E" : String(format: "%+d", value)
    }

    /// Best-cell coloring: accent when under, gold at even, ink over.
    static func vsParColor(_ value: Int) -> Color {
        if value < 0 { return .sticksGreen }
        if value == 0 { return .sticksGold }
        return .sticksInk
    }
}
