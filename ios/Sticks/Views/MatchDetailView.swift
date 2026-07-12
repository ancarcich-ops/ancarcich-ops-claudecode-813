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
//  The same actions also render as a visible "Round actions" card at
//  the bottom of the page (the ⋯ menu alone was too easy to miss),
//  plus a prominent gold FINISH ROUND button once every score is in.
//
//  Slice 29: web parity — the GPS launcher moves to the TOP (right
//  under the header, "Resume/Start on-course GPS →"), Edit pars on the
//  scorecard card (creator, any status), an Edit side games CTA
//  (creator, not completed), and the Share my round card (any seated
//  player).
//
//  Slice 36: the standard app header (back chevron + Sticks wordmark +
//  HeaderControls) replaces the floating back/⋯ circles; the ⋯ actions
//  menu moves inline next to the course title, like the web.
//
//  Slice 54: web parity — a Scorecard | Live odds tab switcher under
//  the match header. The Market lives on the Live-odds tab only; the
//  scorecard/standings/side-games stay on Scorecard. The Live-odds tab
//  is hidden entirely for unpriced/solo rounds.
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
    @State private var showsCreate = false
    @State private var showsEditPars = false
    @State private var showsEditSideGames = false
    /// Slice 50: the event-driven side game whose per-hole editor sheet
    /// is open (Snake, BBB, Match press).
    @State private var eventEditorGame: SideGame?
    /// Slice 54: which content tab is showing — Scorecard (default) or
    /// Live odds (the Market). Matches the web's match-page tabs.
    @State private var selectedTab: MatchDetailTab = .scorecard
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
                            // Slice 54: the tab switcher only exists when
                            // the match is priced — solo/unpriced rounds
                            // have no Market, so no tab bar at all.
                            if isMarketPriced(detail) {
                                detailTabBar(detail)
                            }
                            if selectedTab == .liveOdds,
                               isMarketPriced(detail),
                               let odds = viewModel.response?.odds {
                                // Live odds tab: the Market only.
                                MarketCard(
                                    detail: detail,
                                    odds: odds,
                                    viewModel: viewModel,
                                    session: session
                                )
                            } else {
                                scorecardTabContent(detail)
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
        // Slice 36: the shared app header replaces the system nav bar
        // and its floating back/⋯ circles.
        .safeAreaInset(edge: .top, spacing: 0) { appHeaderBar }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Color.sticksGreen)
        .navigationDestination(isPresented: $showsGPS) {
            OnCourseGPSView(viewModel: viewModel, session: session)
        }
        .sheet(item: $selectedCell) { cell in
            ScoreEntryView(cell: cell, viewModel: viewModel, session: session)
        }
        .sheet(isPresented: $showsEditPars) {
            if let detail = viewModel.detail {
                EditParsSheet(detail: detail, viewModel: viewModel, session: session)
            }
        }
        .sheet(item: $eventEditorGame) { game in
            // Slice 53: Wolf and Targets get their own editors; the
            // event-driven trio keeps the slice-50 per-hole editor.
            switch MatchDetailMath.eventGameKey(game.kind) {
            case "WOLF":
                WolfEditorView(game: game, viewModel: viewModel, session: session)
            case "TARGETS":
                TargetsConfigView(viewModel: viewModel, session: session)
            default:
                SideGameEventEditorView(game: game, viewModel: viewModel, session: session)
            }
        }
        .sheet(isPresented: $showsEditSideGames) {
            if let detail = viewModel.detail {
                EditSideGamesSheet(
                    detail: detail,
                    currentKinds: viewModel.response?.sideGames.map(\.kind) ?? [],
                    viewModel: viewModel,
                    session: session
                )
            }
        }
        .fullScreenCover(isPresented: $showsCreate) {
            if let user = session.user {
                CreateMatchView(user: user, session: session) { matchId in
                    showsCreate = false
                    NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
                    NotificationCenter.default.post(
                        name: .sticksOpenMatch,
                        object: nil,
                        userInfo: ["matchId": matchId]
                    )
                }
            }
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

    /// The big gold FINISH ROUND moment — live round, every hole scored.
    private var showsFinishCTA: Bool {
        canMarkFinal && viewModel.isRoundComplete
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

    /// Slice 36: the same cream header bar the tabs use — back chevron
    /// leading, Sticks wordmark, then the shared [+ New round] +
    /// [All my groups ▾] cluster — so match detail reads like the rest
    /// of the app instead of a bare pushed view.
    private var appHeaderBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .frame(width: 32, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                (Text("Sticks").foregroundStyle(Color.sticksInk)
                    + Text(".").foregroundStyle(Color.sticksGreen))
                    .font(SticksFont.display(26))
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            if let user = session.user {
                HeaderControls(user: user, session: session, showsCreate: $showsCreate)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg)
        .overlay(alignment: .bottom) {
            Color.sticksHairline.frame(height: 1)
        }
    }

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

            // Slice 36: the ⋯ actions menu sits inline next to the
            // title (web parity), not floating in a nav bar.
            HStack(alignment: .top, spacing: 10) {
                Text(match.courseName)
                    .font(SticksFont.display(30))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                if hasMenuActions {
                    actionsMenu
                }
            }

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

    // MARK: - Tabs (slice 54)

    /// Priced = the server sent non-empty win probabilities and there's
    /// an actual field to bet on (≥ 2 players).
    private func isMarketPriced(_ detail: MatchDetail) -> Bool {
        guard let odds = viewModel.response?.odds else { return false }
        return !odds.probabilities.isEmpty && detail.players.count > 1
    }

    /// Web-style segmented text tabs — Scorecard (with thru/holes badge)
    /// and Live odds (with the call count, hidden at 0). Active tab gets
    /// an ink label and a green underline; inactive is muted.
    private func detailTabBar(_ detail: MatchDetail) -> some View {
        let callCount = viewModel.response?.odds?.totalCalls ?? 0
        return HStack(spacing: 24) {
            tabButton(
                title: "Scorecard",
                badge: "\(thruCount(detail))/\(detail.holes)",
                isActive: selectedTab == .scorecard
            ) { selectTab(.scorecard) }

            tabButton(
                title: "Live odds",
                badge: callCount > 0 ? "\(callCount)" : nil,
                isActive: selectedTab == .liveOdds
            ) { selectTab(.liveOdds) }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Color.sticksHairline.frame(height: 1)
        }
    }

    private func selectTab(_ tab: MatchDetailTab) {
        guard selectedTab != tab else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.15)) {
            selectedTab = tab
        }
    }

    private func tabButton(
        title: String,
        badge: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(isActive ? Color.sticksInk : Color.sticksMuted)
                    if let badge {
                        Text(badge)
                            .font(SticksFont.mono(10))
                            .foregroundStyle(isActive ? Color.sticksGreen : Color.sticksFaint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (isActive ? Color.sticksGreen : Color.sticksFaint)
                                    .opacity(0.1)
                            )
                            .clipShape(.capsule)
                    }
                }
                Rectangle()
                    .fill(isActive ? Color.sticksGreen : Color.clear)
                    .frame(height: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Holes-scored count for the Scorecard badge — the caller's row when
    /// seated, else the first player (same rule as the scorecard's meta).
    private func thruCount(_ detail: MatchDetail) -> Int {
        let player = detail.players.first { $0.id == detail.myMatchPlayerId }
            ?? detail.players.first
        guard let player else { return 0 }
        return MatchDetailMath.holesPlayed(for: player, in: detail)
    }

    /// Everything except the Market — the whole pre-slice-54 flow.
    @ViewBuilder
    private func scorecardTabContent(_ detail: MatchDetail) -> some View {
        // Web order: the GPS launcher is the first
        // thing under the header.
        if detail.status != .completed {
            gpsButton(detail)
        }
        if detail.status == .inProgress, detail.myMatchPlayerId != nil {
            MatchHeroCard(
                detail: detail,
                holeGeo: viewModel.response?.holeGeo ?? [:],
                currentHoleIndex: currentHoleIndex(detail)
            )
        }
        scorecardCard(detail)
        if detail.status == .inProgress {
            StandingsCard(
                detail: detail,
                probabilities: viewModel.response?.odds?.probabilities ?? [:],
                sideGames: viewModel.response?.sideGames ?? [],
                onRecordEvents: detail.canEnterScores && detail.status != .completed
                    ? { game in eventEditorGame = game }
                    : nil
            )
        }
        // Slice 52/53: one prominent "score it" card per
        // enabled game with a native editor (Snake, BBB,
        // Match press, Wolf, Targets) — the obvious way
        // in, matching the web's inline editor. Sits under
        // the Standings. Hidden for spectators and
        // completed rounds; Targets is config-only, so
        // its card is creator-only.
        if detail.canEnterScores, detail.status != .completed {
            ForEach(editableSideGames) { game in
                SideGameScoreCard(
                    game: game,
                    eventCount: eventCount(for: game),
                    stateOverride: stateOverride(for: game),
                    onOpen: { eventEditorGame = $0 }
                )
            }
        }
        if showsFinishCTA {
            finishRoundButton
        }
        if canEditSideGames {
            editSideGamesButton
        }
        if detail.myMatchPlayerId != nil {
            ShareRoundCard(viewModel: viewModel, session: session)
        }
        if !detail.canEnterScores {
            Text("You're viewing as a spectator — only seated players or the match creator can enter scores.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .padding(.horizontal, 4)
        }
        if hasMenuActions {
            roundActionsCard
        }
    }

    // MARK: - Scorecard

    private func scorecardCard(_ detail: MatchDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScorecardGrid(
                detail: detail,
                players: viewModel.sortedPlayers,
                currentHoleIndex: currentHoleIndex(detail),
                onSelect: { cell in selectedCell = cell }
            )

            // Slice 29: compact creator-only par editing, any status.
            if detail.isCreator {
                Rectangle()
                    .fill(Color.sticksHairline.opacity(0.6))
                    .frame(height: 1)
                    .padding(.top, 12)

                Button {
                    showsEditPars = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text("EDIT PARS")
                                .font(SticksFont.mono(10.5))
                                .kerning(1)
                        }
                        .foregroundStyle(Color.sticksGreen)

                        Text("Scorecard par look wrong? Fix any hole's par here.")
                            .font(SticksFont.sans(12))
                            .foregroundStyle(Color.sticksMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit pars")
                .accessibilityHint("Fix incorrect pars on the scorecard")
            }
        }
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

    // MARK: - Visible round actions

    /// All scores are in — the one moment marking final is THE next step,
    /// so it gets a full-width gold CTA instead of hiding in the ⋯ menu.
    private var finishRoundButton: some View {
        Button {
            showsFinalConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .semibold))
                Text("Finish Round — Mark Final")
                    .font(SticksFont.sans(16, weight: .semibold))
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.sticksGold)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// The ⋯ menu's actions as visible, labeled rows at the bottom of
    /// the page — discoverable by scrolling, no hidden gestures.
    private var roundActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROUND ACTIONS")
                .font(SticksFont.label(11, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Color.sticksFaint)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if canEditDetails {
                    actionRow(
                        icon: "pencil",
                        title: "Edit details",
                        subtitle: "Course, tee time, players — until scoring starts"
                    ) { showsEdit = true }
                    if canMarkFinal || canReopen || canDelete { actionDivider }
                }
                if canMarkFinal {
                    actionRow(
                        icon: "flag.checkered",
                        title: "Mark final",
                        subtitle: "Lock scores and move the round to Recent"
                    ) { showsFinalConfirm = true }
                    if canReopen || canDelete { actionDivider }
                }
                if canReopen {
                    actionRow(
                        icon: "arrow.uturn.backward",
                        title: "Reopen round",
                        subtitle: "Unlock scoring — it won't count until finished again"
                    ) { showsReopenConfirm = true }
                    if canDelete { actionDivider }
                }
                if canDelete {
                    actionRow(
                        icon: "trash",
                        title: "Delete round",
                        subtitle: "Removes it for everyone — can't be undone",
                        isDestructive: true
                    ) { showsDeleteConfirm = true }
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
        .padding(.top, 6)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(Color.sticksHairline.opacity(0.6))
            .frame(height: 1)
            .padding(.leading, 58)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = isDestructive ? .sticksError : .sticksGreen
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.1))
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(isDestructive ? Color.sticksError : Color.sticksInk)
                    Text(subtitle)
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    // MARK: - CTA

    private func gpsButton(_ detail: MatchDetail) -> some View {
        Button {
            showsGPS = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(detail.status == .inProgress ? "Resume on-course GPS" : "Start on-course GPS")
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

    /// Slice 52/53: enabled side games with a native editor (Snake, BBB,
    /// Match press, Wolf, Targets) — the server emits a section for every
    /// enabled game even with zero events, so an on-but-empty game still
    /// gets a card. Targets is settings-only (creator-only endpoint), so
    /// non-creators don't get its card.
    private var editableSideGames: [SideGame] {
        (viewModel.response?.sideGames ?? []).filter { game in
            guard MatchDetailMath.hasNativeEditor(game.kind) else { return false }
            if MatchDetailMath.eventGameKey(game.kind) == "TARGETS" {
                return viewModel.detail?.isCreator == true
            }
            return true
        }
    }

    /// Slice 53: config-driven state lines — Targets shows its saved
    /// settings (or a set-up nudge); an unconfigured Wolf nudges toward
    /// the rotation. Nil keeps the default event-count line.
    private func stateOverride(for game: SideGame) -> String? {
        switch MatchDetailMath.eventGameKey(game.kind) {
        case "TARGETS":
            guard let config = TargetsConfig.decode(from: viewModel.response?.sideGameConfigs["TARGETS"]) else {
                return "Not set up yet — tap to configure"
            }
            let stat = config.stat == TargetsConfig.birdieOrBetter ? "Birdie or better" : "Par or better"
            let ante = config.ante > 0 ? " · $\(config.ante) ante" : ""
            return "\(stat) × \(config.target)\(ante)"
        case "WOLF":
            if WolfConfig.decode(from: viewModel.response?.sideGameConfigs["WOLF"]) == nil {
                return "Set the rotation, then record picks"
            }
            return nil
        default:
            return nil
        }
    }

    /// Recorded events for one game, aliases normalized.
    private func eventCount(for game: SideGame) -> Int {
        let key = MatchDetailMath.eventGameKey(game.kind)
        return (viewModel.response?.sideGameEvents ?? [])
            .filter { MatchDetailMath.eventGameKey($0.gameKind) == key }
            .count
    }

    /// Slice 29: creator-only side-game add/remove, hidden once the
    /// round is completed.
    private var canEditSideGames: Bool {
        guard let detail = viewModel.detail else { return false }
        return detail.isCreator && detail.status != .completed
    }

    private var editSideGamesButton: some View {
        Button {
            showsEditSideGames = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 32, height: 32)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit side games")
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                    Text("Skins, Wolf, Snake and more — on or off any time")
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Edit side games")
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

/// Slice 54: the match-detail content tabs, mirroring the web's
/// Scorecard | Live odds switcher.
enum MatchDetailTab {
    case scorecard
    case liveOdds
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
