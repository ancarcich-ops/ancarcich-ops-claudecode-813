//
//  RoundLiveActivity.swift
//  SticksWidget
//
//  Lock screen + Dynamic Island presentation for the on-course round
//  Live Activity: current hole, par, live front/center/back yardages,
//  and scoring progress in the Sticks cream/green look.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            RoundLockScreenView(context: context)
                .activityBackgroundTint(Color.sticksCream)
                .activitySystemActionForegroundColor(Color.sticksGreen)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HOLE \(context.state.hole)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                        Text("PAR \(context.state.par)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(centerYardsText(context.state))
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("YDS · CENTER")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        islandFlank(label: "FRONT", yards: context.state.frontYds)
                        Spacer()
                        Text(roundProgressText(context.state))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.sticksGold)
                        Spacer()
                        islandFlank(label: "BACK", yards: context.state.backYds)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.sticksGreenBright)
            } compactTrailing: {
                Text(compactTrailingText(context.state))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.sticksGreenBright)
            }
            .keylineTint(Color.sticksGreenBright)
        }
    }

    private func islandFlank(label: String, yards: Int?) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.55))
            Text(yards.map(String.init) ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Center yardage, or an em dash when the hole has no GPS data.
private func centerYardsText(_ state: RoundActivityAttributes.ContentState) -> String {
    state.centerYds.map(String.init) ?? "—"
}

/// Compact trailing: center yards when known, otherwise the hole number.
private func compactTrailingText(_ state: RoundActivityAttributes.ContentState) -> String {
    state.centerYds.map(String.init) ?? "H\(state.hole)"
}

/// "12/18 SCORED · +3" (the to-par suffix only when known).
private func roundProgressText(_ state: RoundActivityAttributes.ContentState) -> String {
    var text = "\(state.holesScored)/\(state.totalHoles) SCORED"
    if let toPar = state.myToPar {
        let suffix = toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
        text += " · \(suffix)"
    }
    return text
}

// MARK: - Lock screen / banner

private struct RoundLockScreenView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sticksGreen)
                    Text(context.attributes.courseName.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(Color.sticksGreen)
                        .lineLimit(1)
                }
                Text("HOLE \(context.state.hole) · PAR \(context.state.par)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                Text(roundProgressText(context.state))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sticksMuted)
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                flank(label: "F", yards: context.state.frontYds)
                Text(centerYardsText(context.state))
                    .font(.system(size: 38, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
                    .contentTransition(.numericText())
                flank(label: "B", yards: context.state.backYds)
            }
        }
        .padding(16)
    }

    private func flank(label: String, yards: Int?) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.sticksMuted)
            Text(yards.map(String.init) ?? "—")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk.opacity(0.8))
        }
    }
}
