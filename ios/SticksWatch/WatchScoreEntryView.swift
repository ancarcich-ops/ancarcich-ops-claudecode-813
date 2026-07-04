//
//  WatchScoreEntryView.swift
//  SticksWatch
//
//  Full-screen score stepper for the wearer's own score: Digital Crown
//  and +/− adjust, the background is the par-relative ScoreStyle color
//  (matching the phone's language), confirm sends the score through the
//  phone and dismisses on success.
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

    private static let maxStrokes = 20

    init(hole: Int, par: Int, initialScore: Int?) {
        self.hole = hole
        self.par = par
        let start = initialScore ?? par
        _strokes = State(initialValue: start)
        _crownValue = State(initialValue: Double(start))
    }

    private var style: WatchScoreStyle {
        WatchScoreStyle.forScore(strokes, par: par)
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
                        .font(.system(size: 46, weight: .semibold, design: .serif))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(style.text)
                        .frame(minWidth: 56)
                    adjustButton("plus", delta: 1)
                }

                Text(WatchScoreStyle.relativeLabel(for: strokes, par: par))
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(1.6)
                    .foregroundStyle(style.text)
                    .contentTransition(.opacity)

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
        .disabled(isSending)
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
        .disabled(isSending)
    }

    /// Sends the score to the phone; success haptic + dismiss on reply,
    /// error message with RETRY on failure — the spinner never outlives
    /// the command's 5s timeout.
    private func confirm() {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                _ = try await phoneSession.sendScore(hole: hole, strokes: strokes)
                WKInterfaceDevice.current().play(.success)
                dismiss()
            } catch WatchCommandError.phone(let message) {
                errorMessage = message
                WKInterfaceDevice.current().play(.failure)
            } catch {
                errorMessage = "Can't reach iPhone. Try again."
                WKInterfaceDevice.current().play(.failure)
            }
            isSending = false
        }
    }
}
