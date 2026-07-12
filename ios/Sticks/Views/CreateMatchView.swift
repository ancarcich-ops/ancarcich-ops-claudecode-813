//
//  CreateMatchView.swift
//  Sticks
//
//  Slice 20: the "start a round" flow — course search (name + one-shot
//  "near me"), 9/18 + front/back, NET/GROSS, the seat list with
//  recent-partner suggestions, side-game chips and a group picker,
//  ending in a pinned ledge CREATE button that posts the match and
//  hands the new id back to the caller.
//
//  Slice 27: the same form reopens in EDIT MODE (pass a
//  MatchEditContext) — pre-filled from the match, "Save changes"
//  PATCHes /matches/:id instead of POSTing.
//
//  Slice 32: reorganized into a step-by-step wizard — Course → Round →
//  Players → Side games (solo rounds skip Side games), with a labeled
//  step indicator up top and a pinned Back/Next footer. Same sections,
//  same view model, same API calls — one step on screen at a time.
//
//  Slice 45: web parity — Course folded into a single progressive-
//  reveal "Round" step (Course → Tee & holes → Format), one group open
//  at a time, answered groups collapsing to tappable chips. Adds the
//  tee-time picker (→ scheduledAt), Full 18/Front 9/Back 9, and the
//  Solo/Twosome/Threesome/Foursome player-count chips.
//

import SwiftUI
import UIKit

struct CreateMatchView: View {
    /// One wizard step — each shows one slice of the old single-scroll
    /// form. Solo rounds (just the "me" seat) skip `.sideGames`.
    enum Step: Int, CaseIterable {
        case round
        case players
        case sideGames
    }

    let user: User
    let session: SessionStore
    /// Called with the match id after a successful POST (or PATCH in
    /// edit mode).
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateMatchViewModel
    @State private var step: Step
    /// True while moving forward — drives the slide direction.
    @State private var isAdvancing = true
    @FocusState private var focusedSeat: UUID?
    @FocusState private var isCourseFieldFocused: Bool

    init(
        user: User,
        session: SessionStore,
        editing: MatchEditContext? = nil,
        initialStep: Step = .round,
        tournamentId: String? = nil,
        onCreated: @escaping (String) -> Void
    ) {
        self.user = user
        self.session = session
        self.onCreated = onCreated
        _step = State(initialValue: initialStep)
        _viewModel = State(initialValue: CreateMatchViewModel(
            editing: editing,
            user: user,
            tournamentId: tournamentId
        ))
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    stepTitleBlock
                    stepSections
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(stepTransition)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footerBar }
        .task {
            async let bootstrap: Void = viewModel.bootstrap(user: user, session: session)
            async let nearby: Void = viewModel.autoLoadNearby(session: session)
            _ = await (bootstrap, nearby)
        }
    }

    // MARK: - Wizard plumbing

    /// The steps this round actually shows — solo rounds have no
    /// side-games step (mirrors the web, where solo ends at Players).
    private var visibleSteps: [Step] {
        var steps: [Step] = [.round, .players]
        if viewModel.seats.count > 1 {
            steps.append(.sideGames)
        }
        return steps
    }

    private var isLastStep: Bool { step == visibleSteps.last }

    /// Per-step gate on Next. The final step defers to `canCreate`.
    private func canLeave(_ step: Step) -> Bool {
        switch step {
        case .round: return viewModel.selectedCourse != nil && viewModel.roundStage >= 2
        case .players: return viewModel.seatsAreValid && viewModel.teamsAreValid
        case .sideGames: return true
        }
    }

    private var isPrimaryEnabled: Bool {
        isLastStep ? viewModel.canCreate : canLeave(step)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isAdvancing ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isAdvancing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func goNext() {
        guard let index = visibleSteps.firstIndex(of: step),
              index + 1 < visibleSteps.count else { return }
        if step == .round {
            // Leaving the Round step collapses every group to a chip,
            // so coming Back shows the web's answered state.
            viewModel.advanceRound(from: 2)
        }
        focusedSeat = nil
        isCourseFieldFocused = false
        isAdvancing = true
        withAnimation(.easeOut(duration: 0.22)) {
            step = visibleSteps[index + 1]
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func goBack() {
        guard let index = visibleSteps.firstIndex(of: step), index > 0 else { return }
        focusedSeat = nil
        isCourseFieldFocused = false
        isAdvancing = false
        withAnimation(.easeOut(duration: 0.22)) {
            step = visibleSteps[index - 1]
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The current step's sections — one step's content on screen at a
    /// time, each a plain VStack of cards on the cream background.
    @ViewBuilder private var stepSections: some View {
        switch step {
        case .round:
            roundRevealSections
        case .players:
            playersSection
        case .sideGames:
            sideGamesSection
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.isEditing ? "EDIT ROUND" : "NEW ROUND")
                    .font(SticksFont.mono(11))
                    .kerning(1.54)
                    .foregroundStyle(Color.sticksGreen)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sticksMuted)
                        .frame(width: 32, height: 32)
                        .background(Color.sticksPanel2)
                        .clipShape(.circle)
                }
                .accessibilityLabel("Close")
            }

            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.sticksBg.opacity(0.97))
    }

    /// Labeled dots — Course · Round · Players · Side games — with the
    /// current one in accent green. The side-games dot disappears for
    /// solo rounds so the count stays honest.
    private var stepIndicator: some View {
        HStack(spacing: 14) {
            ForEach(visibleSteps, id: \.self) { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(item == step ? Color.sticksGreen : Color.sticksHairline)
                        .frame(width: 6, height: 6)

                    Text(stepLabel(item))
                        .font(SticksFont.mono(9))
                        .kerning(1.1)
                        .foregroundStyle(item == step ? Color.sticksGreen : Color.sticksFaint)
                }
            }

            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.18), value: step)
        .animation(.easeOut(duration: 0.18), value: visibleSteps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \((visibleSteps.firstIndex(of: step) ?? 0) + 1) of \(visibleSteps.count): \(stepLabel(step).capitalized)")
    }

    private func stepLabel(_ step: Step) -> String {
        switch step {
        case .round: return "ROUND"
        case .players: return "PLAYERS"
        case .sideGames: return "SIDE GAMES"
        }
    }

    private var stepTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stepTitle)
                .font(SticksFont.display(34, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Color.sticksInk)

            Text(stepSubtitle)
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var stepTitle: String {
        switch step {
        case .round: return viewModel.isEditing ? "Edit round" : "Start a round"
        case .players: return "Players"
        case .sideGames: return "Side games"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .round:
            return viewModel.isEditing
                ? "Adjust the details — nothing changes until you save."
                : "Course, tee time, and format."
        case .players:
            return "Seat your group and set handicaps."
        case .sideGames:
            return "Optional — pick what's in play."
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5))
            .kerning(1.47)
            .foregroundStyle(Color.sticksGreen)
    }

    // MARK: - Round step — guided reveal (slice 45)

    /// The web's progressive-reveal Round step: Course → Tee & holes →
    /// Format, one group open at a time, answered groups collapsing to
    /// tappable chips that re-open on tap.
    private var roundRevealSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            courseGroup

            if viewModel.roundStage >= 1 {
                teeHolesGroup
            }

            if viewModel.roundStage >= 2 {
                formatGroup
                groupSection
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.roundStage)
        .animation(.easeOut(duration: 0.22), value: viewModel.openRoundGroup)
    }

    @ViewBuilder private var courseGroup: some View {
        if viewModel.openRoundGroup == 0 || viewModel.selectedCourse == nil {
            VStack(alignment: .leading, spacing: 10) {
                courseSection

                if viewModel.selectedCourse != nil, viewModel.roundStage >= 1 {
                    roundContinueButton(from: 0, label: "DONE")
                }
            }
        } else if let course = viewModel.selectedCourse {
            roundChip(label: "COURSE", summary: course.name, group: 0)
        }
    }

    @ViewBuilder private var teeHolesGroup: some View {
        if viewModel.openRoundGroup == 1 {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("TEE TIME & HOLES")

                teeTimeRow

                SegmentPicker(
                    options: [
                        (CreateMatchViewModel.HolesChoice.full18, "FULL 18"),
                        (.front9, "FRONT 9"),
                        (.back9, "BACK 9"),
                    ],
                    selection: Bindable(viewModel).holesChoice
                )

                roundContinueButton(from: 1, label: viewModel.roundStage >= 3 ? "DONE" : "CONTINUE")
            }
        } else {
            roundChip(label: "TEE & HOLES", summary: teeHolesSummary, group: 1)
        }
    }

    /// Native date/time picker defaulting to now — maps to the create
    /// body's `scheduledAt`.
    private var teeTimeRow: some View {
        HStack(spacing: 10) {
            Text("TEE TIME")
                .font(SticksFont.mono(9))
                .kerning(1.1)
                .foregroundStyle(Color.sticksFaint)

            Spacer(minLength: 8)

            DatePicker(
                "",
                selection: Bindable(viewModel).teeTime,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .tint(Color.sticksGreen)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    @ViewBuilder private var formatGroup: some View {
        if viewModel.openRoundGroup == 2 {
            VStack(alignment: .leading, spacing: 18) {
                formatSection
                playerCountSection
                scoringSection

                if viewModel.roundStage >= 3 {
                    roundContinueButton(from: 2, label: "DONE")
                }
            }
        } else {
            roundChip(label: "FORMAT", summary: formatSummary, group: 2)
        }
    }

    /// Solo / Twosome / Threesome / Foursome — sets how many seats the
    /// Players step starts with. Solo forces Individual.
    private var playerCountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("NUMBER OF PLAYERS")

            SegmentPicker(
                options: [(1, "SOLO"), (2, "TWOSOME"), (3, "THREESOME"), (4, "FOURSOME")],
                selection: playerCountBinding
            )

            Text(
                viewModel.seats.count == 1
                    ? "Just you — solo rounds play Individual."
                    : "You'll name everyone on the Players step."
            )
            .font(SticksFont.mono(10.5, weight: .regular))
            .foregroundStyle(Color.sticksFaint)
        }
    }

    private var playerCountBinding: Binding<Int> {
        Binding(
            get: { viewModel.seats.count },
            set: { count in
                withAnimation(.easeOut(duration: 0.18)) {
                    viewModel.setPlayerCount(count)
                }
            }
        )
    }

    /// A collapsed, answered group — tap to re-open it, like the web's
    /// StepChip.
    private func roundChip(label: String, summary: String, group: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.22)) {
                viewModel.reopenRoundGroup(group)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(SticksFont.mono(9))
                        .kerning(1.1)
                        .foregroundStyle(Color.sticksGreen)

                    Text(summary)
                        .font(SticksFont.sans(14.5, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("EDIT")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.capsule)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(label): \(summary). Double tap to edit.")
    }

    /// Inline advance for a reveal group — green-tinted, deliberately
    /// lighter than the footer CTA.
    private func roundContinueButton(from group: Int, label: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.22)) {
                viewModel.advanceRound(from: group)
            }
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .kerning(0.5)

                if label == "CONTINUE" {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Color.sticksGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.sticksGreen.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksGreen.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// "7/11 2:05PM · 18 holes" — the web's chip summary shape.
    private static let teeTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mma"
        return formatter
    }()

    private var teeHolesSummary: String {
        "\(Self.teeTimeFormatter.string(from: viewModel.teeTime)) · \(holesLabel)"
    }

    private var holesLabel: String {
        switch viewModel.holesChoice {
        case .full18: return "18 holes"
        case .front9: return "Front 9"
        case .back9: return "Back 9"
        }
    }

    private var formatSummary: String {
        let formatName: String
        switch viewModel.format {
        case "SCRAMBLE": formatName = "Scramble"
        case "BOTH": formatName = "Both"
        default: formatName = "Individual"
        }
        let scoring = viewModel.scoringMode == "GROSS" ? "Gross" : "Net"
        return "\(formatName) · \(playerCountLabel) · \(scoring)"
    }

    private var playerCountLabel: String {
        switch viewModel.seats.count {
        case 1: return "Solo"
        case 2: return "Twosome"
        case 3: return "Threesome"
        case 4: return "Foursome"
        default: return "\(viewModel.seats.count) players"
        }
    }

    // MARK: - Course

    @ViewBuilder private var courseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("COURSE")

            if let course = viewModel.selectedCourse {
                selectedCourseChip(course)
            } else {
                courseSearchField

                if viewModel.nearMeFailed {
                    Text("Couldn't find you — search by name instead.")
                        .font(SticksFont.mono(10.5))
                        .foregroundStyle(Color.sticksMuted)
                }

                if !viewModel.courseResults.isEmpty {
                    courseResultsCard
                } else if viewModel.isSearchingCourses || viewModel.isLocating {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color.sticksGreen).controlSize(.small)
                        Text(viewModel.isLocating ? "Finding courses near you…" : "Searching…")
                            .font(SticksFont.mono(11))
                            .foregroundStyle(Color.sticksFaint)
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }

    private var courseSearchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)

                TextField(
                    "",
                    text: Bindable(viewModel).courseQuery,
                    prompt: Text("Search courses…")
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksFaint)
                )
                .font(SticksFont.sans(15))
                .foregroundStyle(Color.sticksInk)
                .autocorrectionDisabled()
                .focused($isCourseFieldFocused)
                .onChange(of: viewModel.courseQuery) { _, _ in
                    viewModel.searchCourses(session: session)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCourseFieldFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
            .shadow(color: isCourseFieldFocused ? Color.sticksGreen.opacity(0.25) : .clear, radius: 5)

            if !viewModel.isLocationDenied {
                nearMeButton
            }
        }
    }

    private var nearMeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await viewModel.findNearby(session: session) }
        } label: {
            Group {
                if viewModel.isLocating {
                    ProgressView().tint(Color.sticksGreen).controlSize(.small)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("NEAR ME")
                            .font(SticksFont.mono(10.5))
                            .kerning(0.8)
                    }
                    .foregroundStyle(Color.sticksGreen)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 50)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(viewModel.isLocating)
        .accessibilityLabel("Find courses near me")
    }

    private var courseResultsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.courseResults.prefix(8).enumerated()), id: \.element.id) { index, course in
                if index > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        viewModel.selectCourse(course, session: session)
                    }
                    isCourseFieldFocused = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    courseRow(course)
                }
                .buttonStyle(RowPressStyle())
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private func courseRow(_ course: CourseResult) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(SticksFont.display(16))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text(courseMeta(course))
                    .font(SticksFont.mono(11, weight: .regular))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let distance = course.distanceMi {
                Text(String(format: "%.1f MI", distance))
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private func selectedCourseChip(_ course: CourseResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sticksCream)
                .frame(width: 38, height: 38)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .font(SticksFont.display(18))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text(courseMeta(course))
                    .font(SticksFont.mono(11, weight: .regular))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.22)) {
                    viewModel.selectedCourse = nil
                }
            } label: {
                Text("CHANGE")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.capsule)
            }
        }
        .padding(12)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksGreen.opacity(0.45), lineWidth: 1)
        )
    }

    private func courseMeta(_ course: CourseResult) -> String {
        var parts: [String] = []
        if let city = course.city, !city.isEmpty { parts.append(city) }
        parts.append("\(course.holes) holes")
        return parts.joined(separator: " · ")
    }

    // MARK: - Scoring

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SCORING")

            SegmentPicker(
                options: [("NET", "NET"), ("GROSS", "GROSS")],
                selection: Bindable(viewModel).scoringMode
            )
        }
    }

    // MARK: - Format (slice 39)

    /// Individual / Scramble / Both, matching the web. Teams are seated
    /// on the Players step — a round that ends up solo is forced back to
    /// Individual there (and again at submit, belt & braces).
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FORMAT")

            SegmentPicker(
                options: [
                    ("INDIVIDUAL", "INDIVIDUAL"),
                    ("SCRAMBLE", "SCRAMBLE"),
                    ("BOTH", "BOTH"),
                ],
                selection: Bindable(viewModel).format
            )

            Text(formatHint)
                .font(SticksFont.mono(10.5, weight: .regular))
                .foregroundStyle(Color.sticksFaint)
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.format)
    }

    private var formatHint: String {
        switch viewModel.format {
        case "SCRAMBLE":
            return "One ball per team — you'll split into Team A and Team B next."
        case "BOTH":
            return "Everyone plays their own ball, plus a team match on top."
        default:
            return "All-vs-all. Scramble: one ball per team. Both: individual + a team match."
        }
    }

    // MARK: - Players

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("PLAYERS")

                Spacer()

                Text("\(viewModel.seats.count)/8")
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksFaint)
            }

            if viewModel.scoringMode == "GROSS" {
                Text("Handicaps are kept for net scoring.")
                    .font(SticksFont.mono(10.5, weight: .regular))
                    .foregroundStyle(Color.sticksFaint)
            }

            if viewModel.usesTeams {
                teamSummary
            }

            VStack(spacing: 10) {
                ForEach($viewModel.seats) { $seat in
                    VStack(spacing: 8) {
                        SeatRow(
                            seat: $seat,
                            tees: viewModel.tees,
                            showsTeam: viewModel.usesTeams,
                            focusedSeat: $focusedSeat,
                            onSelectTeam: { team in
                                viewModel.setTeam(seatId: seat.id, team: team)
                                UISelectionFeedbackGenerator().selectionChanged()
                            },
                            onSelectTee: { tee in
                                viewModel.setTee(seatId: seat.id, teeId: tee.id)
                                UISelectionFeedbackGenerator().selectionChanged()
                            },
                            onNameEdited: { query in
                                viewModel.unlinkIfEdited(seatId: seat.id)
                                viewModel.searchPlayers(query: query, session: session)
                            },
                            onStep: { delta in
                                viewModel.stepHandicap(seatId: seat.id, by: delta)
                            },
                            onRemove: {
                                if focusedSeat == seat.id { focusedSeat = nil }
                                withAnimation(.easeOut(duration: 0.18)) {
                                    viewModel.removeSeat(id: seat.id)
                                }
                            }
                        )

                        if focusedSeat == seat.id, !seat.isMe {
                            suggestionsCard(for: seat)
                        }
                    }
                }
            }

            if viewModel.canAddSeat {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        viewModel.addSeat()
                    }
                    if let newSeat = viewModel.seats.last {
                        focusedSeat = newSeat.id
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add player")
                            .font(SticksFont.sans(14, weight: .semibold))
                    }
                    .foregroundStyle(Color.sticksGreen)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.sticksGreen.opacity(0.07))
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sticksGreen.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.usesTeams)
    }

    /// Live Team A / Team B tally for SCRAMBLE/BOTH — with the "both
    /// teams need a player" nudge while one side is empty.
    private var teamSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("TEAM A \(viewModel.teamACount)")
                    .font(SticksFont.mono(10.5))
                    .kerning(0.8)
                    .foregroundStyle(viewModel.teamACount > 0 ? Color.sticksGreen : Color.sticksError)

                Text("·")
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksFaint)

                Text("TEAM B \(viewModel.teamBCount)")
                    .font(SticksFont.mono(10.5))
                    .kerning(0.8)
                    .foregroundStyle(viewModel.teamBCount > 0 ? Color.sticksGreen : Color.sticksError)
            }

            if !viewModel.teamsAreValid {
                Text(
                    viewModel.seats.count < 2
                        ? "\(viewModel.format == "BOTH" ? "Both" : "Scramble") needs at least 2 players — add one below."
                        : "Both teams need at least one player."
                )
                .font(SticksFont.mono(10.5, weight: .regular))
                .foregroundStyle(Color.sticksError)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.teamsAreValid)
    }

    @ViewBuilder private func suggestionsCard(for seat: CreateMatchViewModel.Seat) -> some View {
        let suggestions = viewModel.suggestions(forQuery: seat.name)
        let isRecent = seat.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(isRecent ? "RECENT PARTNERS" : "PLAYERS")
                    .font(SticksFont.mono(9))
                    .kerning(1.1)
                    .foregroundStyle(Color.sticksFaint)
                    .padding(.horizontal, 14)
                    .padding(.top, 11)
                    .padding(.bottom, 7)

                ForEach(suggestions.prefix(5)) { suggestion in
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    Button {
                        viewModel.link(seatId: seat.id, to: suggestion)
                        focusedSeat = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        suggestionRow(suggestion)
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .transition(.opacity)
        }
    }

    private func suggestionRow(_ suggestion: PlayerSuggestion) -> some View {
        HStack(spacing: 10) {
            PlayerBubble(name: suggestion.displayName, avatarUrl: suggestion.avatarUrl, seed: suggestion.userId, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.displayName)
                    .font(SticksFont.sans(13.5, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text("@\(suggestion.username)")
                    .font(SticksFont.mono(10, weight: .regular))
                    .foregroundStyle(Color.sticksFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let handicap = suggestion.lastHandicap {
                Text("HCP \(CreateMatchViewModel.formatHandicap(handicap))")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.sticksPanel2)
                    .clipShape(.capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(.rect)
    }

    // MARK: - Side games

    private var sideGamesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("SIDE GAMES")

                Text("OPTIONAL")
                    .font(SticksFont.mono(9))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)
            }

            let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(availableSideGames, id: \.kind) { game in
                    sideGameChip(kind: game.kind, label: game.label)
                }
            }
        }
    }

    /// Nassau is 18-hole only — hidden on 9-hole rounds (the server
    /// rejects it there anyway).
    private var availableSideGames: [(kind: String, label: String)] {
        var games: [(String, String)] = [
            ("SKINS", "Skins"),
            ("STABLEFORD", "Stableford"),
        ]
        if viewModel.holes == 18 {
            games.append(("NASSAU", "Nassau"))
        }
        games.append(contentsOf: [
            ("BBB", "BBB"),
            ("SNAKE", "Snake"),
            ("WOLF", "Wolf"),
        ])
        return games
    }

    private func sideGameChip(kind: String, label: String) -> some View {
        let isOn = viewModel.sideGames.contains(kind)
        return Button {
            viewModel.toggleSideGame(kind)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(SticksFont.sans(13.5, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.sticksGreen : Color.sticksMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isOn ? Color.sticksGreen.opacity(0.1) : Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.sticksGreen.opacity(0.45) : Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeOut(duration: 0.12), value: isOn)
    }

    // MARK: - Group

    @ViewBuilder private var groupSection: some View {
        if !viewModel.groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("POST TO")

                Menu {
                    Button("Public (no group)") {
                        viewModel.selectedGroupId = nil
                    }
                    ForEach(viewModel.groups) { group in
                        Button(group.name) {
                            viewModel.selectedGroupId = group.id
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if let group = selectedGroup {
                            Circle()
                                .fill(GroupIdentity.color(for: group.id))
                                .frame(width: 9, height: 9)
                            Text(group.name)
                                .font(SticksFont.sans(15, weight: .semibold))
                                .foregroundStyle(Color.sticksInk)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sticksFaint)
                            Text("Public (no group)")
                                .font(SticksFont.sans(15))
                                .foregroundStyle(Color.sticksMuted)
                        }

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.sticksFaint)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Color.sticksPanel2)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sticksHairline, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var selectedGroup: SticksGroup? {
        viewModel.selectedGroupId.flatMap { id in
            viewModel.groups.first { $0.id == id }
        }
    }

    // MARK: - Footer (Back / Next / Create)

    private var footerBar: some View {
        VStack(spacing: 10) {
            if let error = viewModel.createError {
                Text(error)
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if step != visibleSteps.first {
                    backButton
                }

                Button {
                    if isLastStep {
                        create()
                    } else {
                        goNext()
                    }
                } label: {
                    Group {
                        if viewModel.isCreating {
                            ProgressView().tint(Color.sticksCream)
                        } else {
                            HStack(spacing: 7) {
                                Text(primaryLabel)
                                    .font(SticksFont.sans(15, weight: .bold))
                                    .kerning(0.6)

                                if !isLastStep {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .foregroundStyle(Color.sticksCream)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(CreateLedgeButtonStyle(showsLedge: isPrimaryEnabled))
                .disabled(!isPrimaryEnabled)
                .opacity(isPrimaryEnabled ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.sticksBg.opacity(0.97))
        .animation(.easeOut(duration: 0.18), value: step)
    }

    private var primaryLabel: String {
        guard isLastStep else { return "NEXT" }
        return viewModel.isEditing ? "SAVE CHANGES" : "CREATE ROUND"
    }

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .bold))
                Text("BACK")
                    .font(SticksFont.mono(11))
                    .kerning(1)
            }
            .foregroundStyle(Color.sticksMuted)
            .frame(width: 92, height: 52)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(viewModel.isCreating)
        .accessibilityLabel("Back")
    }

    private func create() {
        guard viewModel.canCreate else { return }
        focusedSeat = nil
        Task {
            if let matchId = await viewModel.create(session: session) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCreated(matchId)
            } else if viewModel.createError != nil {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Seat row

private struct SeatRow: View {
    @Binding var seat: CreateMatchViewModel.Seat
    let tees: [CourseTee]
    /// True for SCRAMBLE/BOTH — shows the Team A / Team B toggle.
    let showsTeam: Bool
    var focusedSeat: FocusState<UUID?>.Binding
    let onSelectTeam: (Int) -> Void
    let onSelectTee: (CourseTee) -> Void
    let onNameEdited: (String) -> Void
    let onStep: (Double) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mainRow

            if !tees.isEmpty {
                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                teeRow
            }

            if showsTeam {
                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                teamRow
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: tees.isEmpty)
        .animation(.easeOut(duration: 0.18), value: showsTeam)
    }

    // MARK: Team picker (slice 39)

    /// Team A / Team B toggle for SCRAMBLE and BOTH rounds.
    private var teamRow: some View {
        HStack(spacing: 8) {
            Text("TEAM")
                .font(SticksFont.mono(9))
                .kerning(1.1)
                .foregroundStyle(Color.sticksFaint)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                teamButton(0, label: "A")
                teamButton(1, label: "B")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func teamButton(_ team: Int, label: String) -> some View {
        let isActive = seat.team == team
        return Button {
            guard !isActive else { return }
            onSelectTeam(team)
        } label: {
            Text(label)
                .font(SticksFont.mono(10.5))
                .kerning(0.6)
                .foregroundStyle(isActive ? Color.sticksCream : Color.sticksMuted)
                .frame(width: 44, height: 26)
                .background(isActive ? Color.sticksGreen : Color.sticksPanel2)
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .stroke(isActive ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .accessibilityLabel("Team \(label) for \(seat.name.isEmpty ? "player" : seat.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            PlayerBubble(
                name: seat.name,
                avatarUrl: seat.avatarUrl,
                seed: seat.userId ?? seat.id.uuidString,
                size: 34,
                isMe: seat.isMe
            )

            VStack(alignment: .leading, spacing: 1) {
                if seat.isMe {
                    (
                        Text(seat.name).foregroundStyle(Color.sticksInk)
                        + Text("  (you)").foregroundStyle(Color.sticksFaint)
                    )
                    .font(SticksFont.sans(14.5, weight: .semibold))
                    .lineLimit(1)
                } else {
                    TextField(
                        "",
                        text: $seat.name,
                        prompt: Text("Player name")
                            .font(SticksFont.sans(14.5))
                            .foregroundStyle(Color.sticksFaint)
                    )
                    .font(SticksFont.sans(14.5, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .autocorrectionDisabled()
                    .focused(focusedSeat, equals: seat.id)
                    .onChange(of: seat.name) { _, newValue in
                        guard focusedSeat.wrappedValue == seat.id else { return }
                        onNameEdited(newValue)
                    }
                }

                if let username = seat.username {
                    Text("@\(username)")
                        .font(SticksFont.mono(10, weight: .regular))
                        .foregroundStyle(Color.sticksFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            handicapStepper

            if !seat.isMe {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sticksFaint)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Remove \(seat.name.isEmpty ? "player" : seat.name)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, seat.isMe ? 12 : 6)
        .padding(.vertical, 10)
    }

    // MARK: Tee picker

    private var selectedTee: CourseTee? {
        tees.first { $0.id == seat.teeId }
    }

    /// Compact per-seat tee menu — always seeded with the course default
    /// when tees exist, so it never blocks Create.
    private var teeRow: some View {
        Menu {
            ForEach(tees) { tee in
                Button {
                    onSelectTee(tee)
                } label: {
                    if tee.id == seat.teeId {
                        Label(Self.teeLabel(tee, withEstTag: true), systemImage: "checkmark")
                    } else {
                        Text(Self.teeLabel(tee, withEstTag: true))
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text("TEE")
                    .font(SticksFont.mono(9))
                    .kerning(1.1)
                    .foregroundStyle(Color.sticksFaint)

                Spacer(minLength: 8)

                if let tee = selectedTee {
                    Text(Self.teeLabel(tee, withEstTag: false))
                        .font(SticksFont.mono(10.5))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    if tee.estimated {
                        Text("est.")
                            .font(SticksFont.mono(8.5, weight: .regular))
                            .foregroundStyle(Color.sticksFaint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.sticksPanel2)
                            .clipShape(.capsule)
                    }
                } else {
                    Text("Choose tee")
                        .font(SticksFont.mono(10.5, weight: .regular))
                        .foregroundStyle(Color.sticksMuted)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(.rect)
        }
        .accessibilityLabel("Tee for \(seat.name.isEmpty ? "player" : seat.name)")
    }

    /// "Blue · M · 70.0/118 · 6445y" (+ " · est." inside menus, where
    /// the tag can't render as a separate chip).
    private static func teeLabel(_ tee: CourseTee, withEstTag: Bool) -> String {
        var parts = [
            tee.name,
            tee.gender,
            String(format: "%.1f", tee.rating) + "/\(tee.slope)",
        ]
        if let yardage = tee.yardage {
            parts.append("\(yardage)y")
        }
        if withEstTag, tee.estimated {
            parts.append("est.")
        }
        return parts.joined(separator: " · ")
    }

    /// −/+ around a typeable handicap value. Blank = invalid (the
    /// create button stays disabled), not zero.
    private var handicapStepper: some View {
        HStack(spacing: 0) {
            stepButton(glyph: "minus", delta: -1)

            TextField("", text: $seat.handicapText)
                .font(SticksFont.mono(13.5))
                .foregroundStyle(
                    CreateMatchViewModel.parseHandicap(seat.handicapText) == nil
                        ? Color.sticksError
                        : Color.sticksInk
                )
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 44)

            stepButton(glyph: "plus", delta: 1)
        }
        .frame(height: 36)
        .background(Color.sticksPanel2)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .accessibilityLabel("Handicap")
    }

    private func stepButton(glyph: String, delta: Double) -> some View {
        Button {
            onStep(delta)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.sticksMuted)
                .frame(width: 30, height: 36)
                .contentShape(.rect)
        }
    }
}

// MARK: - Pieces

/// Avatar bubble — photo when a URL exists, otherwise initials on a
/// stable identity color (green for the signed-in user's seat).
private struct PlayerBubble: View {
    let name: String
    let avatarUrl: String?
    let seed: String
    let size: CGFloat
    var isMe = false

    var body: some View {
        Group {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                Color.sticksPanel2
                    .overlay {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            initialsView
                        }
                        .allowsHitTesting(false)
                    }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }

    private var initialsView: some View {
        Text(initials)
            .font(SticksFont.label(size * 0.34, weight: .bold))
            .foregroundStyle(Color.sticksCream)
            .frame(width: size, height: size)
            .background(isMe ? Color.sticksGreen : GroupIdentity.color(for: seed))
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// Equal-width mono segments — accent fill + cream when active,
/// panel2 + hairline when idle (the slice-16 segment language).
private struct SegmentPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isActive = option.0 == selection
                Button {
                    guard !isActive else { return }
                    selection = option.0
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(option.1)
                        .font(SticksFont.mono(11.5))
                        .kerning(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isActive ? Color.sticksCream : Color.sticksMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(isActive ? Color.sticksGreen : Color.sticksPanel2)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isActive ? Color.clear : Color.sticksHairline, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .animation(.easeOut(duration: 0.14), value: selection)
    }
}

/// Accent-filled button on a 2pt darker-green ledge that compresses on
/// press; no ledge while disabled. The ledge lives in a `.background`
/// so it can never size past the label — the old free-floating ZStack
/// shape was flexible and could balloon into a full-screen green block
/// (slice 39's Course-step takeover).
private struct CreateLedgeButtonStyle: ButtonStyle {
    let showsLedge: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && showsLedge
        return configuration.label
            .background(Color.sticksGreen)
            .clipShape(.rect(cornerRadius: 12))
            .offset(y: pressed ? 2 : 0)
            .background {
                if showsLedge {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sticksGreenDark)
                        .offset(y: 2)
                }
            }
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sticksPanel2.opacity(0.6) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    CreateMatchView(
        user: User(id: "1", username: "tj", displayName: "Tj Sokoll"),
        session: SessionStore()
    ) { _ in }
}
