//
//  CreateMatchView.swift
//  Sticks
//
//  Slice 20: the "start a round" flow. Single-scroll form — course
//  search (name + one-shot "near me"), 9/18 + front/back, NET/GROSS,
//  the seat list with recent-partner suggestions, side-game chips and
//  a group picker — ending in a pinned ledge CREATE button that posts
//  the match and hands the new id back to the caller.
//
//  Slice 27: the same form reopens in EDIT MODE (pass a
//  MatchEditContext) — pre-filled from the match, "Save changes"
//  PATCHes /matches/:id instead of POSTing.
//

import SwiftUI
import UIKit

struct CreateMatchView: View {
    let user: User
    let session: SessionStore
    /// Called with the match id after a successful POST (or PATCH in
    /// edit mode).
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateMatchViewModel
    @FocusState private var focusedSeat: UUID?
    @FocusState private var isCourseFieldFocused: Bool

    init(
        user: User,
        session: SessionStore,
        editing: MatchEditContext? = nil,
        onCreated: @escaping (String) -> Void
    ) {
        self.user = user
        self.session = session
        self.onCreated = onCreated
        _viewModel = State(initialValue: CreateMatchViewModel(editing: editing, user: user))
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    titleBlock
                    courseSection
                    holesSection
                    scoringSection
                    playersSection
                    sideGamesSection
                    groupSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
        .task {
            await viewModel.bootstrap(user: user, session: session)
        }
    }

    // MARK: - Chrome

    private var header: some View {
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.sticksBg.opacity(0.97))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.isEditing ? "Edit round" : "Start a round")
                .font(SticksFont.display(34, weight: .bold))
                .kerning(-0.7)
                .foregroundStyle(Color.sticksInk)

            Text(
                viewModel.isEditing
                    ? "Adjust the details — nothing changes until you save."
                    : "Pick the course, seat your group, tee off."
            )
            .font(SticksFont.sans(14))
            .foregroundStyle(Color.sticksMuted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5))
            .kerning(1.47)
            .foregroundStyle(Color.sticksGreen)
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
                } else if viewModel.isSearchingCourses {
                    HStack(spacing: 8) {
                        ProgressView().tint(Color.sticksGreen).controlSize(.small)
                        Text("Searching…")
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
                    viewModel.selectCourse(course, session: session)
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
                viewModel.selectedCourse = nil
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

    // MARK: - Holes & scoring

    private var holesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("HOLES")

            SegmentPicker(
                options: [(18, "18 HOLES"), (9, "9 HOLES")],
                selection: Bindable(viewModel).holes
            )

            if viewModel.holes == 9 {
                SegmentPicker(
                    options: [(false, "FRONT 9"), (true, "BACK 9")],
                    selection: Bindable(viewModel).startsOnBack
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.holes)
    }

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("SCORING")

            SegmentPicker(
                options: [("NET", "NET"), ("GROSS", "GROSS")],
                selection: Bindable(viewModel).scoringMode
            )
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

            VStack(spacing: 10) {
                ForEach($viewModel.seats) { $seat in
                    VStack(spacing: 8) {
                        SeatRow(
                            seat: $seat,
                            tees: viewModel.tees,
                            focusedSeat: $focusedSeat,
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

    // MARK: - Create bar

    private var createBar: some View {
        VStack(spacing: 10) {
            if let error = viewModel.createError {
                Text(error)
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                create()
            } label: {
                Group {
                    if viewModel.isCreating {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text(viewModel.isEditing ? "SAVE CHANGES" : "CREATE ROUND")
                            .font(SticksFont.sans(15, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(Color.sticksCream)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(CreateLedgeButtonStyle(showsLedge: viewModel.canCreate))
            .disabled(!viewModel.canCreate)
            .opacity(viewModel.canCreate ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.sticksBg.opacity(0.97))
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
    var focusedSeat: FocusState<UUID?>.Binding
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
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: tees.isEmpty)
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
/// press; no ledge while disabled.
private struct CreateLedgeButtonStyle: ButtonStyle {
    let showsLedge: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && showsLedge
        return ZStack {
            if showsLedge {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sticksGreenDark)
                    .offset(y: 2)
            }
            configuration.label
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 12))
                .offset(y: pressed ? 2 : 0)
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
