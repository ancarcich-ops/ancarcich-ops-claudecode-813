//
//  RoundScoringSheet.swift
//  Sticks
//
//  Slice 100: round scoring mid-round — the app half of POST
//  /matches/:id/scoring. Three edits: the group the round posts into,
//  Net/Gross, and each player's handicap. Course, holes and players
//  stay locked (they change the scorecard itself, not values on it).
//
//  Every save re-counts the round from the strokes already logged —
//  scores never move, every leaderboard re-derives — so save always
//  confirms first. Handicaps go by matchPlayerId and a blank field
//  means "unchanged", never scratch. A scramble scores gross, full
//  stop; the picker locks. The response reconciles: the server drops
//  an unrecognised mode and falls an unknown group back to public.
//

import SwiftUI
import UIKit

struct RoundScoringSheet: View {
    let detail: MatchDetail
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var scoringMode: String
    @State private var groups: [SticksGroup] = []
    /// nil + pickedPublic false = leave the posted group alone (the
    /// detail payload carries no group, so the current one is unknown).
    @State private var selectedGroup: SticksGroup?
    @State private var pickedPublic = false
    @State private var handicapText: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsConfirm = false

    /// A scramble scores gross, whatever anyone picked at the tee.
    private var isScramble: Bool { detail.format == "SCRAMBLE" }

    private var canEdit: Bool { detail.canManageRound && detail.status != .completed }

    init(detail: MatchDetail, viewModel: MatchDetailViewModel, session: SessionStore) {
        self.detail = detail
        self.viewModel = viewModel
        self.session = session
        _scoringMode = State(initialValue: detail.scoringMode.uppercased())
        var texts: [String: String] = [:]
        for player in detail.players {
            texts[player.id] = player.handicap.map { String(format: "%g", $0) } ?? ""
        }
        _handicapText = State(initialValue: texts)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    caption

                    if !canEdit {
                        readOnlyBanner
                    } else {
                        scoringSection
                        groupSection
                        handicapsSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            if canEdit {
                footer
            }
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .alert("Change the round's scoring?", isPresented: $showsConfirm) {
            Button("Save scoring") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every leaderboard recounts from the strokes already logged — the strokes themselves stay put.")
        }
        .task { await loadGroups() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Round settings")
                .font(SticksFont.display(26, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            Text(detail.courseName)
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 6)
    }

    private var caption: some View {
        Text("Change these any time — scores already logged stay put and every leaderboard recalculates. Course, holes and players are locked once the round starts.")
            .font(SticksFont.mono(10.5))
            .kerning(0.3)
            .foregroundStyle(Color.sticksFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var readOnlyBanner: some View {
        Text(detail.status == .completed
            ? "This round is final. Reopen it before changing its scoring."
            : "Only the round's creator can change its scoring.")
            .font(SticksFont.sans(13))
            .foregroundStyle(Color.sticksMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: Scoring mode

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SCORING")

            HStack(spacing: 8) {
                modeChip("NET")
                modeChip("GROSS")

                Spacer(minLength: 0)

                if isScramble {
                    Text("Scramble rounds score gross.")
                        .font(SticksFont.sans(11.5))
                        .foregroundStyle(Color.sticksFaint)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modeChip(_ mode: String) -> some View {
        let selected = scoringMode == mode
        return Button {
            guard !isScramble else { return }
            scoringMode = mode
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(mode)
                .font(SticksFont.mono(12.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(selected ? Color.sticksCream : Color.sticksInk)
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(selected ? Color.sticksGreen : Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.sticksHairline, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isScramble)
        .opacity(isScramble && !selected ? 0.5 : 1)
    }

    // MARK: Posted group

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("POSTS TO")

            Menu {
                Button("Public") {
                    pickedPublic = true
                    selectedGroup = nil
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                ForEach(groups) { group in
                    Button(group.name) {
                        selectedGroup = group
                        pickedPublic = false
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(currentGroupLabel)
                        .font(SticksFont.sans(14, weight: .medium))
                        .foregroundStyle(Color.sticksInk)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sticksMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
            }
            .accessibilityLabel("Group the round posts to")

            if selectedGroup != nil || pickedPublic {
                Text("The round moves to that group's feed. Leaderboards there recount.")
                    .font(SticksFont.sans(11.5))
                    .foregroundStyle(Color.sticksFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The payload carries no group, so until the picker is touched the
    /// row says the round stays where it is.
    private var currentGroupLabel: String {
        if pickedPublic { return "Public" }
        if let selectedGroup { return selectedGroup.name }
        return "Where it is now"
    }

    // MARK: Handicaps

    private var handicapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("HANDICAPS")

            VStack(spacing: 0) {
                ForEach(Array(detail.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline.opacity(0.6))
                            .frame(height: 1)
                            .padding(.leading, 14)
                    }

                    HStack(spacing: 12) {
                        Text(player.displayName)
                            .font(SticksFont.sans(14, weight: .medium))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        TextField("—", text: binding(player.id))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(SticksFont.sans(14, weight: .semibold))
                            .foregroundStyle(Color.sticksInk)
                            .frame(width: 64)
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(Color.sticksPanel2)
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.sticksHairline, lineWidth: 1)
                            )
                            .accessibilityLabel("Handicap for \(player.displayName)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )

            Text("Blank leaves a player's handicap alone. Changing one re-counts their net scores from the strokes already logged.")
                .font(SticksFont.sans(11.5))
                .foregroundStyle(Color.sticksFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ matchPlayerId: String) -> Binding<String> {
        Binding(
            get: { handicapText[matchPlayerId] ?? "" },
            set: { handicapText[matchPlayerId] = $0 }
        )
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SticksFont.mono(11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Color.sticksFaint)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showsConfirm = true
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text("Save scoring")
                            .font(SticksFont.sans(16, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: - Data

    private func loadGroups() async {
        guard let token = session.token else { return }
        groups = (try? await APIClient.shared.groups(token: token))?.groups ?? []
    }

    /// Sends only what changed: the mode when it moved (never on a
    /// scramble), the group only when picked, and a handicap row per
    /// player whose text parses AND differs from what's stored.
    private func save() {
        guard !isSaving else { return }
        var update = ScoringUpdate(scoringMode: nil, groupId: nil, handicaps: nil)

        if !isScramble, scoringMode != detail.scoringMode.uppercased() {
            update.scoringMode = scoringMode
        }
        if pickedPublic {
            update.groupId = "public"
        } else if let selectedGroup {
            update.groupId = selectedGroup.id
        }

        var rows: [ScoringUpdate.Handicap] = []
        for player in detail.players {
            let text = (handicapText[player.id] ?? "")
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ",", with: ".")
            guard !text.isEmpty, let value = Double(text) else { continue }
            guard value != player.handicap else { continue }
            rows.append(ScoringUpdate.Handicap(matchPlayerId: player.id, handicap: text))
        }
        if !rows.isEmpty {
            update.handicaps = rows
        }

        let changed = update.scoringMode != nil || update.groupId != nil || update.handicaps != nil
        guard changed else {
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let result = try await viewModel.setRoundScoring(update, session: session)
                // Reconcile against the server's afterwards-state.
                if let mode = result.scoringMode { scoringMode = mode }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}
