//
//  RoundLiveActivity.swift
//  SticksWidget
//
//  Yardage-first Live Activity: the cream "Caddie" lock screen card
//  (always light, even in dark mode) and the dark-token Dynamic Island.
//
//  Score colors here use conventional golf green=under / red=over — a
//  deliberate override of the app's usual palette mapping. The hero's
//  "y" unit is never colored: the yardage is not a score.
//
//  When the content goes stale (the app was suspended and distances
//  froze), the hero dims and "OPEN STICKS TO REFRESH" replaces the
//  "TO PIN · CENTER" label (context.isStale).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            CaddieCardView(context: context)
                .activityBackgroundTint(Color.caddieShell.opacity(0.97))
                .activitySystemActionForegroundColor(Color.caddieGreen)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.islandFlag)
                        Text("\(context.attributes.courseName.uppercased()) · THRU \(context.state.holesScored)")
                            .font(WidgetFont.mono(10, weight: .regular))
                            .kerning(0.8)
                            .foregroundStyle(Color.islandUnit)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    islandYards(context.state.toPinYds, size: 26, unitSize: 14, stale: context.isStale)
                        .padding(.trailing, 4)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Hole \(context.state.hole) · PAR \(context.state.par)")
                            .font(WidgetFont.display(16))
                            .foregroundStyle(Color.islandDigits)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        islandMeta(context.state)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.islandFlag)
            } compactTrailing: {
                islandYards(context.state.toPinYds, size: 15, unitSize: 11, stale: context.isStale)
            } minimal: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.islandFlag)
            }
            .keylineTint(Color.islandFlag)
        }
    }

    /// "168y" — DM Mono digits in island cream, the unit in island grey;
    /// "—" when there's no fix. Digits dim when stale.
    private func islandYards(_ yards: Int?, size: CGFloat, unitSize: CGFloat, stale: Bool) -> some View {
        Group {
            if let yards {
                Text("\(yards)")
                    .font(WidgetFont.mono(size))
                    .foregroundStyle(Color.islandDigits)
                + Text("y")
                    .font(WidgetFont.mono(unitSize))
                    .foregroundStyle(Color.islandUnit)
            } else {
                Text("—")
                    .font(WidgetFont.mono(size))
                    .foregroundStyle(Color.islandUnit)
            }
        }
        .lineLimit(1)
        .opacity(stale ? 0.4 : 1)
    }

    /// "F 159 · B 178 · +2" — F/B numbers in cream, labels in grey, the
    /// to-par keeping the red/green rule even on black. "— · LOCATING"
    /// when there's no fix.
    private func islandMeta(_ state: RoundActivityAttributes.ContentState) -> some View {
        var meta: Text
        if let front = state.frontYds, let back = state.backYds {
            meta = Text("F ").foregroundStyle(Color.islandUnit)
                + Text("\(front)").foregroundStyle(Color.islandDigits)
                + Text(" · B ").foregroundStyle(Color.islandUnit)
                + Text("\(back)").foregroundStyle(Color.islandDigits)
        } else {
            meta = Text("— · LOCATING").foregroundStyle(Color.islandUnit)
        }
        if let toPar = state.myToPar {
            let color: Color = toPar < 0 ? .islandFlag : (toPar > 0 ? .islandRed : .islandDigits)
            meta = meta
                + Text(" · ").foregroundStyle(Color.islandUnit)
                + Text(toParLabel(toPar)).foregroundStyle(color)
        }
        return meta
            .font(WidgetFont.mono(12))
            .kerning(0.4)
            .lineLimit(1)
    }
}

/// "+3" / "E" / "-1".
private func toParLabel(_ toPar: Int) -> String {
    if toPar == 0 { return "E" }
    return toPar > 0 ? "+\(toPar)" : "\(toPar)"
}

// MARK: - Lock screen card ("Caddie" skin — always cream, even in dark mode)

private struct CaddieCardView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            // Hairline on the hero's left edge, 16pt gap on both sides.
            Rectangle()
                .fill(Color.caddieLabel.opacity(0.28))
                .frame(width: 1)
                .padding(.leading, 16)

            hero
                .padding(.leading, 16)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.caddieBorder.opacity(0.9), lineWidth: 1)
        }
    }

    // MARK: Hero (right column) — yards to pin

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let toPin = context.state.toPinYds {
                heroNumber(toPin)
                    .opacity(context.isStale ? 0.35 : 1)
                Spacer().frame(height: 7)
            }
            heroLabel
            if context.state.toPinYds != nil,
               let front = context.state.frontYds,
               let back = context.state.backYds {
                Spacer().frame(height: 12)
                frontBackLine(front: front, back: back)
                    .opacity(context.isStale ? 0.35 : 1)
            }
        }
    }

    /// "168y" — the unit is 24pt and ALWAYS neutral: it is not a score.
    private func heroNumber(_ toPin: Int) -> some View {
        (Text("\(toPin)")
            .font(WidgetFont.mono(52))
            .kerning(-1.04)
            .foregroundStyle(Color.caddieInk)
         + Text("y")
            .font(WidgetFont.mono(24))
            .foregroundStyle(Color.caddieLabel))
            .lineLimit(1)
    }

    /// "TO PIN · CENTER", or "— · LOCATING" with no fix, or the stale
    /// call to action. Never an empty hero.
    private var heroLabel: some View {
        Group {
            if context.isStale {
                Text("OPEN STICKS TO REFRESH")
                    .foregroundStyle(Color.caddieSub)
            } else if context.state.toPinYds == nil {
                Text("— · LOCATING")
                    .foregroundStyle(Color.caddieLabel)
            } else {
                Text("TO PIN · ").foregroundStyle(Color.caddieLabel)
                    + Text("CENTER").foregroundStyle(Color.caddieSub)
            }
        }
        .font(WidgetFont.mono(9.5, weight: .regular))
        .kerning(1.14)
        .lineLimit(1)
    }

    /// "F 159y B 178y" — numbers in ink, letters and units neutral.
    private func frontBackLine(front: Int, back: Int) -> some View {
        (Text("F ").foregroundStyle(Color.caddieLabel)
            + Text("\(front)").foregroundStyle(Color.caddieInk)
            + Text("y ").foregroundStyle(Color.caddieLabel)
            + Text("B ").foregroundStyle(Color.caddieLabel)
            + Text("\(back)").foregroundStyle(Color.caddieInk)
            + Text("y").foregroundStyle(Color.caddieLabel))
            .font(WidgetFont.mono(12))
            .lineLimit(1)
    }

    // MARK: Left column — context

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    courseLine
                    holeLine
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("TO PAR")
                        .font(WidgetFont.mono(8.5, weight: .regular))
                        .kerning(0.85)
                        .foregroundStyle(Color.caddieLabel)
                    toParScore
                }
            }
            progressStrip
            thruLine
        }
    }

    private var courseLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.caddieRed)
            Text(context.attributes.courseName.uppercased())
                .font(WidgetFont.mono(10, weight: .regular))
                .kerning(0.8)
                .foregroundStyle(Color.caddieSub)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// "Hole 5  PAR 4" — this line never wraps.
    private var holeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Hole \(context.state.hole)")
                .font(WidgetFont.display(23))
                .foregroundStyle(Color.caddieInk)
            Text("PAR \(context.state.par)")
                .font(WidgetFont.display(13))
                .foregroundStyle(Color.caddieSub)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Conventional golf colors: green under, red over, ink for even.
    /// Spectators (no seat) get a neutral em dash.
    private var toParScore: some View {
        Group {
            if let toPar = context.state.myToPar {
                Text(toParLabel(toPar))
                    .foregroundStyle(
                        toPar < 0 ? Color.caddieGreen : (toPar > 0 ? Color.caddieRed : Color.caddieInk)
                    )
            } else {
                Text("—").foregroundStyle(Color.caddieLabel)
            }
        }
        .font(WidgetFont.mono(34))
        .monospacedDigit()
        .lineLimit(1)
    }

    /// One segment per hole in round order: green under, red over,
    /// neutral par, ink for the hole in play, faint for unscored.
    private var progressStrip: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< max(context.state.totalHoles, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(segmentColor(index))
                    .frame(height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Round index of the hole in play. Derived from the absolute hole
    /// number — exact for rounds starting on hole 1 (the standard case);
    /// shotgun starts rotate the marker by the starting offset.
    private var inPlayIndex: Int {
        context.state.hole - 1
    }

    private func segmentColor(_ index: Int) -> Color {
        if index == inPlayIndex { return .caddieInk }
        guard index >= 0,
              index < context.state.holeDiffs.count,
              let diff = context.state.holeDiffs[index] else {
            return Color.caddieLabel.opacity(0.28)
        }
        if diff < 0 { return .caddieGreen }
        if diff > 0 { return .caddieRed }
        return .caddieLabel
    }

    /// "THRU 4 OF 18" — the count slightly darker than the frame text.
    private var thruLine: some View {
        (Text("THRU ").foregroundStyle(Color.caddieLabel)
            + Text("\(context.state.holesScored)").foregroundStyle(Color.caddieSub)
            + Text(" OF \(context.state.totalHoles)").foregroundStyle(Color.caddieLabel))
            .font(WidgetFont.mono(10, weight: .regular))
            .kerning(1)
            .lineLimit(1)
    }
}
