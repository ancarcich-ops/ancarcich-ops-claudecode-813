//
//  WatchScoreEntryView.swift
//  SticksWatch
//
//  Full-screen score stepper for the wearer's own score: Digital Crown
//  and +/− adjust, the background is the par-relative ScoreStyle color
//  (matching the phone's language), a live OVERALL preview shows what
//  confirming does to the round total, and confirm sends the score
//  through the phone — a birdie or better fires a celebration before
//  the sheet dismisses.
//

import SwiftUI
import WatchKit

struct WatchScoreEntryView: View {
    let hole: Int
    let par: Int

    @Environment(PhoneSessionService.self) private var phoneSession
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: Int
    @State private var crownValue: Double
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isCelebrating = false

    private let initialScore: Int?
    /// Wearer's running to-par BEFORE this entry — feeds the OVERALL
    /// preview. Nil when no hole has been scored yet.
    private let overallToPar: Int?

    private static let maxStrokes = 20

    init(hole: Int, par: Int, initialScore: Int?, overallToPar: Int?) {
        self.hole = hole
        self.par = par
        self.initialScore = initialScore
        self.overallToPar = overallToPar
        let start = initialScore ?? par
        _strokes = State(initialValue: start)
        _crownValue = State(initialValue: Double(start))
    }

    private var style: WatchScoreStyle {
        WatchScoreStyle.forScore(strokes, par: par)
    }

    /// Round to-par IF this score is confirmed — replaces any existing
    /// score on this hole rather than double-counting it.
    private var projectedToPar: Int {
        var base = overallToPar ?? 0
        if let initialScore {
            base -= initialScore - par
        }
        return base + (strokes - par)
    }

    private var projectedToParText: String {
        projectedToPar == 0 ? "E" : (projectedToPar > 0 ? "+\(projectedToPar)" : "\(projectedToPar)")
    }

    /// Birdie or better celebrates; eagle+ (or an ace) goes gold.
    private var celebrationAccent: Color? {
        guard strokes - par <= -1 || strokes == 1 else { return nil }
        let isEagleOrBetter = strokes - par <= -2 || strokes == 1
        return isEagleOrBetter ? Color(red: 0.93, green: 0.75, blue: 0.35) : .sticksGreenBright
    }

    var body: some View {
        ZStack {
            style.background.ignoresSafeArea()

            VStack(spacing: 4) {
                Text("HOLE \(hole) · PAR \(par)")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(style.text.opacity(0.75))

                HStack(spacing: 12) {
                    adjustButton("minus", delta: -1)
                    Text("\(strokes)")
                        .font(.system(size: 50, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(style.text)
                        .frame(minWidth: 60)
                    adjustButton("plus", delta: 1)
                }

                Text(WatchScoreStyle.relativeLabel(for: strokes, par: par))
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(1.6)
                    .foregroundStyle(style.text)
                    .contentTransition(.opacity)

                overallPreview

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(style.text.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }

                confirmButton
                    .padding(.top, 4)
            }
            .opacity(isCelebrating ? 0 : 1)
            .animation(.easeOut(duration: 0.15), value: isCelebrating)

            if isCelebrating, let accent = celebrationAccent {
                ScoreCelebrationView(
                    accent: accent,
                    label: WatchScoreStyle.relativeLabel(for: strokes, par: par)
                )
            }
        }
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 1,
            through: Double(Self.maxStrokes),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            let value = min(max(Int(newValue.rounded()), 1), Self.maxStrokes)
            if value != strokes { strokes = value }
        }
        .animation(.easeInOut(duration: 0.2), value: strokes)
    }

    /// "OVERALL → +2" — what confirming does to the round total, live
    /// as the crown turns.
    private var overallPreview: some View {
        HStack(spacing: 4) {
            Text("OVERALL")
                .font(.system(size: 9, weight: .semibold))
                .kerning(1.2)
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
            Text(projectedToParText)
                .font(.system(size: 12, weight: .bold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(style.text.opacity(0.8))
        .padding(.top, 1)
    }

    private func adjustButton(_ systemName: String, delta: Int) -> some View {
        Button {
            setStrokes(strokes + delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(style.text)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSending || isCelebrating)
    }

    private func setStrokes(_ value: Int) {
        let clamped = min(max(value, 1), Self.maxStrokes)
        strokes = clamped
        crownValue = Double(clamped)
    }

    private var confirmButton: some View {
        Button {
            confirm()
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text(errorMessage == nil ? "CONFIRM" : "RETRY")
                        .font(.system(size: 13, weight: .heavy))
                        .kerning(1.6)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(.white.opacity(0.92))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSending || isCelebrating)
    }

    /// Sends the score to the phone; success = haptic + celebration if
    /// birdie-or-better + dismiss, error message with RETRY on failure —
    /// the spinner never outlives the command's 5s timeout.
    private func confirm() {
        guard !isSending, !isCelebrating else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                _ = try await phoneSession.sendScore(hole: hole, strokes: strokes)
                isSending = false
                if celebrationAccent != nil {
                    celebrate()
                } else {
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                }
            } catch WatchCommandError.phone(let message) {
                errorMessage = message
                WKInterfaceDevice.current().play(.failure)
                isSending = false
            } catch {
                errorMessage = "Can't reach iPhone. Try again."
                WKInterfaceDevice.current().play(.failure)
                isSending = false
            }
        }
    }

    /// Ring burst + particles + a tiered haptic pattern (birdie "chirp",
    /// eagle flourish), then auto-dismiss.
    private func celebrate() {
        let isEagleOrBetter = strokes - par <= -2 || strokes == 1
        isCelebrating = true
        playCelebrationHaptics(eagle: isEagleOrBetter)
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            dismiss()
        }
    }

    private func playCelebrationHaptics(eagle: Bool) {
        let device = WKInterfaceDevice.current()
        device.play(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            device.play(eagle ? .directionUp : .click)
            if eagle {
                try? await Task.sleep(for: .milliseconds(200))
                device.play(.success)
            }
        }
    }
}
