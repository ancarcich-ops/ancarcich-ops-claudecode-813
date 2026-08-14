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

    /// The stale round currently shown in the "needs your attention"
    /// alert — nil when no alert is up.
    @State private var attentionMatch: MatchSummary?
    @State private var endRoundError: String?

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
            // Slice 63 tweaks: match detail's "created by" pushes a
            // member profile from this stack too. The caller's own
            // profile pops and hops to the Stats tab.
            .navigationDestination(for: MemberProfileDestination.self) { destination in
                MemberProfileView(
                    username: destination.username,
                    fallbackName: destination.displayName,
                    session: session,
                    onOpenOwnStats: {
                        if !path.isEmpty { path.removeLast() }
                        tabSelection = .stats
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showsCreate) {
            CreateMatchView(user: user, session: session) { matchId in
                showsCreate = false
                Task { await openCreatedMatch(id: matchId) }
            }
        }
        .popsToRoot(on: .home, path: $path)
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
        // A round the user created has sat live for >24h — alert them
        // once per session so they can continue or end it.
        .onChange(of: viewModel.attentionMatches) { _, pending in
            guard attentionMatch == nil, let next = pending.first else { return }
            attentionMatch = next
        }
        .alert(
            "Round needs your attention",
            isPresented: attentionAlertPresented,
            presenting: attentionMatch
        ) { match in
            Button("Continue round") {
                viewModel.markAttentionHandled(match.id)
                path.append(match)
            }
            Button("End round") {
                viewModel.markAttentionHandled(match.id)
                Task { await endRound(match) }
            }
            Button("Not now", role: .cancel) {
                viewModel.markAttentionHandled(match.id)
            }
        } message: { match in
            Text("Your round at \(match.courseName) has been live for over a day, so it's hidden from your groups and the public feed. Keep playing to finish it, or end it now to post the scores.")
        }
        .alert(
            "Couldn't end the round",
            isPresented: Binding(
                get: { endRoundError != nil },
                set: { if !$0 { endRoundError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(endRoundError ?? "")
        }
    }

    /// Presentation binding for the attention alert — dismissing clears
    /// the current match, then the next pending one (if any) surfaces
    /// after a short beat so back-to-back alerts don't collide.
    private var attentionAlertPresented: Binding<Bool> {
        Binding(
            get: { attentionMatch != nil },
            set: { presented in
                guard !presented else { return }
                attentionMatch = nil
                Task {
                    try? await Task.sleep(for: .seconds(0.7))
                    if attentionMatch == nil {
                        attentionMatch = viewModel.attentionMatches.first
                    }
                }
            }
        )
    }

    /// Marks the stale round finished server-side, then refreshes every
    /// feed. Failures surface in a follow-up alert.
    private func endRound(_ match: MatchSummary) async {
        guard let token = session.token else { return }
        do {
            try await APIClient.shared.postComplete(matchId: match.id, token: token)
            NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
        } catch let error as APIError {
            endRoundError = error.message
        } catch {
            endRoundError = "Can't reach Sticks. Check your connection and try again."
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
        // The pills are fixed-size, so the row adapts around them. The
        // wordmark is the brand — it must never disappear — so the
        // ladder trades the clubs mark, then the (no-op on this tab)
        // Home pill's text, then the pill itself before shrinking the
        // wordmark. Rows are rigid apart from the Spacer, so
        // ViewThatFits picks the first row whose content truly fits.
        ViewThatFits(in: .horizontal) {
            headerRow(wordmarkSize: 30, showsMark: true, homePill: .text)
            headerRow(wordmarkSize: 30, showsMark: false, homePill: .text)
            headerRow(wordmarkSize: 26, showsMark: false, homePill: .icon)
            headerRow(wordmarkSize: 22, showsMark: false, homePill: .icon)
            headerRow(wordmarkSize: 30, showsMark: false, homePill: .hidden)
            headerRow(wordmarkSize: 22, showsMark: false, homePill: .hidden)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg)
        .overlay(alignment: .bottom) {
            Color.sticksHairline.frame(height: 1)
        }
    }

    /// One candidate header row for the ViewThatFits ladder.
    private func headerRow(
        wordmarkSize: CGFloat,
        showsMark: Bool,
        homePill: HeaderControls.HomePillStyle
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 10) {
                if showsMark {
                    SticksClubsMark()
                        .frame(width: 34, height: 34)
                }

                (Text("Sticks").foregroundStyle(Color.sticksInk)
                    + Text(".").foregroundStyle(Color.sticksGreen))
                    .font(SticksFont.display(wordmarkSize))
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            HeaderControls(
                user: user,
                session: session,
                showsCreate: $showsCreate,
                tabSelection: $tabSelection,
                homePill: homePill
            )
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
                // Live cards carry "+ PICK" chips, so the card can't be a
                // NavigationLink (the link would swallow the chip taps) —
                // a container tap gesture pushes the detail instead, and
                // the deeper chip Buttons win their own taps.
                if match.status == .inProgress {
                    MatchCardView(match: match, showsPicks: true)
                        .contentShape(.rect)
                        .onTapGesture { path.append(match) }
                        .accessibilityAddTraits(.isButton)
                } else {
                    NavigationLink(value: match) {
                        MatchCardView(match: match)
                    }
                    .buttonStyle(MatchCardButtonStyle())
                }
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
