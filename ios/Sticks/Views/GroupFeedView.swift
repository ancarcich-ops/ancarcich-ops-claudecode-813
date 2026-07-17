//
//  GroupFeedView.swift
//  Sticks
//
//  Slice 12: a group's private feed — the home screen's match cards
//  (reused verbatim) filtered to matches posted to this group, in the
//  same Live / Upcoming / Recent sections.
//

import SwiftUI

struct GroupFeedView: View {
    let group: SticksGroup
    let session: SessionStore

    @State private var viewModel = MatchListViewModel()
    @State private var showsCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                loadingView
            case .failed(let message):
                failedView(message)
            case .loaded:
                if groupMatches.isEmpty {
                    emptyView
                } else {
                    feed
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .task {
            await viewModel.load(session: session)
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: - Filtering

    private var groupMatches: [MatchSummary] {
        viewModel.matches.filter { $0.groupId == group.id }
    }

    private var liveMatches: [MatchSummary] {
        viewModel.liveMatches.filter { $0.groupId == group.id }
    }

    private var upcomingMatches: [MatchSummary] {
        viewModel.upcomingMatches.filter { $0.groupId == group.id }
    }

    private var recentMatches: [MatchSummary] {
        viewModel.recentMatches.filter { $0.groupId == group.id }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(group.initials)
                .font(SticksFont.display(17))
                .foregroundStyle(Color.sticksCream)
                .frame(width: 38, height: 38)
                .background(GroupIdentity.color(for: group.id))
                .clipShape(.rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(SticksFont.display(22))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                subtitle
            }

            Spacer(minLength: 8)

            leaderboardEntry
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(Color.sticksBg.opacity(0.97))
    }

    /// "8 members · code ABC123" — the members part opens the roster
    /// (slice 64), the code part copies the same invite line as the
    /// card ticket.
    private var subtitle: some View {
        HStack(spacing: 0) {
            NavigationLink(value: GroupMembersDestination(group: group)) {
                Text(memberText)
                    .font(SticksFont.mono(11))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGreen)
                    .padding(.vertical, 2)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Group members")

            Text(" · ")
                .font(SticksFont.mono(11))
                .foregroundStyle(Color.sticksMuted)

            Button {
                guard !showsCopied else { return }
                GroupIdentity.copyInvite(code: group.inviteCode)
                withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
                copyResetTask?.cancel()
                copyResetTask = Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.2)) { showsCopied = false }
                }
            } label: {
                Text(showsCopied ? "✓ COPIED" : "CODE \(group.inviteCode)")
                    .font(SticksFont.mono(11))
                    .kerning(0.8)
                    .foregroundStyle(showsCopied ? Color.sticksGreen : Color.sticksMuted)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy invite code \(group.inviteCode)")
        }
        .lineLimit(1)
    }

    private var memberText: String {
        group.memberCount == 1 ? "1 member" : "\(group.memberCount) members"
    }

    /// Same leaderboard entry point as the group card's footer —
    /// disabled until the group has at least one match.
    private var leaderboardEntry: some View {
        NavigationLink(value: LeaderboardDestination(group: group)) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Leaderboard")
                    .font(SticksFont.sans(13.5, weight: .semibold))
            }
            .foregroundStyle(Color.sticksGreen)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Color.sticksGreen.opacity(0.08))
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(Color.sticksGreen.opacity(0.25), lineWidth: 1)
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(group.matchCount == 0)
        .opacity(group.matchCount == 0 ? 0.5 : 1)
        .accessibilityLabel("Group leaderboard")
    }

    // MARK: - Feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !liveMatches.isEmpty {
                    matchSection(title: "Live", matches: liveMatches, showsLiveDot: true)
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
                    FeedPulsingDot()
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
                .buttonStyle(FeedCardButtonStyle())
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
            Text("No matches posted to this group yet.")
                .font(SticksFont.sans(14.5))
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

// MARK: - Pieces (mirrors the home feed's private helpers)

private struct FeedPulsingDot: View {
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

private struct FeedCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
