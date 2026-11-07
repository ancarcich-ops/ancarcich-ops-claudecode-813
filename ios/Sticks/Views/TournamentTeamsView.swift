//
//  TournamentTeamsView.swift
//  Sticks
//
//  Slice 86: creator-only organizer screen for sides. Form teams from
//  unassigned roster entries (exactly format.teamSize, picked in tap
//  order), auto-seat everyone honouring mutual partner requests, and
//  disband sides. Every refusal shows the server's message verbatim —
//  Appendix B: "Four-man scramble needs 4 players a side, got 3" beats
//  any generic toast on the first tee.
//
//  Data comes from GET /tournaments/:id via TournamentDetailViewModel;
//  every mutation refetches the detail instead of trusting the
//  mutation response.
//

import SwiftUI
import UIKit

struct TournamentTeamsView: View {
    let tournamentId: String
    let session: SessionStore
    /// Fires after every successful mutation so the screen behind
    /// stays in agreement.
    let onChange: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TournamentDetailViewModel
    @State private var selection: [String] = []
    @State private var actionError: String?
    @State private var autoResult: String?
    @State private var isWorking = false

    init(tournamentId: String, session: SessionStore, onChange: @escaping () async -> Void) {
        self.tournamentId = tournamentId
        self.session = session
        self.onChange = onChange
        _viewModel = State(initialValue: TournamentDetailViewModel(tournamentId: tournamentId))
    }

    // MARK: Derived

    private var format: TournamentFormat? { viewModel.response?.tournament.format }
    private var teamSize: Int { format?.teamSize ?? 1 }
    private var teams: [TournamentSide] { viewModel.response?.teams ?? [] }
    private var roster: [TournamentRosterEntry] { viewModel.response?.roster ?? [] }
    private var unassigned: [TournamentRosterEntry] { roster.filter { $0.team == nil } }

    /// Selection stays valid only while every picked id is still
    /// unassigned (a disband or refetch can move people around).
    private var liveSelection: [String] {
        let available = Set(unassigned.map(\.id))
        return selection.filter { available.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    ProgressView().tint(Color.sticksGreen)
                case .failed(let message):
                    failedView(message)
                case .loaded:
                    if viewModel.response != nil {
                        content
                    }
                }
            }
            .navigationTitle("Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(SticksFont.sans(15, weight: .semibold))
                }
            }
            .toolbarBackground(Color.sticksBg, for: .navigationBar)
            .tint(Color.sticksGreen)
            .task { await viewModel.load(session: session) }
            .refreshable { await viewModel.load(session: session, quiet: true) }
        }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let format {
                    formatHeader(format)
                }

                if let error = actionError {
                    errorBanner(error)
                }
                if let result = autoResult {
                    resultBanner(result)
                }

                seatEveryoneSection

                if !unassigned.isEmpty || !liveSelection.isEmpty {
                    unassignedSection
                }

                sidesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(SticksFont.sans(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksMuted)
                .padding(.horizontal, 40)
            Button("Try Again") {
                Task { await viewModel.load(session: session) }
            }
            .font(SticksFont.sans(15, weight: .semibold))
            .foregroundStyle(Color.sticksGreen)
        }
    }

    // MARK: Header

    private func formatHeader(_ format: TournamentFormat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(format.label)
                .font(SticksFont.display(22, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            let unseated = unassigned.count
            Text("\(teams.count) side\(teams.count == 1 ? "" : "s") formed · \(unseated) unassigned")
                .font(SticksFont.mono(11.5))
                .kerning(1)
                .foregroundStyle(Color.sticksMuted)
        }
    }

    // MARK: Auto-seat

    private var seatEveryoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await autoSeat() }
            } label: {
                HStack(spacing: 8) {
                    if isWorking {
                        ProgressView().tint(Color.sticksCream).scaleEffect(0.85)
                    }
                    Image(systemName: "wand.and.stars")
                    Text(isWorking ? "SEATING…" : "SEAT EVERYONE")
                        .font(SticksFont.sans(14, weight: .bold))
                        .kerning(0.4)
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking)
            .opacity(isWorking ? 0.7 : 1)
            .accessibilityLabel("Seat everyone automatically")

            Text("Honours mutual partner requests only — if A asks for B but B asks for C, neither is honoured. A one-sided request is a preference, not an agreement.")
                .font(SticksFont.sans(12))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Unassigned

    @ViewBuilder
    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Unassigned")
                    .font(SticksFont.display(19))
                    .foregroundStyle(Color.sticksInk)
                Spacer()
                Text("\(liveSelection.count)/\(teamSize) PICKED")
                    .font(SticksFont.mono(11.5))
                    .kerning(1)
                    .foregroundStyle(liveSelection.count == teamSize ? Color.sticksGreen : Color.sticksFaint)
            }
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(unassigned.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                    unassignedRow(entry)
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )

            makeTeamButton
        }
    }

    private func unassignedRow(_ entry: TournamentRosterEntry) -> some View {
        let isSelected = liveSelection.contains(entry.id)
        let isFull = liveSelection.count >= teamSize && !isSelected

        return Button {
            toggle(entry.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.sticksGreen : Color.sticksFaint, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.sticksGreen)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(isFull ? Color.sticksMuted : Color.sticksInk)

                    if let partner = entry.partnerName, !partner.isEmpty {
                        Text("PARTNER → \(partner.uppercased())")
                            .font(SticksFont.mono(9.5))
                            .kerning(0.8)
                            .foregroundStyle(Color.sticksGold)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.displayName), \(isSelected ? "picked" : "unassigned")\(entry.partnerName.map { ", wants \($0) as partner" } ?? "")")
    }

    /// Enabled only at EXACTLY teamSize — the server refuses anything
    /// else, and the button says why it's quiet.
    private var makeTeamButton: some View {
        let ready = liveSelection.count == teamSize && !isWorking
        return Button {
            Task { await makeTeam() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.3")
                Text(buttonText)
                    .font(SticksFont.sans(14, weight: .bold))
                    .kerning(0.4)
            }
            .foregroundStyle(ready ? Color.sticksCream : Color.sticksMuted)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(ready ? Color.sticksGreen : Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ready ? Color.clear : Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!ready)
        .accessibilityLabel("Make team from \(liveSelection.count) selected players")
    }

    private var buttonText: String {
        if isWorking { return "WORKING…" }
        let picked = liveSelection.count
        if picked == 0 { return "PICK \(teamSize) PLAYERS" }
        if picked == teamSize { return "MAKE TEAM" }
        return "PICK \(teamSize - picked) MORE"
    }

    // MARK: Formed sides

    @ViewBuilder
    private var sidesSection: some View {
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Formed sides")
                    .font(SticksFont.display(19))
                    .foregroundStyle(Color.sticksInk)
                    .padding(.top, 4)

                VStack(spacing: 0) {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { index, side in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sticksHairline)
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                        sideRow(side)
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
    }

    private func sideRow(_ side: TournamentSide) -> some View {
        HStack(spacing: 12) {
            Text("T\(max(side.team, 1))")
                .font(SticksFont.mono(13))
                .foregroundStyle(Color.sticksGreen)
                .frame(width: 40, height: 40)
                .background(Color.sticksGreen.opacity(0.1))
                .clipShape(.rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(side.members.map(\.displayName).joined(separator: " + "))
                    .font(SticksFont.sans(14.5, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(2)

                if !side.complete {
                    Text("SHORT — NEEDS \(teamSize)")
                        .font(SticksFont.mono(9.5))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksGold)
                }
            }

            Spacer()

            Button {
                Task { await disband(side) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.down")
                        .font(.system(size: 11, weight: .bold))
                    Text("DISBAND")
                        .font(SticksFont.mono(10))
                        .kerning(0.8)
                }
                .foregroundStyle(Color.sticksError)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.sticksError.opacity(0.09))
                .clipShape(.rect(cornerRadius: 9))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isWorking)
            .accessibilityLabel("Disband team \(side.team)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Banners

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

    private func resultBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(SticksFont.sans(13, weight: .medium))
                .foregroundStyle(Color.sticksGreen)
        } icon: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.sticksGreen)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksGreen.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: Actions

    private func toggle(_ rosterId: String) {
        guard !isWorking else { return }
        if let index = selection.firstIndex(of: rosterId) {
            selection.remove(at: index)
        } else if selection.count < teamSize {
            selection.append(rosterId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            // Full — a nudge instead of a silent ignore.
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func makeTeam() {
        let playerIds = liveSelection
        guard playerIds.count == teamSize, !isWorking,
              let token = session.token else { return }
        isWorking = true
        actionError = nil
        autoResult = nil
        Task {
            defer { isWorking = false }
            do {
                _ = try await APIClient.shared.formTeam(
                    tournamentId: tournamentId, playerIds: playerIds, token: token
                )
                selection.removeAll()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await viewModel.load(session: session, quiet: true)
                await onChange()
            } catch let error as APIError {
                actionError = error.message
            } catch {
                actionError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    private func autoSeat() {
        guard !isWorking, let token = session.token else { return }
        isWorking = true
        actionError = nil
        autoResult = nil
        Task {
            defer { isWorking = false }
            do {
                let response = try await APIClient.shared.autoSeatTeams(
                    tournamentId: tournamentId, token: token
                )
                var message = "Formed \(response.formed) side\(response.formed == 1 ? "" : "s")"
                if response.leftOver > 0 {
                    message += ", \(response.leftOver) player\(response.leftOver == 1 ? "" : "s") left over"
                }
                autoResult = message
                selection.removeAll()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                await viewModel.load(session: session, quiet: true)
                await onChange()
            } catch let error as APIError {
                actionError = error.message
            } catch {
                actionError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    private func disband(_ side: TournamentSide) {
        guard !isWorking, let token = session.token else { return }
        isWorking = true
        actionError = nil
        autoResult = nil
        Task {
            defer { isWorking = false }
            do {
                _ = try await APIClient.shared.disbandTeam(
                    tournamentId: tournamentId, team: side.team, token: token
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
    }
}
