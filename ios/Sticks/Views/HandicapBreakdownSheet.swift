//
//  HandicapBreakdownSheet.swift
//  Sticks
//
//  Slice 62: "How is this calculated?" — tapping the Sticks Index on
//  Stats opens this sheet. It lists every round's differential (sorted
//  ascending, the counted ones highlighted, score-only rounds tagged
//  est) and walks the average → adjust → ×0.96 → index math. Mirrors
//  the web /stats breakdown panel.
//

import SwiftUI

struct HandicapBreakdownSheet: View {
    let breakdown: IndexBreakdown

    @Environment(\.dismiss) private var dismiss

    /// Best (lowest) differential first — the counted rounds lead.
    private var sortedRounds: [BreakdownRound] {
        breakdown.perRound.sorted { $0.differential < $1.differential }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                explainer
                roundsCard
                mathCard
                if breakdown.fromRounds >= 3, breakdown.fromRounds <= 8 {
                    fewRoundsFootnote
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("STICKS INDEX \(String(format: "%+.1f", breakdown.index))")
                    .font(SticksFont.mono(10))
                    .kerning(1.4)
                    .foregroundStyle(Color.sticksGreen)

                Text("How is this calculated?")
                    .font(SticksFont.display(24, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 30, height: 30)
                    .background(Color.sticksPanel2)
                    .clipShape(.circle)
            }
            .accessibilityLabel("Close")
        }
    }

    private var explainer: some View {
        Text("Your index is the best \(breakdown.usedCount) of your last \(breakdown.fromRounds) rounds. Each round's differential = (113 ÷ slope) × (gross − rating); only your lowest \(breakdown.usedCount) count.")
            .font(SticksFont.sans(13))
            .foregroundStyle(Color.sticksMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Rounds list

    private var roundsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ROUND DIFFERENTIALS")
                    .font(SticksFont.mono(9))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)

                Spacer(minLength: 8)

                Text("\(breakdown.usedCount) OF \(breakdown.fromRounds) COUNT")
                    .font(SticksFont.mono(9))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksGreen)
            }

            VStack(spacing: 0) {
                ForEach(Array(sortedRounds.enumerated()), id: \.element.id) { position, round in
                    if position > 0 {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
                    roundRow(round)
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func roundRow(_ round: BreakdownRound) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(round.used ? Color.sticksGreen : Color.sticksHairline)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(round.courseName.isEmpty ? "Round" : round.courseName)
                    .font(SticksFont.sans(13, weight: round.used ? .bold : .regular))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text("\(round.gross) (\(StatsFormat.vsPar(round.vsPar)))")
                        .font(SticksFont.mono(10))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksMuted)

                    if round.isEstimated {
                        Text("est")
                            .font(SticksFont.mono(8.5))
                            .foregroundStyle(Color.sticksGold)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.sticksGold.opacity(0.12))
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
            }

            Spacer(minLength: 8)

            Text(String(format: "%.1f", round.differential))
                .font(SticksFont.mono(13, weight: round.used ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(round.used ? Color.sticksGreen : Color.sticksInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(round.used ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(round))
    }

    private func accessibilityText(_ round: BreakdownRound) -> String {
        let counted = round.used ? "counts toward your index" : "does not count"
        return "\(round.courseName), gross \(round.gross), differential \(String(format: "%.1f", round.differential)), \(counted)"
    }

    // MARK: - Math block

    private var mathCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("THE MATH")
                .font(SticksFont.mono(9))
                .kerning(1)
                .foregroundStyle(Color.sticksFaint)

            VStack(alignment: .leading, spacing: 7) {
                mathLine(
                    "avg of best \(breakdown.usedCount)",
                    value: String(format: "= %.2f", breakdown.average),
                    tint: .sticksInk
                )

                if breakdown.adjust != 0 {
                    mathLine(
                        "small-sample adjustment",
                        value: String(format: "− %@", trimmed(breakdown.adjust)),
                        tint: .sticksMuted
                    )
                }

                mathLine(
                    "bonus of excellence",
                    value: String(format: "× %@", trimmed(breakdown.factor)),
                    tint: .sticksMuted
                )

                Rectangle().fill(Color.sticksHairline).frame(height: 1)

                mathLine(
                    "index",
                    value: String(format: "= %+.1f", breakdown.index),
                    tint: .sticksGreen,
                    bold: true
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func mathLine(_ label: String, value: String, tint: Color, bold: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(SticksFont.mono(11, weight: bold ? .medium : .regular))
                .foregroundStyle(bold ? Color.sticksInk : Color.sticksMuted)

            Spacer(minLength: 8)

            Text(value)
                .font(SticksFont.mono(12, weight: bold ? .medium : .regular))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    /// "1" not "1.00", "0.96" not "0.9600" — drop trailing zeros.
    private func trimmed(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        guard text.contains(".") else { return text }
        var result = text
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    // MARK: - Footnote

    private var fewRoundsFootnote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.sticksFaint)
                .padding(.top, 1)

            Text("With few rounds, only a handful count — your index swings more per round and firms up as you log more.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
