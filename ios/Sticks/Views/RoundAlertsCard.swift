//
//  RoundAlertsCard.swift
//  Sticks
//
//  Slice 72: "Alerts for this round" — a per-round override so a match
//  you care about can buzz you even when you don't follow anyone in it
//  and your group is quiet by default. Three states: DEFAULT (your
//  account settings decide), ALL ALERTS (this round always sends), MUTE
//  (this round never sends). Mirrored to the server, which gates fanout.
//

import SwiftUI
import UIKit

struct RoundAlertsCard: View {
    let matchId: String

    private var store: RoundAlertsStore { .shared }
    private var push: PushNotificationService { .shared }

    var body: some View {
        let mode = store.mode(for: matchId)

        return VStack(alignment: .leading, spacing: 10) {
            Text("ALERTS FOR THIS ROUND")
                .font(SticksFont.label(11, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Color.sticksFaint)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(RoundAlertMode.allCases, id: \.self) { option in
                        chip(option, isActive: option == mode)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)

                Text(mode.caption)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, mode == .all && push.authState == .notDetermined ? 4 : 13)

                // Turning a round ON is meaningless without the system
                // permission — offer it right here instead of sending
                // the user to Settings.
                if mode == .all, push.authState == .notDetermined {
                    enablePermissionRow
                } else if mode == .all, push.authState == .denied {
                    permissionWarning
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(
                        mode == .all ? Color.sticksGreen.opacity(0.45) : Color.sticksHairline,
                        lineWidth: 1
                    )
            )
        }
        .padding(.top, 6)
        .task {
            await push.refreshAuthState()
            await store.refresh(matchId: matchId)
        }
    }

    // MARK: - Chips

    private func chip(_ option: RoundAlertMode, isActive: Bool) -> some View {
        Button {
            guard !isActive else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.16)) {
                store.setMode(option, for: matchId)
            }
            if option == .all, push.authState == .notDetermined {
                Task { await push.requestAuthorization() }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option.iconName)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(option.chipLabel)
                    .font(SticksFont.mono(10))
                    .kerning(0.6)
            }
            .foregroundStyle(isActive ? tint(option) : Color.sticksMuted)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isActive ? tint(option).opacity(0.14) : Color.sticksPanel2)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(
                    isActive ? tint(option).opacity(0.5) : Color.clear,
                    lineWidth: 1
                )
            )
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(option.chipLabel) alerts for this round")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tint(_ option: RoundAlertMode) -> Color {
        option == .mute ? Color.sticksError : Color.sticksGreen
    }

    // MARK: - Permission fallbacks

    private var enablePermissionRow: some View {
        Button {
            Task { await push.requestAuthorization() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 11, weight: .semibold))
                Text("TURN ON NOTIFICATIONS")
                    .font(SticksFont.mono(10))
                    .kerning(1.1)
            }
            .foregroundStyle(Color.sticksGreen)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.sticksBg)
            .clipShape(.capsule)
            .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, 14)
        .padding(.bottom, 13)
    }

    private var permissionWarning: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("NOTIFICATIONS ARE OFF IN IOS SETTINGS")
                    .font(SticksFont.mono(9.5))
                    .kerning(0.8)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.sticksError)
            .padding(.horizontal, 14)
            .padding(.bottom, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.sticksBg.ignoresSafeArea()
        RoundAlertsCard(matchId: "preview")
            .padding(20)
    }
}
