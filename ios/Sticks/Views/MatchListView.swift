//
//  MatchListView.swift
//  Sticks
//
//  The signed-in home screen. Groups matches into Live / Upcoming /
//  Recent with pull-to-refresh; each match renders as a status-aware
//  card (MatchCardView) and the whole card navigates to the detail.
//

import SwiftUI

struct MatchListView: View {
    let user: User
    let session: SessionStore
    @Binding var tabSelection: SticksTab

    @State private var viewModel = MatchListViewModel()
    @State private var path = NavigationPath()
    @State private var showsCreate = false

    private var groupFilter: GroupFilterStore { .shared }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    loadingView
                case .failed(let message):
                    failedView(message)
                case .loaded:
                    if visibleMatches.isEmpty {
                        switch groupFilter.mode {
                        case .all:
                            emptyView
                        case .publicOnly:
                            filterEmptyView(
                                title: "No public rounds yet.",
                                subtitle: "Rounds without a group show here. Start\none with + New round, or switch the filter up top."
                            )
                        case .group:
                            filterEmptyView(
                                title: "No rounds in this group yet.",
                                subtitle: "Start one with + New round, or switch\nback to All my groups up top."
                            )
                        }
                    } else {
                        matchList
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationDestination(for: MatchSummary.self) { match in
                MatchDetailView(match: match, session: session)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showsCreate) {
            CreateMatchView(user: user, session: session) { matchId in
                showsCreate = false
                Task { await openCreatedMatch(id: matchId) }
            }
        }
        .task {
            await viewModel.load(session: session, group: groupFilter.groupQueryValue)
        }
        // Slice 38: the switcher drives the fetch — the server computes
        // cross-group visibility (a group's feed includes rounds its
        // members played elsewhere), which the client can't replicate.
        // The previous list keeps showing while the refetch is in flight.
        .onChange(of: groupFilter.mode) { _, _ in
            Task { await viewModel.load(session: session, group: groupFilter.groupQueryValue) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sticksMatchesDidChange)) { _ in
            Task { await viewModel.load(session: session, group: groupFilter.groupQueryValue) }
        }
        // A round created from a non-Home tab: reload and push its detail,
        // exactly like Home's own create flow.
        .onReceive(NotificationCenter.default.publisher(for: .sticksOpenMatch)) { note in
            guard let matchId = note.userInfo?["matchId"] as? String else { return }
            Task { await openCreatedMatch(id: matchId) }
        }
        // Slice 42: the welcome flow's "New round" CTA opens the create
        // wizard, exactly like + New round in the header.
        .onReceive(NotificationCenter.default.publisher(for: .sticksStartNewRound)) { _ in
            showsCreate = true
        }
    }

    // MARK: - Feed scope

    // Slice 38: no client-side group filtering — GET /matches?group=
    // already returns the exact set the website shows for the active
    // scope, so the view model's lists render as-is.
    private var visibleMatches: [MatchSummary] { viewModel.matches }
    private var liveMatches: [MatchSummary] { viewModel.liveMatches }
    private var upcomingMatches: [MatchSummary] { viewModel.upcomingMatches }
    private var recentMatches: [MatchSummary] { viewModel.recentMatches }

    /// After a successful POST /matches: refresh the list and push the
    /// new match's detail so the GPS screen is one tap away. If the
    /// active scope excludes the new round (e.g. Public only + a group
    /// round), a one-off unscoped fetch still finds it to open.
    private func openCreatedMatch(id: String) async {
        await viewModel.load(session: session, group: groupFilter.groupQueryValue)
        if let match = viewModel.matches.first(where: { $0.id == id }) {
            path.append(match)
        } else if let token = session.token,
                  let match = (try? await APIClient.shared.matches(token: token))?
                      .matches.first(where: { $0.id == id }) {
            path.append(match)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                SticksClubsMark()
                    .frame(width: 34, height: 34)

                (Text("Sticks").foregroundStyle(Color.sticksInk)
                    + Text(".").foregroundStyle(Color.sticksGreen))
                    .font(SticksFont.display(30))
                    .lineLimit(1)
            }
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

    // MARK: - List

    private var matchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !liveMatches.isEmpty {
                    matchSection(
                        title: "Live",
                        matches: liveMatches,
                        showsLiveDot: true
                    )
                }
                if !upcomingMatches.isEmpty {
                    matchSection(title: "Upcoming", matches: upcomingMatches)
                }
                if !recentMatches.isEmpty {
                    matchSection(title: "Recent", matches: recentMatches)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(session: session, group: groupFilter.groupQueryValue)
        }
    }

    private func matchSection(
        title: String,
        matches: [MatchSummary],
        showsLiveDot: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if showsLiveDot {
                    PulsingDot()
                }
                Text(title)
                    .font(SticksFont.label(12))
                    .kerning(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(showsLiveDot ? Color.sticksGreen : Color.sticksMuted)
            }
            .padding(.leading, 4)

            ForEach(matches) { match in
                NavigationLink(value: match) {
                    MatchCardView(match: match)
                }
                .buttonStyle(MatchCardButtonStyle())
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading matches…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text("No matches yet")
                .font(SticksFont.display(24))
                .foregroundStyle(Color.sticksInk)
            Text("Tap + New round up top to set up\nyour first match.")
                .font(SticksFont.sans(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.horizontal, 40)
    }

    /// The active filter has no rounds — the switcher stays up top so
    /// the user can flip back to "All my groups".
    private func filterEmptyView(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(title)
                .font(SticksFont.display(22))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
            Text(subtitle)
                .font(SticksFont.sans(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.horizontal, 40)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.load(session: session, group: groupFilter.groupQueryValue) }
            } label: {
                Text("Try Again")
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksCream)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

}

// MARK: - Pieces

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct MatchCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    MatchListView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore(),
        tabSelection: .constant(.home)
    )
}
