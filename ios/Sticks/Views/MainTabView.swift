//
//  MainTabView.swift
//  Sticks
//
//  Slice 12/15: the signed-in root — a 4-tab structure (Home / Groups /
//  Stats / Settings) with a custom cream tab bar. Each tab keeps its
//  own NavigationStack alive across switches.
//
//  Slice 29: the bar is owned HERE as a bottom safe-area inset over all
//  four stacks, so it persists on pushed screens (match detail, group
//  leaderboard). It hides only while the immersive on-course GPS screen
//  is up (via TabChrome). The inset also keeps scroll content from
//  hiding behind the bar on every screen automatically.
//

import SwiftUI
import UIKit

enum SticksTab: Hashable {
    case home
    case groups
    case stats
    case settings
}

struct MainTabView: View {
    let user: User
    let session: SessionStore

    @State private var selection: SticksTab = .home

    private var chrome: TabChrome { .shared }

    var body: some View {
        ZStack {
            MatchListView(user: user, session: session, tabSelection: $selection)
                .opacity(selection == .home ? 1 : 0)
                .allowsHitTesting(selection == .home)
                .accessibilityHidden(selection != .home)

            GroupsView(user: user, session: session, tabSelection: $selection)
                .opacity(selection == .groups ? 1 : 0)
                .allowsHitTesting(selection == .groups)
                .accessibilityHidden(selection != .groups)

            StatsView(user: user, session: session, tabSelection: $selection)
                .opacity(selection == .stats ? 1 : 0)
                .allowsHitTesting(selection == .stats)
                .accessibilityHidden(selection != .stats)

            SettingsView(user: user, session: session, tabSelection: $selection)
                .opacity(selection == .settings ? 1 : 0)
                .allowsHitTesting(selection == .settings)
                .accessibilityHidden(selection != .settings)
        }
        // The persistent bar — a safe-area inset so every screen's
        // scroll content (roots AND pushed screens) is inset above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chrome.hidesTabBar {
                SticksTabBar(selection: $selection)
            }
        }
        // Slice 13: hidden tabs stay mounted, so an open GPS screen on a
        // match with NO active round would keep foreground location
        // running after switching tabs. Stop it when HOME hides; resume
        // when HOME returns with the GPS screen still visible.
        .onChange(of: selection) { oldValue, newValue in
            if oldValue == .home {
                RoundSessionService.shared.homeTabHidden()
            } else if newValue == .home {
                RoundSessionService.shared.homeTabShown()
            }
        }
        // Slice 31: the header's group switcher must be populated on
        // every tab without visiting Groups first — load here, refresh
        // on matches/groups-changed signals.
        .task {
            await GroupFilterStore.shared.load(session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sticksMatchesDidChange)) { _ in
            Task { await GroupFilterStore.shared.load(session: session) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sticksGroupsDidChange)) { _ in
            Task { await GroupFilterStore.shared.load(session: session) }
        }
        // Slice 36: a round created from the match-detail header (or any
        // screen without a tab binding) still lands on Home, which owns
        // the push-to-new-match flow.
        .onReceive(NotificationCenter.default.publisher(for: .sticksOpenMatch)) { _ in
            selection = .home
        }
        // Slice 40: the header's Home pill on screens without a tab
        // binding (pushed match detail) pops itself, then asks us to
        // land on the Home tab.
        .onReceive(NotificationCenter.default.publisher(for: .sticksGoHome)) { _ in
            selection = .home
        }
    }
}

// MARK: - Tab bar

/// Custom bottom tab bar: panel at 94% over blur, 1pt top hairline,
/// 23pt stroke icons over DM Mono 9.5pt uppercase labels.
struct SticksTabBar: View {
    @Binding var selection: SticksTab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.home, icon: "house", label: "Home")
            tabButton(.groups, icon: "person.2", label: "Groups")
            tabButton(.stats, icon: "chart.bar", label: "Stats")
            tabButton(.settings, icon: "gearshape", label: "Settings")
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.sticksCard.opacity(0.94)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: SticksTab, icon: String, label: String) -> some View {
        let isActive = selection == tab
        return Button {
            guard selection != tab else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 23)

                Text(label)
                    .font(SticksFont.mono(9.5))
                    .kerning(0.95)
                    .textCase(.uppercase)
            }
            .foregroundStyle(isActive ? Color.sticksGreen : Color.sticksFaint)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

#Preview {
    MainTabView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore()
    )
}
