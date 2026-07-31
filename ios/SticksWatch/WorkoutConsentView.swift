//
//  WorkoutConsentView.swift
//  SticksWatch
//
//  The "Track this round in Health?" sheet. Shown once per round when the
//  saved mode is .ask, and reachable any time from the Health badge on
//  the round screen to start, stop, or change the default.
//

import SwiftUI
import WatchKit

struct WorkoutConsentView: View {
    enum Mode {
        /// First prompt of a round — yes/no, with a remember toggle.
        case prompt
        /// Opened from the badge mid-round — start/stop + default picker.
        case manage
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @State private var remember = false

    private var consent: WorkoutConsentStore { WorkoutConsentStore.shared }
    private var isRunning: Bool { WorkoutKeepAliveService.shared.isRunning }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                Text("Records heart rate, energy, and distance to Health, credits your rings — and keeps Sticks on your wrist so a raised wrist shows your yardage instead of the watch face.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch mode {
                case .prompt: promptButtons
                case .manage: manageControls
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.sticksDanger)
                Text("HEALTH")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(.secondary)
            }
            Text(mode == .prompt ? "Track this round as a Golf workout?" : "Golf workout")
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Prompt

    private var promptButtons: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $remember) {
                Text("Remember my choice")
                    .font(.system(size: 12))
            }
            .tint(Color.sticksGreenBright)

            Button {
                WKInterfaceDevice.current().play(.success)
                consent.accept(remember: remember)
                dismiss()
            } label: {
                Text("Start Workout")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Color.sticksGreenBright)

            Button {
                consent.decline(remember: remember)
                dismiss()
            } label: {
                Text(remember ? "Never Track" : "Not Now")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .tint(.gray)

            Text("You can start it later from the Health badge on the round screen.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Manage

    private var manageControls: some View {
        VStack(spacing: 8) {
            if isRunning {
                Button {
                    consent.stopManually()
                    dismiss()
                } label: {
                    Text("Stop & Save Workout")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.sticksDanger)
            } else {
                Button {
                    WKInterfaceDevice.current().play(.success)
                    consent.startManually()
                    dismiss()
                } label: {
                    Text("Start Workout")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.sticksGreenBright)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("WHEN A ROUND STARTS")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(.secondary)

                Picker("When a round starts", selection: modeBinding) {
                    ForEach(WorkoutConsent.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .frame(height: 70)
            }
        }
    }

    private var modeBinding: Binding<WorkoutConsent> {
        Binding(
            get: { WorkoutConsentStore.shared.mode },
            set: { WorkoutConsentStore.shared.mode = $0 }
        )
    }
}

#Preview {
    WorkoutConsentView(mode: .prompt)
}
