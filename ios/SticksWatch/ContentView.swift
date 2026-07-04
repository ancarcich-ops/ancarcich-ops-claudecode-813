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

    var body: some View {
        Group {
            if let snapshot = phoneSession.snapshot {
                RoundGlanceView(snapshot: snapshot)
            } else {
                noRound
            }
        }
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
        }
        .padding(.horizontal, 8)
    }
}
