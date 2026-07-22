//
//  RoundGlanceView.swift
//  SticksWatch
//
//  Direction A — "Rangefinder". The purest read: no ring, no ornament.
//  Course name · hole switcher pill · hero center yardage · flanks ·
//  score pill · OVERALL to-par at the base. The Digital Crown scrubs
//  holes (haptic detent per hole) alongside the chevrons; switching is
//  optimistic and reverts on failure. In always-on wrist-down the chrome
//  recedes and the yardage + to-par persist, dimmed.
//

import SwiftUI
import WatchKit

struct RoundGlanceView: View {
    let snapshot: RoundSnapshot

    @Environment(PhoneSessionService.self) private var phoneSession
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// Round index a hole switch is optimistically showing while the
    /// command is in flight — reverted on error/timeout, replaced by the
    /// reply snapshot on success.
    @State private var pendingHoleIndex: Int?
    /// Crown position in round-index space; drives the same optimistic
    /// switch path as the chevrons, debounced so scrubbing several holes
    /// sends one command.
    @State private var crownHole: Double = 0
    @State private var commitTask: Task<Void, Never>?
    @State private var commitGeneration = 0
    /// Brief command failure notice ("CAN'T REACH IPHONE") shown in the
    /// status line, auto-dismissed.
    @State private var transientError: String?
    @State private var showScoreEntry = false

    /// Snapshots older than this are treated as stale — the yardage is no
    /// longer trustworthy and must not be presented as live.
    private static let staleAfter: TimeInterval = 3 * 60
    /// How long the crown rests on a hole before the switch is committed.
    private static let crownSettleDelay: Duration = .milliseconds(350)

    var body: some View {
        // TimelineView re-evaluates staleness as time passes, even when no
        // fresh snapshot arrives from the phone (the exact case that matters).
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let isStale = context.date.timeIntervalSince(snapshot.updatedAt) > Self.staleAfter
            content(isStale: isStale)
        }
        .focusable()
        .digitalCrownRotation(
            $crownHole,
            from: 0,
            through: Double(max(snapshot.totalHoles - 1, 0)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownHole) { _, newValue in
            crownMoved(to: newValue)
        }
        .onChange(of: snapshot.holeIndex) { _, newIndex in
            // The phone settled the hole (reply or its own push) — resync
            // the crown unless the wearer is mid-scrub.
            if pendingHoleIndex == nil {
                crownHole = Double(newIndex)
            }
        }
        .onAppear {
            crownHole = Double(snapshot.holeIndex)
        }
        .sheet(isPresented: $showScoreEntry) {
            WatchScoreEntryView(
                hole: snapshot.hole,
                par: snapshot.par,
                initialScore: snapshot.myScore,
                overallToPar: snapshot.myToPar
            )
        }
    }

    private func content(isStale: Bool) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                Text(snapshot.courseName.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(isLuminanceReduced ? Color.white.opacity(0.35) : Color.sticksGreenBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                holeSwitcher
                    .padding(.top, 2)

                Group {
                    if pendingHoleIndex != nil {
                        ProgressView()
                            .tint(Color.sticksGreenBright)
                            .frame(height: 66)
                    } else {
                        Text(centerText)
                            .font(.system(size: 62, weight: .semibold, design: .serif))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                            .opacity(heroOpacity(isStale: isStale))
                    }
                }

                if !isLuminanceReduced {
                    statusLine(isStale: isStale)
                }

                HStack(spacing: 20) {
                    flank(label: "FRONT", yards: snapshot.frontYds)
                    flank(label: "BACK", yards: snapshot.backYds)
                }
                .padding(.top, 5)
                .opacity(heroOpacity(isStale: isStale))

                // Spectators (no seat) never see score entry; wrist-down
                // drops it too — chrome recedes in always-on.
                if snapshot.isSeated && !isLuminanceReduced {
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

    /// Stale and pending both dim the live numbers; wrist-down dims them
    /// further but keeps them readable — the whole point of always-on.
    private func heroOpacity(isStale: Bool) -> Double {
        if isStale || pendingHoleIndex != nil { return 0.35 }
        return isLuminanceReduced ? 0.55 : 1
    }

    // MARK: - Hole switcher

    /// ‹ HOLE 7 · PAR 4 › pill — chevrons switch the hole on the PHONE;
    /// the label changes optimistically and the reply snapshot settles it.
    /// Wrist-down the chevrons and pill chrome drop; the label persists.
    @ViewBuilder
    private var holeSwitcher: some View {
        if isLuminanceReduced {
            Text(holeLabel)
                .font(.system(size: 13, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            HStack(spacing: 2) {
                chevron("chevron.left", delta: -1)
                Text(holeLabel)
                    .font(.system(size: 13, weight: .bold))
                    .kerning(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                chevron("chevron.right", delta: 1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
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
        let target = displayedHoleIndex + delta
        let disabled = target < 0 || target >= snapshot.totalHoles
        return Button {
            WKInterfaceDevice.current().play(.click)
            crownHole = Double(target)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }

    // MARK: - Hole switching (crown + chevrons share this path)

    private var displayedHoleIndex: Int {
        pendingHoleIndex ?? snapshot.holeIndex
    }

    /// Optimistic label immediately; the command fires once the crown
    /// settles so scrubbing 7 holes sends one setHole, not seven.
    private func crownMoved(to value: Double) {
        let target = min(max(Int(value.rounded()), 0), max(snapshot.totalHoles - 1, 0))
        guard target != displayedHoleIndex else { return }
        transientError = nil
        pendingHoleIndex = target
        commitTask?.cancel()
        commitTask = Task {
            try? await Task.sleep(for: Self.crownSettleDelay)
            guard !Task.isCancelled else { return }
            await commit(target)
        }
    }

    private func commit(_ target: Int) async {
        guard target != snapshot.holeIndex else {
            pendingHoleIndex = nil
            return
        }
        commitGeneration += 1
        let generation = commitGeneration
        do {
            // Success merges the reply snapshot into phoneSession.
            _ = try await phoneSession.setHole(index: target)
            if generation == commitGeneration {
                pendingHoleIndex = nil
            }
        } catch {
            // The optimistic label never survives a failed send.
            if generation == commitGeneration {
                pendingHoleIndex = nil
                crownHole = Double(snapshot.holeIndex)
                showTransientError(for: error)
            }
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

    /// "OVERALL" caption over the wearer's running to-par ("+3" / "E" /
    /// "-1"), gold, pinned to the base — desaturated wrist-down.
    private var overallScore: some View {
        VStack(spacing: 1) {
            Text("OVERALL")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.secondary)
            Text(overallScoreText)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isLuminanceReduced ? Color.sticksGold.opacity(0.55) : Color.sticksGold)
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
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .monospacedDigit()
        }
    }
}
