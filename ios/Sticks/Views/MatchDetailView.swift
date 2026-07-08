//
//  MatchDetailView.swift
//  Sticks
//
//  Slice 3: match detail / scorecard. Header with course + status,
//  scorecard grid (caller's row first), On-course GPS CTA, and a
//  30-second foreground poll of GET /matches/:id.
//
//  Slice 27: the ⋯ actions menu (top-right) — Edit details (creator,
//  UPCOMING, no scores), Mark final (in progress), Reopen (creator,
//  completed), Delete round (creator, any status).
//

import SwiftUI
import UIKit

struct MatchDetailView: View {
    let match: MatchSummary
    let session: SessionStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MatchDetailViewModel
    @State private var selectedCell: ScoreCellSelection?
    @State private var showsGPS = false
    @State private var showsEdit = false
    @State private var showsDeleteConfirm = false
    @State private var showsFinalConfirm = false
    @State private var showsReopenConfirm = false
    @State private var isDeleting = false
    @State private var actionError: String?

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
                            if detail.status == .inProgress {
                                if detail.myMatchPlayerId != nil {
                                    MatchHeroCard(
                                        detail: detail,
                                        holeGeo: viewModel.response?.holeGeo ?? [:],
                                        currentHoleIndex: currentHoleIndex(detail)
                                    )
                                }
                                StandingsCard(
                                    detail: detail,
                                    probabilities: viewModel.response?.odds?.probabilities ?? [:],
                                    sideGames: viewModel.response?.sideGames ?? []
                                )
                            }
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
        .toolbar {
            if hasMenuActions {
                ToolbarItem(placement: .topBarTrailing) {
                    actionsMenu
                }
            }
        }
        .navigationDestination(isPresented: $showsGPS) {
            OnCourseGPSView(viewModel: viewModel, session: session)
        }
        .sheet(item: $selectedCell) { cell in
            ScoreEntryView(cell: cell, viewModel: viewModel, session: session)
        }
        .fullScreenCover(isPresented: $showsEdit) {
            if let detail = viewModel.detail, let user = session.user {
                CreateMatchView(
                    user: user,
                    session: session,
                    editing: MatchEditContext(
                        detail: detail,
                        sideGameKinds: viewModel.response?.sideGames.map(\.kind) ?? [],
                        groupId: match.groupId
                    )
                ) { _ in
                    showsEdit = false
                    NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
                    Task { await viewModel.load(session: session, quiet: true) }
                }
            }
        }
        .confirmationDialog(
            "Delete this round for everyone? This can't be undone.",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete round", role: .destructive) { deleteRound() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Mark this round final?", isPresented: $showsFinalConfirm) {
            Button("Mark final") { markFinal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scores lock in and the round moves to Recent.")
        }
        .alert("Reopen this round?", isPresented: $showsReopenConfirm) {
            Button("Reopen") { reopenRound() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It won't count as final until you finish it again.")
        }
        .alert(
            "Couldn't do that",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
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

    // MARK: - Actions menu (slice 27)

    /// Edit only while the round is untouched — creator, UPCOMING, and
    /// not a single score logged (the server 400s otherwise).
    private var canEditDetails: Bool {
        guard let detail = viewModel.detail else { return false }
        return detail.isCreator
            && detail.status == .upcoming
            && detail.players.allSatisfy { $0.scoresByHole.isEmpty }
    }

    private var canMarkFinal: Bool {
        viewModel.detail?.status == .inProgress
    }

    /// Reopen a finished round — creator-only, COMPLETED only. The server
    /// reverts it to IN_PROGRESS (or UPCOMING if it had no scores).
    private var canReopen: Bool {
        guard let detail = viewModel.detail else { return false }
        return detail.isCreator && detail.status == .completed
    }

    private var canDelete: Bool {
        viewModel.detail?.isCreator == true
    }

    private var hasMenuActions: Bool {
        canEditDetails || canMarkFinal || canReopen || canDelete
    }

    private var actionsMenu: some View {
        Menu {
            if canEditDetails {
                Button {
                    showsEdit = true
                } label: {
                    Label("Edit details", systemImage: "pencil")
                }
            }
            if canMarkFinal {
                Button {
                    showsFinalConfirm = true
                } label: {
                    Label("Mark final", systemImage: "flag.checkered")
                }
            }
            if canReopen {
                Button {
                    showsReopenConfirm = true
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
            }
            if canDelete {
                Button(role: .destructive) {
                    showsDeleteConfirm = true
                } label: {
                    Label("Delete round", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .frame(width: 32, height: 32)
                .background(Color.sticksPanel2)
                .clipShape(.circle)
                .contentShape(.circle)
        }
        .disabled(isDeleting)
        .accessibilityLabel("Round actions")
    }

    /// DELETE /matches/:id → pop back to the feed and refresh it.
    /// A 403's server message shows verbatim.
    private func deleteRound() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await viewModel.deleteMatch(session: session)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
                dismiss()
            } catch let error as APIError {
                actionError = error.message
            } catch {
                actionError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    /// POST /matches/:id/reopen → refetch (renders IN_PROGRESS, or
    /// UPCOMING if it had no scores). A 403's server message shows verbatim.
    private func reopenRound() {
        Task {
            do {
                try await viewModel.reopenMatch(session: session)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
            } catch let error as APIError {
                actionError = error.message
            } catch {
                actionError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    /// POST /matches/:id/complete → refetch (renders COMPLETED).
    private func markFinal() {
        Task {
            do {
                try await viewModel.completeMatch(session: session)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
            } catch let error as APIError {
                actionError = error.message
            } catch {
                actionError = "Can't reach Sticks. Check your connection and try again."
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
