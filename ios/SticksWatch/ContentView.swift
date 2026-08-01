//
//  ContentView.swift
//  SticksWatch
//
//  Shows the live round pushed from the iPhone, or a branded resting
//  state when no round is active.
//

import SwiftUI

struct ContentView: View {
    @Environment(PhoneSessionService.self) private var phoneSession

    private var consent: WorkoutConsentStore { WorkoutConsentStore.shared }

    var body: some View {
        Group {
            if let snapshot = phoneSession.snapshot {
                RoundGlanceView(snapshot: snapshot)
            } else {
                noRound
            }
        }
        // Asked once per round, before any Health recording begins.
        .sheet(isPresented: askingBinding) {
            WorkoutConsentView(mode: .prompt)
        }
    }

    private var askingBinding: Binding<Bool> {
        Binding(
            get: { WorkoutConsentStore.shared.isAsking },
            set: { isPresented in
                // Swiped away without choosing — treat as "not now" for
                // this round, without changing the saved default.
                if !isPresented, WorkoutConsentStore.shared.isAsking {
                    WorkoutConsentStore.shared.decline(remember: false)
                }
            }
        )
    }

    private var noRound: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.sticksGreenBright)
            Text("Sticks")
                .font(.system(size: 22, weight: .semibold, design: .serif))
            Text("Open a round on your iPhone to see live yardages here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // HealthKit stays identified even before a round exists.
            HStack(spacing: 4) {
                Image(systemName: "heart")
                    .font(.system(size: 8, weight: .bold))
                Text("GOLF WORKOUT · HEALTH")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08))
            .clipShape(Capsule())
            .accessibilityLabel("Rounds can be recorded as a golf workout in Health")
        }
        .padding(.horizontal, 8)
    }
}
