//
//  MainTabView.swift
//  Sticks
//
//  Slice 12/15: the signed-in root — a 4-tab structure (Home / Groups /
//  Stats / Settings) with a custom cream tab bar. Each tab keeps its
//  own NavigationStack alive across switches; the bar lives on each
//  tab's ROOT screen only, so pushed screens (match detail, GPS) stay
//  full-bleed exactly as before.
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

    var body: some View {
        ZStack {
            MatchListView(user: user, session: session, tabSelection: $selection)
                .opacity(selection == .home ? 1 : 0)
                .allowsHitTesting(selection == .home)
                .accessibilityHidden(selection != .home)

            GroupsView(session: session, tabSelection: $selection)
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
