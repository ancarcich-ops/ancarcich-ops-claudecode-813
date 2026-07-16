//
//  MemberProfileView.swift
//  Sticks
//
//  Slice 63: a group member's read-only stats profile — the same hero,
//  rounds-over-time, scoring-analysis, and course-bests cards the Stats
//  tab composes, minus every owner-only affordance (no new-round, no
//  deletes, no GHIN/target editors; the server already nulls those).
//  If the profile resolves to the caller (isSelf), it routes to the
//  editable Stats tab instead.
//

import SwiftUI

/// Push destination for a member's read-only profile, registered on
/// the Groups tab's NavigationStack.
struct MemberProfileDestination: Hashable {
    let username: String
    /// Best-known display name — shown while the profile loads.
    let displayName: String
}

struct MemberProfileView: View {
    let username: String
    /// Fallback title until the payload's displayName arrives.
    let fallbackName: String
    let session: SessionStore
    /// Called when the profile turns out to be the caller's own —
    /// the owner routes to the editable Stats tab (and this pops).
    let onOpenOwnStats: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = MemberProfileViewModel()
    @State private var baselineSelection: BaselineSelection = .hcp(10)

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                loadingView
            case .failed(let message):
                failedView(message)
            case .loaded:
                if let stats = viewModel.stats {
                    content(stats)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backChip }
        }
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .task {
            await viewModel.load(username: username, session: session)
            if viewModel.isSelf {
                onOpenOwnStats()
            }
        }
    }

    // MARK: - Back chip

    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("←")
                    .layoutPriority(1)
                Text("BACK")
            }
            .font(SticksFont.mono(11.5))
            .kerning(1.15)
            .foregroundStyle(Color.sticksGreen)
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    // MARK: - Content

    private func content(_ stats: PlayerStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identityHeader(stats)

                StatsHeroCard(stats: stats)

                if stats.rounds.count >= 2 {
                    RoundsOverTimeCard(
                        rounds: Array(stats.rounds.suffix(20)),
                        index: stats.index,
                        baselines: viewModel.baselines,
                        selection: $baselineSelection
                    )
                }

                if stats.distribution.totalHolesPlayed > 0 {
                    ScoringAnalysisCard(
                        stats: stats,
                        baselines: viewModel.baselines,
                        selection: $baselineSelection
                    )
                }

                if !stats.courseRecords.isEmpty {
                    CourseBestsCard(records: stats.courseRecords)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(username: username, session: session)
        }
    }

    private func identityHeader(_ stats: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName(stats))
                .font(SticksFont.display(28, weight: .bold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(2)

            Text("@\(handle(stats))")
                .font(SticksFont.mono(11.5))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
                .lineLimit(1)
        }
    }

    private func displayName(_ stats: PlayerStats) -> String {
        if !stats.displayName.isEmpty { return stats.displayName }
        if !fallbackName.isEmpty { return fallbackName }
        return username
    }

    private func handle(_ stats: PlayerStats) -> String {
        stats.username.isEmpty ? username : stats.username
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading \(fallbackName.isEmpty ? username : fallbackName)…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
                .lineLimit(1)
                .padding(.horizontal, 40)
        }
    }

    /// First-load failure — the server's own message (404 "no such
    /// account" included) verbatim, plus a retry.
    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.load(username: username, session: session) }
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
