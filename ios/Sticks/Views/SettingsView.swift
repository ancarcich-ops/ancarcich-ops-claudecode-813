//
//  SettingsView.swift
//  Sticks
//
//  Slice 12: minimal Settings tab — the signed-in identity, the app
//  version, and SIGN OUT, as a panel card list.
//

import SwiftUI

struct SettingsView: View {
    let user: User
    let session: SessionStore
    var tabSelection: Binding<SticksTab>? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(SticksFont.display(40, weight: .bold))
                            .kerning(-0.8)
                            .foregroundStyle(Color.sticksInk)

                        accountCard
                        aboutCard
                        signOutCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let tabSelection {
                    SticksTabBar(selection: tabSelection)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Cards

    private var accountCard: some View {
        panelCard {
            row(label: "NAME", value: user.displayName)
            hairline
            row(label: "USERNAME", value: "@\(user.username)")
        }
    }

    private var aboutCard: some View {
        panelCard {
            row(label: "VERSION", value: Self.versionText)
        }
    }

    private var signOutCard: some View {
        Button {
            session.signOut()
        } label: {
            Text("SIGN OUT")
                .font(SticksFont.mono(12))
                .kerning(1.2)
                .foregroundStyle(Color.sticksError)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Pieces

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

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(SticksFont.mono(10))
                .kerning(1)
                .foregroundStyle(Color.sticksFaint)
            Spacer()
            Text(value)
                .font(SticksFont.sans(15, weight: .medium))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.sticksHairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore()
    )
}
