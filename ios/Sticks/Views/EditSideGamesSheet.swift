//
//  EditSideGamesSheet.swift
//  Sticks
//
//  Slice 29: creator-only side-game add/remove — toggles for the
//  selectable kinds, pre-checked from the match's current side games.
//  Save posts the FULL desired set. NASSAU is 18-hole only; an existing
//  TEAM_VS_TEAM shows as a read-only row (teams are edited on the web)
//  and is preserved in the sent set.
//

import SwiftUI
import UIKit

struct EditSideGamesSheet: View {
    let detail: MatchDetail
    let currentKinds: [String]
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Selectable kinds in display order with short blurbs.
    private static let options: [(kind: String, label: String, blurb: String)] = [
        ("SKINS", "Skins", "Win a hole outright to take the skin — ties carry over"),
        ("STABLEFORD", "Stableford", "Points per hole against par"),
        ("NASSAU", "Nassau", "Front nine, back nine, and overall"),
        ("WOLF", "Wolf", "Rotating captain picks a partner — or goes lone wolf"),
        ("BINGO_BANGO_BONGO", "Bingo Bango Bongo", "First on, closest to the pin, first in"),
        ("SNAKE", "Snake", "Last three-putt holds the snake"),
        ("SIXES", "Sixes", "Partners rotate every six holes"),
    ]

    init(detail: MatchDetail, currentKinds: [String], viewModel: MatchDetailViewModel, session: SessionStore) {
        self.detail = detail
        self.currentKinds = currentKinds
        self.viewModel = viewModel
        self.session = session
        let selectable = Set(Self.options.map(\.kind))
        _selected = State(initialValue: Set(currentKinds.map { $0.uppercased() }).intersection(selectable))
    }

    /// TEAM_VS_TEAM can't be rebuilt on mobile — shown read-only and
    /// preserved in the sent set when already enabled.
    private var hasTeams: Bool {
        currentKinds.contains { $0.uppercased() == "TEAM_VS_TEAM" }
    }

    /// NASSAU needs a full 18 — the server drops it otherwise, so
    /// don't offer it on shorter rounds.
    private var visibleOptions: [(kind: String, label: String, blurb: String)] {
        Self.options.filter { $0.kind != "NASSAU" || detail.holes == 18 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(visibleOptions.enumerated()), id: \.element.kind) { position, option in
                        if position > 0 {
                            Rectangle()
                                .fill(Color.sticksHairline.opacity(0.6))
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                        toggleRow(option)
                    }

                    if hasTeams {
                        Rectangle()
                            .fill(Color.sticksHairline.opacity(0.6))
                            .frame(height: 1)
                            .padding(.leading, 14)
                        teamsRow
                    }
                }
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Text("Fine-tune stakes & rotation on the website.")
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
            }

            footer
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Edit side games")
                .font(SticksFont.display(26, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            Text("Standings and per-game boards recompute from the scores already in.")
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func toggleRow(_ option: (kind: String, label: String, blurb: String)) -> some View {
        Toggle(isOn: binding(for: option.kind)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)

                Text(option.blurb)
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
            }
        }
        .tint(Color.sticksGreen)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Read-only teams row — present but not toggleable.
    private var teamsRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Teams (edit on web)")
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksMuted)

                Text("Team assignments can't be rebuilt on mobile — it stays on.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksFaint)
            }

            Spacer(minLength: 8)

            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sticksFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func binding(for kind: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(kind) },
            set: { isOn in
                if isOn {
                    selected.insert(kind)
                } else {
                    selected.remove(kind)
                }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        )
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
                save()
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

    /// POST /matches/:id/side-games with the FULL desired set (in display
    /// order, plus a preserved TEAM_VS_TEAM), then quiet refresh → dismiss.
    private func save() {
        guard !isSaving else { return }
        var kinds = Self.options.map(\.kind).filter { selected.contains($0) }
        if hasTeams {
            kinds.append("TEAM_VS_TEAM")
        }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGames(kinds: kinds, session: session)
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
