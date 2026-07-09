//
//  RoundGlanceView.swift
//  SticksWatch
//
//  Interactive on-course readout: hole switching via chevrons flanking
//  the hole label, live yardages, and the wearer's score entry — all
//  proxied through the phone (the watch never talks to the network).
//

import SwiftUI
import WatchKit

struct RoundGlanceView: View {
    let snapshot: RoundSnapshot

    @Environment(PhoneSessionService.self) private var phoneSession
    /// Round index a hole switch is optimistically showing while the
    /// command is in flight — reverted on error/timeout, replaced by the
    /// reply snapshot on success.
    @State private var pendingHoleIndex: Int?
    /// Brief command failure notice ("CAN'T REACH IPHONE") shown in the
    /// status line, auto-dismissed.
    @State private var transientError: String?
    @State private var showScoreEntry = false

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
        .sheet(isPresented: $showScoreEntry) {
            WatchScoreEntryView(
                hole: snapshot.hole,
                par: snapshot.par,
                initialScore: snapshot.myScore
            )
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

                holeSwitcher
                    .padding(.top, 2)

                Group {
                    if pendingHoleIndex != nil {
                        ProgressView()
                            .tint(Color.sticksGreenBright)
                            .frame(height: 58)
                    } else {
                        Text(centerText)
                            .font(.system(size: 52, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .opacity(isStale ? 0.35 : 1)
                    }
                }

                statusLine(isStale: isStale)

                HStack(spacing: 18) {
                    flank(label: "FRONT", yards: snapshot.frontYds)
                    flank(label: "BACK", yards: snapshot.backYds)
                }
                .padding(.top, 6)
                .opacity(isStale || pendingHoleIndex != nil ? 0.35 : 1)

                // Spectators (no seat) never see score entry.
                if snapshot.isSeated {
                    scoreButton
                        .padding(.top, 8)
                }

                overallScore
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: isStale)
            .animation(.easeInOut(duration: 0.2), value: pendingHoleIndex)
        }
    }

    // MARK: - Hole switcher

    /// ‹ HOLE 7 › — chevrons switch the hole on the PHONE; the label
    /// changes optimistically and the reply snapshot settles it.
    private var holeSwitcher: some View {
        HStack(spacing: 6) {
            chevron("chevron.left", delta: -1)
            Text(holeLabel)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            chevron("chevron.right", delta: 1)
        }
    }

    private var holeLabel: String {
        if let pendingHoleIndex {
            // The watch has no course data — the target hole NUMBER is
            // derived from the current one (holes wrap 1–18); the target
            // par arrives with the reply snapshot.
            let delta = pendingHoleIndex - snapshot.holeIndex
            let hole = ((snapshot.hole - 1 + delta) % 18 + 18) % 18 + 1
            return "HOLE \(hole)"
        }
        return "HOLE \(snapshot.hole) · PAR \(snapshot.par)"
    }

    private func chevron(_ systemName: String, delta: Int) -> some View {
        let target = snapshot.holeIndex + delta
        let disabled = pendingHoleIndex != nil || target < 0 || target >= snapshot.totalHoles
        return Button {
            switchHole(to: target)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    private func switchHole(to target: Int) {
        guard pendingHoleIndex == nil,
              target >= 0, target < snapshot.totalHoles else { return }
        transientError = nil
        pendingHoleIndex = target
        WKInterfaceDevice.current().play(.click)
        Task {
            do {
                // Success merges the reply snapshot into phoneSession.
                _ = try await phoneSession.setHole(index: target)
            } catch {
                // The optimistic label never survives a failed send.
                showTransientError(for: error)
            }
            pendingHoleIndex = nil
        }
    }

    // MARK: - Status line

    /// Command errors > staleness > the normal yardage caption.
    @ViewBuilder
    private func statusLine(isStale: Bool) -> some View {
        if let transientError {
            Text(transientError)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(Color.sticksDanger.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        } else if isStale {
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
    }

    private func showTransientError(for error: Error) {
        WKInterfaceDevice.current().play(.failure)
        if case WatchCommandError.phone(let message) = error {
            transientError = message
        } else {
            transientError = "CAN'T REACH IPHONE"
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            transientError = nil
        }
    }

    // MARK: - Score button

    /// Shows the wearer's score on the current hole in its par-relative
    /// color, or a SCORE prompt — tapping opens the full-screen stepper.
    private var scoreButton: some View {
        Button {
            showScoreEntry = true
        } label: {
            HStack(spacing: 5) {
                if let score = snapshot.myScore {
                    Text("\(score)")
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .monospacedDigit()
                    Text(WatchScoreStyle.relativeLabel(for: score, par: snapshot.par))
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("SCORE")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(1.2)
                }
            }
            .foregroundStyle(scoreButtonStyle.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(scoreButtonStyle.background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var scoreButtonStyle: WatchScoreStyle {
        if let score = snapshot.myScore {
            return WatchScoreStyle.forScore(score, par: snapshot.par)
        }
        return WatchScoreStyle(background: .sticksGreen, text: .sticksCream)
    }

    // MARK: - Readout pieces

    private var centerText: String {
        snapshot.centerYds.map(String.init) ?? "—"
    }

    /// "OVERALL SCORE" caption over the wearer's running to-par ("+3" /
    /// "E" / "-1"), or an em dash before any hole is scored.
    private var overallScore: some View {
        VStack(spacing: 1) {
            Text("OVERALL SCORE")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            Text(overallScoreText)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.sticksGold)
        }
    }

    private var overallScoreText: String {
        guard let toPar = snapshot.myToPar else { return "—" }
        return toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
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
