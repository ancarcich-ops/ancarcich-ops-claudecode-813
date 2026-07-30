//
//  WatchHealthCard.swift
//  Sticks
//
//  The Settings tab's APPLE WATCH & HEALTH section — the in-app home for
//  everything the app does with HealthKit and with background location.
//
//  Why it exists: App Review guideline 2.5.1 requires HealthKit usage to
//  be clearly identified in the UI, and 2.5.4 requires the persistent
//  location feature to be discoverable. Both are real features here (the
//  watch runs a Golf workout to stay on the wrist and save the round to
//  Health; the phone keeps GPS alive so lock-screen and wrist yardages
//  stay live), so this card states them plainly, shows live status, and
//  links out to the two system apps that control them.
//
//  Styling mirrors SettingsView's panel cards.
//

import SwiftUI
import UIKit
import WatchConnectivity

struct WatchHealthCard: View {
    /// Live pairing state, refreshed on appear and on every foreground.
    @State private var watchState: WatchPairingState = .unknown

    /// Whether a round is live right now — the card names the exact
    /// behavior that's running.
    private var isRoundLive: Bool { RoundSessionService.shared.isActive }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPLE WATCH & HEALTH")
                .font(SticksFont.mono(10))
                .kerning(1.2)
                .foregroundStyle(Color.sticksFaint)
                .padding(.leading, 2)

            panelCard {
                watchStatusRow
                hairline
                healthWorkoutBlock
                hairline
                backgroundLocationBlock
            }
        }
        .task { refreshWatchState() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            refreshWatchState()
        }
    }

    // MARK: - Watch status

    private var watchStatusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(watchState.isReady ? Color.sticksGreen : Color.sticksFaint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("APPLE WATCH")
                    .font(SticksFont.mono(12))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksInk)

                Text(watchState.caption)
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Circle()
                .fill(watchState.isReady ? Color.sticksGreen : Color.sticksFaint.opacity(0.5))
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - HealthKit identification (guideline 2.5.1)

    private var healthWorkoutBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sticksError)
                    .frame(width: 20)

                Text("HEALTH — GOLF WORKOUTS")
                    .font(SticksFont.mono(12))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksInk)

                Spacer(minLength: 8)

                if isRoundLive {
                    liveBadge("RECORDING")
                }
            }

            Text("When you start a round, the Sticks app on your Apple Watch starts a **Golf workout** in Health. That workout reads your heart rate, active energy, and walking distance while you play, saves the finished round to Health so it counts toward your Activity rings, and is what keeps Sticks on your wrist — a raised wrist comes straight back to your yardages instead of the watch face.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)

            Text("Your Apple Watch asks for Health permission the first time you start a round. Nothing is read or saved without it, and the round still scores normally if you decline.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openHealthApp()
            } label: {
                pillLabel("OPEN HEALTH", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Background location identification (guideline 2.5.4)

    private var backgroundLocationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 20)

                Text("LIVE GPS DURING A ROUND")
                    .font(SticksFont.mono(12))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksInk)

                Spacer(minLength: 8)

                if isRoundLive {
                    liveBadge("ON")
                }
            }

            Text("A round needs your position continuously — even with the phone in your pocket. Sticks keeps GPS running for the life of the round so the yardage on your lock screen widget and on your watch is the distance from where you're actually standing, and so the app advances to the next hole on its own when you walk off a green.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)

            Text("It starts when a round starts and stops the moment you finish — never between rounds. iOS shows its blue location indicator the whole time it's running.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openSystemSettings()
            } label: {
                pillLabel("LOCATION IN IOS SETTINGS", systemImage: "gearshape")
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func refreshWatchState() {
        watchState = WatchPairingState.current()
    }

    /// Opens the Health app to its Browse tab. Health owns the
    /// permission switches for Sticks (Sharing → Apps).
    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Pieces

    private func liveBadge(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(9, weight: .bold))
            .kerning(1)
            .foregroundStyle(Color.sticksCream)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Color.sticksGreen)
            .clipShape(.capsule)
    }

    private func pillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(SticksFont.mono(10))
                .kerning(1.1)
        }
        .foregroundStyle(Color.sticksGreen)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Color.sticksBg)
        .clipShape(.capsule)
        .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
        .contentShape(.capsule)
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.sticksHairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

// MARK: - Pairing state

/// Snapshot of WatchConnectivity pairing, reduced to the three states
/// worth showing a golfer.
enum WatchPairingState {
    /// Paired watch with SticksWatch installed — the full experience.
    case ready
    /// Paired, but the Sticks watch app isn't installed yet.
    case appMissing
    /// No paired watch (or this device can't pair — e.g. iPad).
    case notPaired
    /// WatchConnectivity hasn't activated yet.
    case unknown

    static func current() -> WatchPairingState {
        guard WCSession.isSupported() else { return .notPaired }
        let session = WCSession.default
        guard session.activationState == .activated else { return .unknown }
        guard session.isPaired else { return .notPaired }
        return session.isWatchAppInstalled ? .ready : .appMissing
    }

    var isReady: Bool { self == .ready }

    var caption: String {
        switch self {
        case .ready:
            "Paired and installed. Your watch shows live yardages, takes scores, and records the round in Health."
        case .appMissing:
            "Paired — install Sticks on your watch from the Watch app to get wrist yardages and Health workouts."
        case .notPaired:
            "No Apple Watch paired with this device. Wrist yardages and Health golf workouts need an iPhone with a paired Apple Watch."
        case .unknown:
            "Checking for a paired Apple Watch…"
        }
    }
}

#Preview {
    ZStack {
        Color.sticksBg.ignoresSafeArea()
        ScrollView {
            WatchHealthCard()
                .padding(20)
        }
    }
}
