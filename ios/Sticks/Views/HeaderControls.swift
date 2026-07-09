//
//  HeaderControls.swift
//  Sticks
//
//  Slice 31: the shared trailing header cluster — the group switcher
//  chip, the + New round capsule, and the avatar menu — used by all
//  four tabs so the controls sit in the same place everywhere.
//  TabHeaderBar wraps the cluster with a leading title for the
//  non-Home tabs.
//

import SwiftUI

struct HeaderControls: View {
    let user: User
    let session: SessionStore
    @Binding var showsCreate: Bool

    private var filter: GroupFilterStore { .shared }

    var body: some View {
        HStack(spacing: 8) {
            groupSwitcher

            newRoundButton
                .layoutPriority(1)

            avatarMenu
                .layoutPriority(1)
        }
    }

    // MARK: - Group switcher

    /// "All my groups ▾" (or the active group's name) — a light capsule
    /// chip opening the group menu. The active row carries a checkmark.
    private var groupSwitcher: some View {
        Menu {
            Button {
                filter.setActiveGroup(nil)
            } label: {
                if filter.activeGroupId == nil {
                    Label("All my groups", systemImage: "checkmark")
                } else {
                    Text("All my groups")
                }
            }

            ForEach(filter.groups) { group in
                Button {
                    filter.setActiveGroup(group.id)
                } label: {
                    if filter.activeGroupId == group.id {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.activeGroupName ?? "All my groups")
                    .font(SticksFont.sans(11.5, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(Color.sticksCard)
            .clipShape(.capsule)
            .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
            .contentShape(.capsule)
        }
        .accessibilityLabel("Group filter")
    }

    // MARK: - New round

    private var newRoundButton: some View {
        Button {
            showsCreate = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New round")
                    .font(SticksFont.sans(13.5, weight: .bold))
            }
            .foregroundStyle(Color.sticksCream)
            .padding(.horizontal, 13)
            .frame(height: 36)
            .background(Color.sticksGreen)
            .clipShape(.capsule)
        }
        .buttonStyle(NewRoundPressStyle())
        .accessibilityLabel("New round")
    }

    // MARK: - Avatar menu

    private var avatarMenu: some View {
        Menu {
            Section("@\(user.username)") {
                Button(role: .destructive) {
                    session.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Text(initials(of: user.displayName))
                .font(SticksFont.label(13, weight: .bold))
                .foregroundStyle(Color.sticksCream)
                .frame(width: 36, height: 36)
                .background(Color.sticksGreen)
                .clipShape(.circle)
        }
        .accessibilityLabel("Account menu")
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Tab header bar

/// The non-Home tabs' top header: the tab's title leading, the shared
/// HeaderControls trailing — same padding/background as Home's header
/// so all four tabs read as one system.
struct TabHeaderBar: View {
    let title: String
    let user: User
    let session: SessionStore
    @Binding var showsCreate: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(SticksFont.display(26, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: 6)

            HeaderControls(user: user, session: session, showsCreate: $showsCreate)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg.opacity(0.97))
    }
}

// MARK: - Press style

struct NewRoundPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
