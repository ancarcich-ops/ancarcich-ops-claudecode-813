//
//  TournamentOrganizerView.swift
//  Sticks
//
//  Slice 87: creator-only controls so an organizer never has to open
//  the web app on the first tee. Fix a handicap, remove an entrant,
//  close sign-ups, call the event, delete the whole thing.
//
//  Two rules from the spec, enforced here:
//  - The roster handicap SEEDS rounds created from now on. It does not
//    rewrite a round that already exists — those carry their own,
//    deliberately. The copy says so.
//  - Deleting is NOT undoable: roster, rounds and scores go with it.
//    Confirmed before the call.
//

import SwiftUI
import UIKit

struct TournamentOrganizerView: View {
    let tournamentId: String
    let session: SessionStore
    /// Fires after a successful mutation (except delete).
    let onChange: () async -> Void
    /// Fires after a successful DELETE — the caller dismisses the
    /// tournament itself.
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TournamentDetailViewModel
    @State private var actionError: String?
    @State private var isWorking = false

    // Confirmations
    @State private var removingEntry: TournamentRosterEntry?
    @State private var confirmingFinish = false
    @State private var confirmingDelete = false

    // Handicap editor
    @State private var editingEntry: TournamentRosterEntry?
    @State private var handicapText = ""

    // Your entry
    @State private var myHandicapText = ""
    @State private var myPartnerText = ""

    init(
        tournamentId: String,
        session: SessionStore,
        onChange: @escaping () async -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.tournamentId = tournamentId
        self.session = session
        self.onChange = onChange
        self.onDeleted = onDeleted
        _viewModel = State(initialValue: TournamentDetailViewModel(tournamentId: tournamentId))
    }

    private var tournament: TournamentInfo? { viewModel.response?.tournament }
    private var roster: [TournamentRosterEntry] { viewModel.response?.roster ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    ProgressView().tint(Color.sticksGreen)
                case .failed(let message):
                    VStack(spacing: 14) {
                        Text(message)
                            .font(SticksFont.sans(14))
                            .foregroundStyle(Color.sticksMuted)
                            .padding(.horizontal, 40)
                        Button("Try Again") {
                            Task { await viewModel.load(session: session) }
                        }
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                    }
                case .loaded:
                    if tournament != nil {
                        content
                    }
                }
            }
            .navigationTitle("Organize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(SticksFont.sans(15, weight: .semibold))
                }
            }
            .toolbarBackground(Color.sticksBg, for: .navigationBar)
            .tint(Color.sticksGreen)
            .task {
                await viewModel.load(session: session)
            }
            .refreshable { await viewModel.load(session: session, quiet: true) }
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let error = actionError {
                    errorBanner(error)
                }

                if let tournament {
                    signupsSection(tournament)
                }

                rosterSection

                myEntrySection

                eventSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .confirmationDialog(
            removingEntry.map { "Remove \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { removingEntry != nil }, set: { if !$0 { removingEntry = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from roster", role: .destructive) {
                if let entry = removingEntry { Task { await removeEntry(entry) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They come off the entry list and any sides they're seated on.")
        }
        .confirmationDialog("Call the event?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Call the event", role: .destructive) {
                Task { await finishEvent() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The tournament is marked COMPLETED and standings freeze as final.")
        }
        .confirmationDialog("Delete tournament?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete tournament", role: .destructive) {
                Task { await deleteTournament() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Not undoable. The roster, its rounds and their scores go with it.")
        }
        .sheet(item: $editingEntry) { entry in
            handicapEditor(entry)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksError)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.sticksError)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksError.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: Sign-ups

    private func signupsSection(_ tournament: TournamentInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SIGN-UPS")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: tournament.signupsOpen == false ? "person.slash" : "person.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tournament.signupsOpen == false ? "Closed" : "Open")
                            .font(SticksFont.sans(15, weight: .semibold))
                            .foregroundStyle(Color.sticksInk)
                        Text(signupsCaption(tournament))
                            .font(SticksFont.sans(12.5))
                            .foregroundStyle(Color.sticksMuted)
                    }

                    Spacer()

                    Button {
                        Task { await setSignupsOpen(tournament.signupsOpen == false) }
                    } label: {
                        Text(tournament.signupsOpen == false ? "OPEN" : "CLOSE")
                            .font(SticksFont.mono(11))
                            .kerning(1)
                            .foregroundStyle(Color.sticksGreen)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.sticksGreen.opacity(0.1))
                            .clipShape(.rect(cornerRadius: 9))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isWorking)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func signupsCaption(_ tournament: TournamentInfo) -> String {
        if tournament.signupsOpen == false {
            return "New joins via the invite code are refused."
        }
        if tournament.status == .final {
            return "The event is final — nobody new can join anyway."
        }
        return "Anyone with the invite code can join."
    }

    // MARK: Roster

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ROSTER · \(roster.count)")

            if roster.isEmpty {
                Text("Nobody has joined yet.")
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sticksCard)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.sticksHairline, lineWidth: 1)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(roster.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sticksHairline)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                        rosterRow(entry)
                    }
                }
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
            }

            Text("A handicap change seeds rounds created from now on — rounds already bound keep their own card, so a correction on the first tee can't silently change a finished score.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rosterRow(_ entry: TournamentRosterEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.displayName)
                .font(SticksFont.sans(15, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Spacer()

            Button {
                handicapText = entry.handicapAtStart
                    .map { String(format: ($0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f"), $0) }
                    ?? ""
                editingEntry = entry
            } label: {
                Text(entry.handicapAtStart.map { "HCP \(TournamentScoreFormat.score($0))" } ?? "SET HCP")
                    .font(SticksFont.mono(10.5))
                    .kerning(0.8)
                    .foregroundStyle(entry.handicapAtStart == nil ? Color.sticksGold : Color.sticksMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.sticksPanel2)
                    .clipShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking)
            .accessibilityLabel("\(entry.displayName), set handicap")

            Button {
                removingEntry = entry
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.sticksError)
                    .frame(width: 32, height: 32)
                    .background(Color.sticksError.opacity(0.09))
                    .clipShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking)
            .accessibilityLabel("Remove \(entry.displayName) from roster")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Handicap editor

    private func handicapEditor(_ entry: TournamentRosterEntry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Roster handicap for \(entry.displayName)")
                    .font(SticksFont.display(20, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                TextField("12.4", text: $handicapText)
                    .keyboardType(.decimalPad)
                    .font(SticksFont.display(34, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                    .padding(.horizontal, 16)
                    .frame(height: 62)
                    .background(Color.sticksPanel2)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sticksHairline, lineWidth: 1)
                    )

                Text("Seeds rounds created from now on. Rounds already bound keep their own card.")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)

                Spacer()
            }
            .padding(20)
            .background(Color.sticksBg)
            .navigationTitle("Handicap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingEntry = nil }
                        .font(SticksFont.sans(15))
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 14) {
                        if entry.handicapAtStart != nil {
                            Button("Clear") {
                                Task {
                                    await clearHandicap(entry)
                                    editingEntry = nil
                                }
                            }
                            .font(SticksFont.sans(15))
                            .foregroundStyle(Color.sticksError)
                        }
                        Button("Save") {
                            Task {
                                await saveHandicap(entry)
                                editingEntry = nil
                            }
                        }
                        .font(SticksFont.sans(15, weight: .bold))
                        .disabled(parsedHandicap == nil)
                    }
                }
            }
        }
        .presentationDetents([.height(280)])
    }

    private var parsedHandicap: Double? {
        let trimmed = handicapText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value >= 0, value <= 54 else { return nil }
        return value
    }

    private func saveHandicap(_ entry: TournamentRosterEntry) async {
        guard let value = parsedHandicap, let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.setRosterHandicap(
                tournamentId: tournamentId, playerId: entry.id, handicap: value, token: token
            )
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// Clearing sends an explicit `null` — never 0, which would quietly
    /// read as a scratch player.
    private func clearHandicap(_ entry: TournamentRosterEntry) async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.clearRosterHandicap(
                tournamentId: tournamentId, playerId: entry.id, token: token
            )
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    // MARK: Your entry

    private var myEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("YOUR ENTRY")

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Handicap")
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksInk)
                    Spacer()
                    TextField("9", text: $myHandicapText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .frame(width: 90)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)

                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(height: 1)
                    .padding(.leading, 14)

                HStack(spacing: 10) {
                    Text("Partner request")
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksInk)
                    Spacer()
                    TextField("Name", text: $myPartnerText)
                        .multilineTextAlignment(.trailing)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                        .frame(width: 150)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )

            Button {
                Task { await saveMyEntry() }
            } label: {
                Text(isWorking ? "SAVING…" : "SAVE MY ENTRY")
                    .font(SticksFont.sans(13.5, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(Color.sticksCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 11))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking)

            Text("Blank fields are left unchanged. Auto-seating honours MUTUAL partner requests only.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private func saveMyEntry() async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        let handicapText = myHandicapText.trimmingCharacters(in: .whitespaces)
        let handicap = Double(handicapText.replacingOccurrences(of: ",", with: "."))
        if handicapText.isEmpty == false, handicap == nil || handicap?.isFinite != true || (handicap ?? 0) < 0 {
            actionError = "Check the handicap — a number like 12.4 works best."
            return
        }

        do {
            _ = try await APIClient.shared.patchMyEntry(
                tournamentId: tournamentId,
                handicap: handicap,
                partnerName: myPartnerText.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : myPartnerText.trimmingCharacters(in: .whitespaces),
                token: token
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    // MARK: Event actions

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("EVENT")

            VStack(spacing: 0) {
                if tournament?.status != .final {
                    Button {
                        confirmingFinish = true
                    } label: {
                        rowLabel(
                            icon: "flag.checkered",
                            title: "Call the event",
                            caption: "Marks it COMPLETED — standings freeze as final.",
                            tint: Color.sticksInk
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                        .padding(.leading, 46)
                }

                Button {
                    confirmingDelete = true
                } label: {
                    rowLabel(
                        icon: "trash",
                        title: "Delete tournament",
                        caption: "Not undoable — roster, rounds and scores go with it.",
                        tint: Color.sticksError
                    )
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func rowLabel(icon: String, title: String, caption: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(tint)
                Text(caption)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }

    // MARK: Actions

    private func removeEntry(_ entry: TournamentRosterEntry) async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.removeRosterPlayer(
                tournamentId: tournamentId, playerId: entry.id, token: token
            )
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    private func setSignupsOpen(_ open: Bool) async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.setSignupsOpen(
                tournamentId: tournamentId, open: open, token: token
            )
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    private func finishEvent() async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.completeTournament(
                tournamentId: tournamentId, token: token
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await viewModel.load(session: session, quiet: true)
            await onChange()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    private func deleteTournament() async {
        guard let token = session.token, !isWorking else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.deleteTournament(
                tournamentId: tournamentId, token: token
            )
            onDeleted()
        } catch let error as APIError {
            actionError = error.message
        } catch {
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10))
            .kerning(1.2)
            .foregroundStyle(Color.sticksFaint)
    }
}
