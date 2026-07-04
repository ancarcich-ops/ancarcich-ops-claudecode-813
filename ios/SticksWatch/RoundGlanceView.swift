//
//  RoundGlanceView.swift
//  SticksWatch
//
//  Glanceable on-course readout: hole, par, front/center/back yardages,
//  and scoring progress — mirroring the phone's GPS screen.
//

import SwiftUI

struct RoundGlanceView: View {
    let snapshot: RoundSnapshot

    /// Snapshots older than this are treated as stale — the yardage is no
    /// longer trustworthy and must not be presented as live.
    private static let staleAfter: TimeInterval = 3 * 60

    var body: some View {
        // TimelineView re-evaluates staleness as time passes, even when no
        // fresh snapshot arrives from the phone (the exact case that matters).
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let isStale = context.date.timeIntervalSince(snapshot.updatedAt) > Self.staleAfter
            content(isStale: isStale)
        }
    }

    private func content(isStale: Bool) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                Text(snapshot.courseName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Color.sticksGreenBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("HOLE \(snapshot.hole) · PAR \(snapshot.par)")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.top, 2)

                Text(centerText)
                    .font(.system(size: 52, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .opacity(isStale ? 0.35 : 1)

                if isStale {
                    Text("OPEN STICKS ON IPHONE")
                        .font(.system(size: 9, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Color.sticksGold)
                } else {
                    Text("YDS TO CENTER")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    flank(label: "FRONT", yards: snapshot.frontYds)
                    flank(label: "BACK", yards: snapshot.backYds)
                }
                .padding(.top, 6)
                .opacity(isStale ? 0.35 : 1)

                Text(progressText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sticksGold)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: isStale)
        }
    }

    private var centerText: String {
        snapshot.centerYds.map(String.init) ?? "—"
    }

    /// "12/18 SCORED · +3" (the to-par suffix only when known).
    private var progressText: String {
        var text = "\(snapshot.holesScored)/\(snapshot.totalHoles) SCORED"
        if let toPar = snapshot.myToPar {
            let suffix = toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
            text += " · \(suffix)"
        }
        return text
    }

    private func flank(label: String, yards: Int?) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .kerning(1)
                .foregroundStyle(.secondary)
            Text(yards.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .monospacedDigit()
        }
    }
}
