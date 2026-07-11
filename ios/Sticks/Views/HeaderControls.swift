//
//  HeaderControls.swift
//  Sticks
//
//  Slice 31: the shared trailing header cluster used by all four tabs
//  so the controls sit in the same place everywhere. TabHeaderBar wraps
//  the cluster with a leading title for the non-Home tabs.
//  Slice 33: web-parity — [+ New round] first, then the group switcher,
//  which now doubles as the account menu (groups + "Signed in as
//  @username" + Sign out); the standalone avatar circle is gone.
//  Slice 37: the menu matches the website's switcher — View (All my
//  groups / Public only) and My groups sections with headers, nav
//  links (leaderboard / Personal stats / Manage groups / Settings)
//  when a tab binding is available, then the account section.
//  Slice 40: web-parity Home ghost pill leads the cluster —
//  [Home] [+ New round] [All my groups ▾]. On tab roots it selects
//  the Home tab; on pushed screens without a tab binding (match
//  detail) it pops back and asks MainTabView to switch to Home.
//

import SwiftUI

extension Notification.Name {
    /// Posted by the switcher's "{group} leaderboard" link; the Groups
    /// tab listens and pushes that group's leaderboard.
    static let sticksOpenGroupLeaderboard = Notification.Name("sticksOpenGroupLeaderboard")

    /// Posted by the header's Home button on screens without a tab
    /// binding (pushed match detail); MainTabView selects the Home tab.
    static let sticksGoHome = Notification.Name("sticksGoHome")
}

struct HeaderControls: View {
    let user: User
    let session: SessionStore
    @Binding var showsCreate: Bool
    /// Drives the menu's nav links (Personal stats / Manage groups /
    /// Settings / leaderboard). nil on pushed screens without a tab
    /// binding (match detail) — those links are omitted there.
    var tabSelection: Binding<SticksTab>? = nil

    @Environment(\.dismiss) private var dismiss

    private var filter: GroupFilterStore { .shared }

    var body: some View {
        HStack(spacing: 9) {
            homeButton
                .layoutPriority(1)

            newRoundButton
                .layoutPriority(1)

            groupSwitcher
                .layoutPriority(1)
        }
    }

    // MARK: - Home

    /// Web-parity ghost pill: card fill, hairline border, ink text —
    /// deliberately NOT the green CTA fill. On tab roots it flips the
    /// tab selection to Home (no-op if already there); on pushed
    /// screens with no binding it pops, then MainTabView switches tabs.
    private var homeButton: some View {
        Button {
            if let tabSelection {
                tabSelection.wrappedValue = .home
            } else {
                dismiss()
                NotificationCenter.default.post(name: .sticksGoHome, object: nil)
            }
        } label: {
            Text("Home")
                .font(SticksFont.sans(13.5, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(Color.sticksCard)
                .clipShape(.capsule)
                .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(NewRoundPressStyle())
        .accessibilityLabel("Home")
    }

    // MARK: - Group switcher (+ account menu)

    /// The capsule chip opening the switcher menu — sectioned like the
    /// website: View (All my groups / Public only), My groups, nav
    /// links, then the account ("Signed in as @username" + Sign out).
    private var groupSwitcher: some View {
        Menu {
            viewSection

            if !filter.groups.isEmpty {
                myGroupsSection
            }

            if let tabSelection {
                navSection(tabSelection)
            }

            Section("Signed in as @\(user.username)") {
                Button(role: .destructive) {
                    session.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            HStack(spacing: 4) {
                switcherLabel

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
        .accessibilityLabel("Group filter and account menu")
    }

    /// VIEW — the two scope rows; the active one carries a checkmark.
    private var viewSection: some View {
        Section("View") {
            Button {
                filter.setMode(.all)
            } label: {
                if filter.mode == .all {
                    Label("All my groups", systemImage: "checkmark")
                } else {
                    Text("All my groups")
                }
            }

            Button {
                filter.setMode(.publicOnly)
            } label: {
                if filter.isPublicOnly {
                    Label("Public only", systemImage: "checkmark")
                } else {
                    Text("Public only")
                }
            }
        }
    }

    /// MY GROUPS — one row per group, checkmark on the active one.
    private var myGroupsSection: some View {
        Section("My groups") {
            ForEach(filter.groups) { group in
                Button {
                    filter.setMode(.group(group.id))
                } label: {
                    if filter.activeGroupId == group.id {
                        Label(group.name, systemImage: "checkmark")
                    } else {
                        Text(group.name)
                    }
                }
            }
        }
    }

    /// Nav links — {active group} leaderboard (when one is selected),
    /// Personal stats, Manage groups, Settings.
    private func navSection(_ tabSelection: Binding<SticksTab>) -> some View {
        Section {
            if let group = filter.activeGroup {
                Button {
                    tabSelection.wrappedValue = .groups
                    NotificationCenter.default.post(
                        name: .sticksOpenGroupLeaderboard,
                        object: nil,
                        userInfo: ["groupId": group.id]
                    )
                } label: {
                    Label("\(group.name) leaderboard", systemImage: "chart.bar")
                }
            }

            Button {
                tabSelection.wrappedValue = .stats
            } label: {
                Label("Personal stats", systemImage: "chart.line.uptrend.xyaxis")
            }

            Button {
                tabSelection.wrappedValue = .groups
            } label: {
                Label("Manage groups", systemImage: "person.2")
            }

            Button {
                tabSelection.wrappedValue = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    /// The default "All my groups" never truncates (fixedSize); an
    /// active group's name may tail-truncate past ~140pt.
    @ViewBuilder private var switcherLabel: some View {
        if let name = filter.activeGroupName {
            Text(name)
                .font(SticksFont.sans(11.5, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(filter.isPublicOnly ? "Public only" : "All my groups")
                .font(SticksFont.sans(11.5, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .fixedSize()
        }
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
    @Binding var tabSelection: SticksTab

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

            HeaderControls(
                user: user,
                session: session,
                showsCreate: $showsCreate,
                tabSelection: $tabSelection
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg)
        .overlay(alignment: .bottom) {
            Color.sticksHairline.frame(height: 1)
        }
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
