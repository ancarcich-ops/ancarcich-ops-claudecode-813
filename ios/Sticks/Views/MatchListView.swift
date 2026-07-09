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
                        if groupFilter.activeGroupId != nil {
                            groupEmptyView
                        } else {
                            emptyView
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
            await viewModel.load(session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sticksMatchesDidChange)) { _ in
            Task { await viewModel.load(session: session) }
        }
        // A round created from a non-Home tab: reload and push its detail,
        // exactly like Home's own create flow.
        .onReceive(NotificationCenter.default.publisher(for: .sticksOpenMatch)) { note in
            guard let matchId = note.userInfo?["matchId"] as? String else { return }
            Task { await openCreatedMatch(id: matchId) }
        }
    }

    // MARK: - Group filter

    /// Slice 31: the header switcher scopes the feed — nil shows all.
    private func filtered(_ matches: [MatchSummary]) -> [MatchSummary] {
        guard let groupId = groupFilter.activeGroupId else { return matches }
        return matches.filter { $0.groupId == groupId }
    }

    private var visibleMatches: [MatchSummary] { filtered(viewModel.matches) }
    private var liveMatches: [MatchSummary] { filtered(viewModel.liveMatches) }
    private var upcomingMatches: [MatchSummary] { filtered(viewModel.upcomingMatches) }
    private var recentMatches: [MatchSummary] { filtered(viewModel.recentMatches) }

    /// After a successful POST /matches: refresh the list and push the
    /// new match's detail so the GPS screen is one tap away.
    private func openCreatedMatch(id: String) async {
        await viewModel.load(session: session)
        if let match = viewModel.matches.first(where: { $0.id == id }) {
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

            HeaderControls(user: user, session: session, showsCreate: $showsCreate)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg.opacity(0.97))
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
            await viewModel.load(session: session)
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

    /// The active group has no rounds — the switcher stays up top so
    /// the user can flip back to "All my groups".
    private var groupEmptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text("No rounds in this group yet.")
                .font(SticksFont.display(22))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
            Text("Start one with + New round, or switch\nback to All my groups up top.")
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
                Task { await viewModel.load(session: session) }
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
        session: SessionStore()
    )
}
