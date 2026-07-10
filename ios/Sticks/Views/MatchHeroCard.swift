//
//  MatchHeroCard.swift
//  Sticks
//
//  Slice 13: the live match hero — the caller's gross to-par huge on
//  the left, NET/POSITION and FRONT 9/BACK 9 stat columns on the
//  right, and the current-hole footer line. Rendered only when the
//  caller is seated in an IN_PROGRESS match.
//
//  Slice 36: web parity — the big number renders unclipped (no fixed
//  height), and the hairline + hole line live INSIDE the right pane
//  (indented under NET), matching the web's InRoundLive.
//

import SwiftUI

struct MatchHeroCard: View {
    let detail: MatchDetail
    /// Keyed by absolute hole number — the footer's yardage source.
    let holeGeo: [Int: HoleGeo]
    /// Round index of the hole in play — the footer line.
    let currentHoleIndex: Int?

    private var me: MatchDetailPlayer? {
        detail.players.first { $0.id == detail.myMatchPlayerId }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            grossColumn

            Rectangle()
                .fill(Color.sticksHairline)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                statColumns

                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(height: 1)

                holeLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Left: huge gross to-par

    private var grossColumn: some View {
        let gross = me.flatMap { MatchDetailMath.grossToPar(for: $0, in: detail) }
        let thru = me.map { MatchDetailMath.holesPlayed(for: $0, in: detail) } ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            // Slice 36: no height clamp — the glyph renders in full.
            Text(MatchDetailMath.toParLabel(gross))
                .font(SticksFont.display(56, weight: .bold))
                .monospacedDigit()
                .kerning(-1)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(grossColor(gross))

            Text("GROSS · THRU \(thru)")
                .font(SticksFont.mono(9.5))
                .kerning(0.9)
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private func grossColor(_ gross: Int?) -> Color {
        guard let gross else { return .sticksMuted }
        return gross < 0 ? .sticksGreen : .sticksInk
    }

    // MARK: - Right: stat columns

    private var statColumns: some View {
        let net = me.flatMap { MatchDetailMath.netToPar(for: $0, in: detail) }
        let position = detail.myMatchPlayerId.flatMap {
            MatchDetailMath.position(of: $0, in: detail)
        }
        let front = me.flatMap {
            MatchDetailMath.grossToPar(for: $0, in: detail, indices: 0 ..< min(9, detail.holes))
        }
        let back: Int? = detail.holes == 18
            ? me.flatMap { MatchDetailMath.grossToPar(for: $0, in: detail, indices: 9 ..< 18) }
            : nil

        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                if MatchDetailMath.isNetMode(detail) {
                    stat("NET", value: MatchDetailMath.netLabel(net), isAccent: (net ?? 0) < -0.05)
                }
                positionStat(position)
            }

            VStack(alignment: .leading, spacing: 10) {
                stat("FRONT 9", value: MatchDetailMath.toParLabel(front), isAccent: (front ?? 0) < 0)
                if detail.holes == 18 {
                    stat("BACK 9", value: MatchDetailMath.toParLabel(back), isAccent: (back ?? 0) < 0)
                }
            }
        }
    }

    private func stat(_ label: String, value: String, isAccent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            statLabel(label)
            Text(value)
                .font(SticksFont.display(13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isAccent ? Color.sticksGreen : Color.sticksInk)
        }
    }

    /// "1st" — the number with a smaller ordinal suffix.
    private func positionStat(_ position: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            statLabel("POSITION")
            if let position {
                (
                    Text("\(position)")
                        .font(SticksFont.display(13, weight: .bold))
                    + Text(MatchDetailMath.ordinalSuffix(position))
                        .font(SticksFont.display(9, weight: .bold))
                )
                .foregroundStyle(Color.sticksInk)
            } else {
                Text("—")
                    .font(SticksFont.display(13, weight: .bold))
                    .foregroundStyle(Color.sticksMuted)
            }
        }
    }

    private func statLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(8.5))
            .kerning(0.7)
            .foregroundStyle(Color.sticksFaint)
    }

    // MARK: - Footer: current hole line

    private var holeLine: some View {
        let index = min(currentHoleIndex ?? 0, max(detail.holes - 1, 0))
        let hole = detail.holeNumber(at: index)
        var suffix = " · PAR \(detail.par(at: index))"
        if let yards = holeGeo[hole]?.distanceYds {
            suffix += " · \(Int(yards.rounded()))Y"
        }

        return (
            Text("HOLE \(hole)")
                .foregroundStyle(Color.sticksInk)
            + Text(suffix)
                .foregroundStyle(Color.sticksMuted)
        )
        .font(SticksFont.mono(10.5))
        .kerning(0.7)
    }
}
