//
//  NotificationSettingsCard.swift
//  Sticks
//
//  Slice 71: the Settings tab's NOTIFICATIONS section. Shows the
//  system permission state (enable button / "off in iOS Settings"
//  escape hatch) and the five per-category toggles, mirrored to the
//  server so fanout respects them. Styling matches SettingsView's
//  panel cards.
//

import SwiftUI
import UIKit

struct NotificationSettingsCard: View {
    private var push: PushNotificationService { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTIFICATIONS")
                .font(SticksFont.mono(10))
                .kerning(1.2)
                .foregroundStyle(Color.sticksFaint)
                .padding(.leading, 2)

            panelCard {
                statusRow

                // Slice 93: every category the server can send, in the
                // app's display order — unknown keys render too (with a
                // humanized label), so a new server category is never a
                // missing toggle.
                ForEach(Array(prefRows.enumerated()), id: \.element.key) { index, row in
                    if index > 0 { hairline }
                    toggleRow(label: row.label, caption: row.caption, key: row.key)
                }

                Text("Round alerts cover everyone you follow and everyone you share a group with — any round they play, never your own scores.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .task {
            await push.refreshAuthState()
        }
        // Coming back from the iOS Settings app — re-read permission.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await push.refreshAuthState() }
        }
    }

    // MARK: - Permission status

    @ViewBuilder private var statusRow: some View {
        switch push.authState {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications are off for Sticks in iOS Settings.")
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksInk)

                Button {
                    openSystemSettings()
                } label: {
                    Text("OPEN IOS SETTINGS")
                        .font(SticksFont.mono(10))
                        .kerning(1.1)
                        .foregroundStyle(Color.sticksGreen)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color.sticksBg)
                        .clipShape(.capsule)
                        .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
                        .contentShape(.capsule)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            hairline

        case .notDetermined:
            Button {
                Task { await push.requestAuthorization() }
            } label: {
                HStack {
                    Text("ENABLE NOTIFICATIONS")
                        .font(SticksFont.mono(12))
                        .kerning(1.2)
                        .foregroundStyle(Color.sticksGreen)

                    Spacer()

                    Image(systemName: "bell.badge")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sticksGreen)
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle())
            hairline

        case .authorized, .unknown:
            EmptyView()
        }
    }

    // MARK: - Category toggles

    /// The rows to render: the app's known categories in display order,
    /// then any server keys the app doesn't know yet (sorted, with a
    /// humanized label and a generic caption).
    private var prefRows: [(key: String, label: String, caption: String)] {
        let known = PushPrefs.categories
        let knownKeys = Set(known.map(\.key))
        let extras = push.prefs.values.keys
            .filter { !knownKeys.contains($0) }
            .sorted()
            .map { key in
                (
                    key: key,
                    label: key
                        .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
                        .uppercased(),
                    caption: "Get notified when this happens."
                )
            }
        return known + extras
    }

    private func toggleRow(
        label: String,
        caption: String,
        key: String
    ) -> some View {
        let enabled = push.authState != .denied
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(label)
                    .font(SticksFont.mono(12))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                Toggle("", isOn: prefBinding(key))
                    .labelsHidden()
                    .tint(Color.sticksGreen)
                    .disabled(!enabled)
            }

            Text(caption)
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(enabled ? 1 : 0.5)
    }

    private func prefBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { push.prefs[key] },
            set: { push.setPref(key, to: $0) }
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Pieces (mirrors SettingsView's card styling)

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

#Preview {
    ZStack {
        Color.sticksBg.ignoresSafeArea()
        NotificationSettingsCard()
            .padding(20)
    }
}
