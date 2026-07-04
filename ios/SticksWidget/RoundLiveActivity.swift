//
//  RoundLiveActivity.swift
//  SticksWidget
//
//  Lock screen + Dynamic Island presentation for the on-course round
//  Live Activity: current hole, par, live TO PIN yardage with FRONT/BACK,
//  and scoring progress in the Sticks cream/green look.
//
//  When the content goes stale (the app was suspended and distances froze
//  at their last value), the yardage dims and "OPEN STICKS TO REFRESH"
//  renders instead of pretending the number is live (context.isStale).
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
                        Text(context.attributes.courseName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(Color.sticksGreenBright)
                            .lineLimit(1)
                        Text("HOLE \(context.state.hole) · PAR \(context.state.par)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(yardsText(context.state.toPinYds))
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .opacity(context.isStale ? 0.35 : 1)
                        Text("YDS · TO PIN")
                            .font(.system(size: 9, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale {
                        Text("OPEN STICKS TO REFRESH")
                            .font(.system(size: 11, weight: .bold))
                            .kerning(1.4)
                            .foregroundStyle(Color.sticksGold)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    } else {
                        HStack {
                            islandFlank(label: "FRONT", yards: context.state.frontYds)
                            Spacer()
                            HStack(spacing: 6) {
                                Text(progressText(context.state))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.sticksGold)
                                if let chip = toParText(context.state.myToPar) {
                                    Text(chip)
                                        .font(.system(size: 10, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.sticksGreenBright)
                                        .clipShape(Capsule())
                                }
                            }
                            Spacer()
                            islandFlank(label: "BACK", yards: context.state.backYds)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(Color.sticksGreenBright)
                    Text("\(context.state.hole)")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } compactTrailing: {
                Text(yardsText(context.state.toPinYds))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(context.isStale ? 0.4 : 1))
            } minimal: {
                Text(yardsText(context.state.toPinYds))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(context.isStale ? Color.white.opacity(0.4) : Color.sticksGreenBright)
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
            Text(yardsText(yards))
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Yardage, or an em dash when there's no GPS fix / no green mapped.
private func yardsText(_ yards: Int?) -> String {
    yards.map(String.init) ?? "—"
}

/// "12/18 SCORED".
private func progressText(_ state: RoundActivityAttributes.ContentState) -> String {
    "\(state.holesScored)/\(state.totalHoles) SCORED"
}

/// "+3" / "E" / "-1" — nil when myToPar is nil (spectators).
private func toParText(_ toPar: Int?) -> String? {
    guard let toPar else { return nil }
    if toPar == 0 { return "E" }
    return toPar > 0 ? "+\(toPar)" : "\(toPar)"
}

// MARK: - Lock screen / banner

private struct RoundLockScreenView: View {
    let context: ActivityViewContext<RoundActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(yardsText(context.state.toPinYds))
                            .font(.system(size: 40, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(Color.sticksInk)
                            .opacity(context.isStale ? 0.3 : 1)
                            .contentTransition(.numericText())
                        Text("YDS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.sticksMuted)
                    }
                    if context.isStale {
                        Text("OPEN STICKS TO REFRESH")
                            .font(.system(size: 9, weight: .bold))
                            .kerning(1)
                            .foregroundStyle(Color.sticksGreen)
                    } else {
                        Text("F \(yardsText(context.state.frontYds)) · B \(yardsText(context.state.backYds))")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.8)
                            .monospacedDigit()
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }

            // Bottom edge: thin progress strip + score chip.
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.sticksInk.opacity(0.12))
                        Capsule()
                            .fill(Color.sticksGreen)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 4)

                Text(progressText(context.state))
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color.sticksMuted)
                    .fixedSize()

                if let chip = toParText(context.state.myToPar) {
                    Text(chip)
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksCream)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.sticksGreen)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
    }

    private var progressFraction: CGFloat {
        guard context.state.totalHoles > 0 else { return 0 }
        return min(1, CGFloat(context.state.holesScored) / CGFloat(context.state.totalHoles))
    }
}
