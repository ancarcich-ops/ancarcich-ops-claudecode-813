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

    var body: some View {
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

                Text("YDS TO CENTER")
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 18) {
                    flank(label: "FRONT", yards: snapshot.frontYds)
                    flank(label: "BACK", yards: snapshot.backYds)
                }
                .padding(.top, 6)

                Text(progressText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sticksGold)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
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
