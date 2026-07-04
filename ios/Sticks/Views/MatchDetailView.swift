//
//  MatchDetailView.swift
//  Sticks
//
//  Slice 3: match detail / scorecard. Header with course + status,
//  scorecard grid (caller's row first), On-course GPS CTA, and a
//  30-second foreground poll of GET /matches/:id.
//

import SwiftUI

struct MatchDetailView: View {
    let match: MatchSummary
    let session: SessionStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: MatchDetailViewModel
    @State private var selectedCell: ScoreCellSelection?
    @State private var showsGPS = false

    init(match: MatchSummary, session: SessionStore) {
        self.match = match
        self.session = session
        _viewModel = State(initialValue: MatchDetailViewModel(matchId: match.id))
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    switch viewModel.phase {
                    case .loading:
                        loadingCard
                    case .failed(let message):
                        failedCard(message)
                    case .loaded:
                        if let detail = viewModel.detail {
                            scorecardCard(detail)
                            if detail.status != .completed {
                                gpsButton
                            }
                            if !detail.canEnterScores {
                                Text("You're viewing as a spectator — only seated players or the match creator can enter scores.")
                                    .font(SticksFont.sans(12))
                                    .foregroundStyle(Color.sticksMuted)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .refreshable {
                await viewModel.load(session: session, quiet: true)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .navigationDestination(isPresented: $showsGPS) {
            OnCourseGPSView(viewModel: viewModel, session: session)
        }
        .sheet(item: $selectedCell) { cell in
            ScoreEntryView(cell: cell, viewModel: viewModel, session: session)
        }
        .task {
            await viewModel.load(session: session)
            // 30s poll while this screen is up; only fires when foregrounded.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                if scenePhase == .active {
                    await viewModel.load(session: session, quiet: true)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let detail = viewModel.detail
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusChip(status: detail?.status ?? match.status)
                Spacer()
                Text(dateText)
                    .font(SticksFont.label(11, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksMuted)
            }

            Text(match.courseName)
                .font(SticksFont.display(30))
                .foregroundStyle(Color.sticksInk)
                .multilineTextAlignment(.leading)

            Text(summaryLine(detail))
                .font(SticksFont.label(11, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var dateText: String {
        let date = viewModel.detail?.scheduledAt ?? match.scheduledAt
        if Calendar.current.isDateInToday(date) {
            return "TODAY · \(date.formatted(date: .omitted, time: .shortened))"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter.string(from: date).uppercased()
    }

    private func summaryLine(_ detail: MatchDetail?) -> String {
        let holes = detail?.holes ?? match.holes
        let mode = detail?.scoringMode ?? match.scoringMode
        let format = detail?.format ?? match.format
        return "\(holes) HOLES · \(mode.uppercased()) · \(format.replacingOccurrences(of: "_", with: " ").uppercased())"
    }

    // MARK: - Scorecard

    private func scorecardCard(_ detail: MatchDetail) -> some View {
        ScorecardGrid(
            detail: detail,
            players: viewModel.sortedPlayers,
            currentHoleIndex: currentHoleIndex(detail),
            onSelect: { cell in selectedCell = cell }
        )
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    /// Round index of the current hole for a live match — the round
    /// session's hole when this match is on-course (it advances live),
    /// otherwise the first hole any player still hasn't scored. Nil for
    /// upcoming/completed matches. Read-only — purely visual.
    private func currentHoleIndex(_ detail: MatchDetail) -> Int? {
        guard detail.status == .inProgress else { return nil }
        let roundSession = RoundSessionService.shared
        if roundSession.activeMatchId == detail.id {
            return min(roundSession.holeIndex, detail.holes - 1)
        }
        guard !detail.players.isEmpty else { return 0 }
        for index in 0 ..< detail.holes {
            let hole = detail.holeNumber(at: index)
            if detail.players.contains(where: { $0.scoresByHole[hole] == nil }) {
                return index
            }
        }
        return detail.holes - 1
    }

    // MARK: - CTA

    private var gpsButton: some View {
        Button {
            showsGPS = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("On-course GPS")
                    .font(SticksFont.sans(16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.sticksGreen)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - States

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading scorecard…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func failedCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Shared press-scale feedback for prominent buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
