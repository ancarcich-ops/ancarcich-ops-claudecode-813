//
//  EditSideGamesSheet.swift
//  Sticks
//
//  Slice 99: the server-driven side-games editor, reached from the
//  round detail's CTA (creator, not completed). The GET
//  /matches/:id/side-games payload owns the game list, blurbs and
//  eligibility — the app never hard-codes a game the scorer will
//  refuse. Saving posts the FULL desired set of kinds; the response's
//  `kinds` is reconciled back (the server drops ineligible games and
//  preserves a configured team-vs-team).
//
//  Slice 99 rule the user asked for: on a round already underway, Save
//  shows a confirmation first — turning a game on mid-round back-fills
//  every hole already logged, which should never be a surprise.
//
//  Game settings (Stableford scale, BBB points, Snake stake, Nassau
//  presses) open as a nested sheet reusing the slice-57/58 editors.
//

import SwiftUI
import UIKit

struct EditSideGamesSheet: View {
    let detail: MatchDetail
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var picker: SideGamesPicker?
    @State private var loadFailed: String?
    /// Local on/off state keyed by kind — rebuilt from each GET (and
    /// reconciled from each POST response).
    @State private var onState: [String: Bool] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsMidRoundConfirm = false
    /// The slice-57/58 settings editor open on top of this sheet.
    @State private var configKind: SideGameConfigKind?

    private var editable: Bool { picker?.editable == true }

    /// Turning a game on mid-round back-fills every hole already
    /// logged — that's the caption, and the reason for the confirm.
    private var isUnderway: Bool { detail.status == .inProgress }

    /// Games with a native settings editor (slice 57/58).
    private var configKeys: Set<String> { ["STABLEFORD", "BBB", "SNAKE", "NASSAU"] }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let loadFailed {
                loadErrorView(loadFailed)
            } else if let picker {
                ScrollView {
                    VStack(spacing: 0) {
                        rowsView(picker)
                    }
                    .background(Color.sticksCard)
                    .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                            .stroke(Color.sticksHairline, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Text("Sticks only keeps score — no money is collected, held, or paid through the app. Anything owed is sorted out between you.")
                        .font(SticksFont.mono(10))
                        .kerning(0.3)
                        .foregroundStyle(Color.sticksFaint)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                }

                if editable {
                    footer
                }
            } else {
                VStack {
                    ProgressView()
                        .tint(Color.sticksMuted)
                        .padding(.top, 60)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $configKind) { kind in
            // Slice 57/58 house-rule editors, opened from a game's row.
            switch kind {
            case .stableford:
                StablefordConfigView(viewModel: viewModel, session: session)
            case .bbb:
                BbbConfigView(viewModel: viewModel, session: session)
            case .snake:
                SnakeConfigView(viewModel: viewModel, session: session)
            case .nassau:
                NassauConfigView(viewModel: viewModel, session: session)
            }
        }
        .alert("Change side games on a live round?", isPresented: $showsMidRoundConfirm) {
            Button("Save side games") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every game's board recomputes from the strokes already logged — turning one on back-fills all of them.")
        }
        .task { await reload() }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Side games")
                .font(SticksFont.display(26, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            if let picker, !picker.editable, let reason = picker.reason {
                // Read-only — non-creator or a final round. The server's
                // reason is the explanation ("This round is final.").
                Text(reason)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
            } else if isUnderway {
                Text("Round's underway. You can add or remove side games here — scores recompute from the strokes already logged.")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
            } else {
                Text("Pick what this round plays. Standings and per-game boards build from the scores.")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func rowsView(_ picker: SideGamesPicker) -> some View {
        ForEach(Array(picker.games.enumerated()), id: \.element.kind) { position, game in
            if position > 0 {
                Rectangle()
                    .fill(Color.sticksHairline.opacity(0.6))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
            gameRow(game)
        }
    }

    private func gameRow(_ game: SideGameOption) -> some View {
        let isOn = Binding<Bool>(
            get: { onState[game.kind] ?? game.on },
            set: { isOn in
                onState[game.kind] = isOn
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
        let disabled = !editable || game.locked || !game.eligible

        return VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(game.label)
                            .font(SticksFont.sans(15, weight: .semibold))
                            .foregroundStyle(disabled ? Color.sticksMuted : Color.sticksInk)
                        if game.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.sticksFaint)
                        }
                    }

                    Text(game.blurb)
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                        .opacity(disabled ? 0.7 : 1)

                    if !game.eligible, let reason = game.ineligibleReason {
                        Text(reason)
                            .font(SticksFont.sans(11.5))
                            .foregroundStyle(Color.sticksError)
                            .padding(.top, 2)
                    }
                }
            }
            .tint(Color.sticksGreen)
            .disabled(disabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if onState[game.kind] ?? game.on {
                underRow(game)
            }
        }
        .padding(.vertical, 2)
    }

    /// What shows beneath a game that's on: its settings entry, when
    /// one exists and can be used.
    @ViewBuilder
    private func underRow(_ game: SideGameOption) -> some View {
        let hasEditor = configKeys.contains(game.kind)
        if hasEditor {
            Button {
                configKind = SideGameConfigKind(rawValue: game.kind)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Game settings")
                        .font(SticksFont.mono(11))
                        .kerning(0.4)
                }
                .foregroundStyle(Color.sticksGreen)
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .opacity(editable ? 1 : 0.5)
            .padding(.leading, 28)
            .padding(.bottom, 10)
        }
    }

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksMuted)
                .multilineTextAlignment(.center)

            Button {
                loadFailed = nil
                Task { await reload() }
            } label: {
                Text("TRY AGAIN")
                    .font(SticksFont.mono(12))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksGreen)
            }
            .buttonStyle(PressableButtonStyle())

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
                // The user's rule: a live round confirms before it
                // re-counts. Upcoming rounds save straight through.
                if isUnderway {
                    showsMidRoundConfirm = true
                } else {
                    save()
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text("Save side games")
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

    /// GETs the picker and rebuilds the local on/off state from it.
    private func reload() async {
        do {
            let fresh = try await viewModel.sideGamesPicker(session: session)
            picker = fresh
            var state: [String: Bool] = [:]
            for game in fresh.games {
                state[game.kind] = game.on
            }
            onState = state
        } catch let error as APIError {
            loadFailed = error.message
        } catch {
            loadFailed = "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// POSTs the FULL desired set (locked-on games ride along), then
    /// reconciles against the response's kinds — the server legitimately
    /// drops games this round can't play. Quiet-refreshes the detail
    /// behind the sheet so standings move as soon as it dismisses.
    private func save() {
        guard !isSaving, let picker else { return }
        var kinds = picker.games.map(\.kind).filter { onState[$0] ?? false }
        for game in picker.games where game.locked && game.on && !kinds.contains(game.kind) {
            kinds.append(game.kind)
        }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                let finalKinds = try await viewModel.setSideGamesReturning(kinds: kinds, session: session)
                var state: [String: Bool] = [:]
                for game in picker.games {
                    state[game.kind] = finalKinds.contains(game.kind)
                }
                onState = state
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
