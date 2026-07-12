//
//  TournamentDetailView.swift
//  Sticks
//
//  Slice 55: one tournament — header with status + invite-code share
//  row, a Leaderboard | Odds segmented switcher (cumulative standings
//  and win probabilities), then the bound rounds list. Tapping a round
//  opens the normal match detail; creators get "+ Add round", which
//  reopens the create wizard bound to this tournament.
//

import SwiftUI
import UIKit

struct TournamentDetailView: View {
    let tournamentId: String
    let user: User
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TournamentDetailViewModel
    @State private var selectedTab: Tab = .leaderboard
    @State private var showsAddRound = false
    @State private var showsCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    enum Tab: Hashable {
        case leaderboard
        case odds
    }

    init(tournamentId: String, user: User, session: SessionStore) {
        self.tournamentId = tournamentId
        self.user = user
        self.session = session
        _viewModel = State(initialValue: TournamentDetailViewModel(tournamentId: tournamentId))
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                loadingView
            case .failed(let message):
                failedView(message)
            case .loaded:
                if let response = viewModel.response {
                    content(response)
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
        .fullScreenCover(isPresented: $showsAddRound) {
            CreateMatchView(
                user: user,
                session: session,
                tournamentId: tournamentId
            ) { _ in
                showsAddRound = false
                NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
                Task { await viewModel.load(session: session, quiet: true) }
            }
        }
        .task {
            await viewModel.load(session: session)
        }
        .onDisappear { copyResetTask?.cancel() }
    }

    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("←").layoutPriority(1)
                Text("TOURNAMENTS").lineLimit(1)
            }
            .font(SticksFont.mono(11.5))
            .kerning(1.15)
            .foregroundStyle(Color.sticksGreen)
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to tournaments")
    }

    // MARK: - Content

    private func content(_ response: TournamentDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(response.tournament)

                if !response.tournament.inviteCode.isEmpty {
                    shareRow(response.tournament)
                }

                tabBar(response)

                if selectedTab == .odds, !response.odds.isEmpty {
                    OddsCard(odds: response.odds)
                } else {
                    LeaderboardCard(
                        rows: response.leaderboard,
                        roundsPlanned: response.tournament.roundsPlanned
                    )
                }

                roundsSection(response)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .refreshable {
            await viewModel.load(session: session, quiet: true)
        }
    }

    // MARK: - Header

    private func header(_ tournament: TournamentInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tournament.name)
                    .font(SticksFont.display(30, weight: .bold))
                    .kerning(-0.4)
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                TournamentStatusChip(status: tournament.status)
                    .padding(.top, 4)
            }

            Text(metaLine(tournament))
                .font(SticksFont.mono(11.5))
                .kerning(1.1)
                .foregroundStyle(Color.sticksMuted)

            if let notes = tournament.notes, !notes.isEmpty {
                Text(notes)
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.top, 2)
            }
        }
    }

    private func metaLine(_ tournament: TournamentInfo) -> String {
        var parts: [String] = [
            tournament.scoringMode.uppercased() == "GROSS" ? "GROSS" : "NET",
            tournament.roundsPlanned == 1 ? "1 ROUND" : "\(tournament.roundsPlanned) ROUNDS",
        ]
        if let start = tournament.scheduledStartAt {
            parts.append(start.formatted(.dateTime.month(.abbreviated).day()).uppercased())
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Invite share row

    private func shareRow(_ tournament: TournamentInfo) -> some View {
        HStack(spacing: 0) {
            Button {
                copyCode(tournament.inviteCode)
            } label: {
                ZStack(alignment: .leading) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("INVITE CODE")
                                .font(SticksFont.mono(8.5))
                                .kerning(0.9)
                                .foregroundStyle(Color.sticksFaint)

                            Text(tournament.inviteCode)
                                .font(SticksFont.mono(15))
                                .kerning(2.2)
                                .foregroundStyle(Color.sticksInk)
                        }

                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.sticksMuted)
                    }
                    .opacity(showsCopied ? 0 : 1)

                    if showsCopied {
                        Text("✓ Copied")
                            .font(SticksFont.sans(14, weight: .semibold))
                            .foregroundStyle(Color.sticksGreen)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 54)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy invite code \(tournament.inviteCode)")

            Rectangle()
                .fill(Color.sticksHairline)
                .frame(width: 1, height: 30)

            ShareLink(item: shareMessage(tournament)) {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Share")
                        .font(SticksFont.sans(13.5, weight: .semibold))
                }
                .foregroundStyle(Color.sticksGreen)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .contentShape(.rect)
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private func shareMessage(_ tournament: TournamentInfo) -> String {
        "Join \"\(tournament.name)\" on Sticks — invite code \(tournament.inviteCode)"
    }

    private func copyCode(_ code: String) {
        guard !showsCopied else { return }
        UIPasteboard.general.string = code
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsCopied = false }
        }
    }

    // MARK: - Tabs

    private func tabBar(_ response: TournamentDetailResponse) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                tabButton(.leaderboard, label: "Leaderboard")
                if !response.odds.isEmpty {
                    tabButton(.odds, label: "Odds")
                }
                Spacer()
            }

            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: Tab, label: String) -> some View {
        let isActive = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            VStack(spacing: 8) {
                Text(label)
                    .font(SticksFont.sans(15, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? Color.sticksInk : Color.sticksMuted)

                Rectangle()
                    .fill(isActive ? Color.sticksGreen : Color.clear)
                    .frame(height: 2)
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rounds

    private func roundsSection(_ response: TournamentDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Rounds")
                    .font(SticksFont.display(19))
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                Text("\(response.rounds.count)/\(response.tournament.roundsPlanned)")
                    .font(SticksFont.mono(12))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.top, 4)

            if response.rounds.isEmpty {
                Text(response.tournament.isCreator
                    ? "No rounds yet — add the first one below."
                    : "No rounds yet. The organizer will add them here.")
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.sticksCard)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.sticksHairline, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedRounds(response).enumerated()), id: \.element.id) { index, round in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sticksHairline)
                                .frame(height: 1)
                                .padding(.leading, 60)
                        }
                        roundRow(round, tournament: response.tournament)
                    }
                }
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
            }

            if response.tournament.isCreator {
                addRoundButton
            }
        }
    }

    private func sortedRounds(_ response: TournamentDetailResponse) -> [TournamentRound] {
        response.rounds.sorted { ($0.roundNumber, $0.id) < ($1.roundNumber, $1.id) }
    }

    private func roundRow(_ round: TournamentRound, tournament: TournamentInfo) -> some View {
        NavigationLink(value: matchStub(for: round, tournament: tournament)) {
            HStack(spacing: 13) {
                Text("R\(max(round.roundNumber, 1))")
                    .font(SticksFont.mono(13))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 40, height: 40)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 3) {
                    Text(round.courseName)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    if let date = round.scheduledAt {
                        Text(date.formatted(.dateTime.month(.abbreviated).day()).uppercased())
                            .font(SticksFont.mono(10.5))
                            .kerning(0.8)
                            .foregroundStyle(Color.sticksFaint)
                    }
                }

                Spacer(minLength: 8)

                StatusChip(status: round.status)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Minimal MatchSummary so the round can push the existing
    /// MatchDetailView — the detail screen refetches everything by id.
    private func matchStub(for round: TournamentRound, tournament: TournamentInfo) -> MatchSummary {
        MatchSummary(
            id: round.id,
            courseName: round.courseName,
            scheduledAt: round.scheduledAt ?? .now,
            completedAt: nil,
            status: round.status,
            holes: 18,
            startingHole: 1,
            scoringMode: tournament.scoringMode,
            format: "INDIVIDUAL",
            pars: [],
            probabilities: [:],
            myMatchPlayerId: nil,
            groupId: nil,
            players: [],
            tickerItems: []
        )
    }

    private var addRoundButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showsAddRound = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("Add round")
                    .font(SticksFont.sans(14.5, weight: .bold))
            }
            .foregroundStyle(Color.sticksGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksGreen.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading tournament…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
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

// MARK: - Number formatting

/// Shared "82" / "81.5" formatting for tournament scores.
nonisolated enum TournamentScoreFormat {
    static func score(_ value: Double?) -> String {
        guard let value else { return "—" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - Leaderboard card

private struct LeaderboardCard: View {
    let rows: [TournamentLeaderboardRow]
    let roundsPlanned: Int

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                Text("No scores yet — the leaderboard fills in as rounds finish.")
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                    LeaderboardRowView(
                        row: row,
                        roundsPlanned: roundsPlanned,
                        isLeader: row.rank == 1
                    )
                }
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }
}

private struct LeaderboardRowView: View {
    let row: TournamentLeaderboardRow
    let roundsPlanned: Int
    let isLeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                rankDisc

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .font(SticksFont.sans(15, weight: isLeader ? .bold : .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    if let handicap = row.latestHandicap {
                        Text("HCP \(TournamentScoreFormat.score(handicap))")
                            .font(SticksFont.mono(10))
                            .kerning(0.8)
                            .foregroundStyle(Color.sticksFaint)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(TournamentScoreFormat.score(row.total))
                        .font(SticksFont.display(22, weight: .bold))
                        .foregroundStyle(isLeader ? Color.sticksGreen : Color.sticksInk)

                    if isPartial {
                        Text("THRU R\(row.playedRounds)")
                            .font(SticksFont.mono(9))
                            .kerning(0.9)
                            .foregroundStyle(Color.sticksFaint)
                    }
                }
            }

            roundCells
                .padding(.leading, 52)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isLeader ? Color.sticksGreen.opacity(0.06) : Color.clear)
    }

    private var isPartial: Bool {
        row.playedRounds > 0 && row.playedRounds < roundsPlanned
    }

    private var rankDisc: some View {
        Text("\(row.rank)")
            .font(SticksFont.mono(13))
            .foregroundStyle(isLeader ? Color.sticksCream : Color.sticksMuted)
            .frame(width: 30, height: 30)
            .background(isLeader ? Color.sticksGreen : Color.sticksPanel2)
            .clipShape(.circle)
    }

    /// One compact mono cell per planned round — "R1 82 · R2 79 · R3 —".
    private var roundCells: some View {
        let count = max(roundsPlanned, row.roundScores.count)
        return HStack(spacing: 10) {
            ForEach(0 ..< max(count, 1), id: \.self) { index in
                let score: Double? = row.roundScores.indices.contains(index)
                    ? row.roundScores[index]
                    : nil
                (
                    Text("R\(index + 1) ")
                        .foregroundStyle(Color.sticksFaint)
                    + Text(TournamentScoreFormat.score(score))
                        .foregroundStyle(score == nil ? Color.sticksFaint : Color.sticksInk)
                )
                .font(SticksFont.mono(11))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Odds card

private struct OddsCard: View {
    let odds: [TournamentOddsRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rankedOdds.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                        .padding(.leading, 14)
                }
                OddsRowView(row: row, isFavorite: index == 0)
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var rankedOdds: [TournamentOddsRow] {
        odds.sorted { $0.winProbability > $1.winProbability }
    }
}

private struct OddsRowView: View {
    let row: TournamentOddsRow
    let isFavorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.displayName)
                    .font(SticksFont.sans(15, weight: isFavorite ? .bold : .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(percentText)
                    .font(SticksFont.display(20, weight: .bold))
                    .foregroundStyle(isFavorite ? Color.sticksGreen : Color.sticksInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.sticksPanel2)

                    Capsule()
                        .fill(isFavorite ? Color.sticksGreen : Color.sticksGreen.opacity(0.5))
                        .frame(width: max(proxy.size.width * fraction, 4))
                }
            }
            .frame(height: 6)

            Text(subLine)
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var fraction: CGFloat {
        CGFloat(min(max(row.winProbability, 0), 1))
    }

    private var percentText: String {
        let percent = row.winProbability * 100
        if percent > 0, percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    private var subLine: String {
        var parts: [String] = []
        if let projected = row.projectedTotal {
            parts.append("PROJ \(TournamentScoreFormat.score(projected))")
        }
        if row.playedRounds > 0 {
            parts.append("THRU R\(row.playedRounds)")
        }
        if let handicap = row.latestHandicap {
            parts.append("HCP \(TournamentScoreFormat.score(handicap))")
        }
        return parts.isEmpty ? "NO ROUNDS YET" : parts.joined(separator: " · ")
    }
}
