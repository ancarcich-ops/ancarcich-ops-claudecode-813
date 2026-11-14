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
//  Game settings: Stableford/BBB/Snake/Nassau open the slice-57/58
//  native editors as a nested sheet. Every other game renders its
//  served `settings` schema inline (choice/boolean/number/money,
//  `dependsOn` honoured, `settingsComplete: false` → "set this up on
//  the web") and posts drafts through side-game-config on save — the
//  app never guesses a field name, and a non-empty `dropped` response
//  surfaces as an error rather than a setting that silently no-ops.
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
    /// Local settings drafts keyed kind → setting key → value, seeded
    /// from the GET (stored config, falling back to each setting's
    /// default) and posted through side-game-config on save.
    @State private var drafts: [String: [String: SideGameConfigValue]] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsMidRoundConfirm = false
    /// The slice-57/58 settings editor open on top of this sheet.
    @State private var configKind: SideGameConfigKind?

    private var editable: Bool { picker?.editable == true }

    /// Turning a game on mid-round back-fills every hole already
    /// logged — that's the caption, and the reason for the confirm.
    private var isUnderway: Bool { detail.status == .inProgress }

    /// Games with a native settings editor (slices 57/58 and the
    /// Wolf/Targets editors live on the round screen). Every other game
    /// renders its served `settings` inline.
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
    /// one exists and can be used. Controls render from the served
    /// `settings` schema — never a guessed field name.
    @ViewBuilder
    private func underRow(_ game: SideGameOption) -> some View {
        if configKeys.contains(game.kind) {
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
        } else if !editable || game.settings.isEmpty {
            // Read-only viewers see the game as-is, no controls.
        } else if !game.settingsComplete {
            Text("Set this up on the web — this game needs more than a quick form.")
                .font(SticksFont.sans(11.5))
                .foregroundStyle(Color.sticksMuted)
                .padding(.leading, 28)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(game.settings) { setting in
                    settingControl(game, setting)
                }
            }
            .padding(.leading, 28)
            .padding(.trailing, 14)
            .padding(.bottom, 10)
        }
    }

    /// One served settings field under its game's row. A number or
    /// money field can depend on a boolean sibling — hidden while that
    /// sibling is off, since it can't mean anything yet.
    @ViewBuilder
    private func settingControl(_ game: SideGameOption, _ setting: SideGameSetting) -> some View {
        if setting.dependsOn != nil, drafts[game.kind]?[setting.dependsOn ?? ""]?.boolValue != true {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                Text(setting.label)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
                Spacer(minLength: 8)

                switch setting.type {
                case "boolean":
                    Toggle("", isOn: flagBinding(game, setting))
                        .tint(Color.sticksGreen)
                        .labelsHidden()
                        .scaleEffect(0.82, anchor: .trailing)
                case "choice":
                    choiceMenu(game, setting)
                case "number", "money":
                    HStack(spacing: 5) {
                        if setting.type == "money" {
                            Text("$")
                                .font(SticksFont.mono(12))
                                .foregroundStyle(Color.sticksMuted)
                        }
                        TextField("0", value: numberBinding(game, setting), format: .number)
                            .font(SticksFont.mono(12.5))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 56)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(Color.sticksBg)
                            .clipShape(.rect(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color.sticksHairline, lineWidth: 1)
                            )
                    }
                default:
                    // A type this build doesn't know — render nothing
                    // rather than a control that guesses.
                    EmptyView()
                }
            }
        }
    }

    /// Choice fields pick from the served options in a menu — the same
    /// pattern as the scoring sheet's group picker. The selected
    /// option's label shows; its blurb, if any, is the checkmark row's
    /// subtitle the menu reveals on tap.
    private func choiceMenu(_ game: SideGameOption, _ setting: SideGameSetting) -> some View {
        let choices = setting.choices ?? []
        let current = drafts[game.kind]?[setting.key]
        let selectedLabel = choices.first(where: { $0.value == current })?.label
            ?? choices.first(where: { $0.value == setting.defaultValue })?.label
            ?? "—"
        return Menu {
            ForEach(Array(choices.enumerated()), id: \.element.label) { _, choice in
                Button {
                    drafts[game.kind]?[setting.key] = choice.value
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    let text = choice.blurb.map { "\(choice.label) — \($0)" } ?? choice.label
                    if choice.value == current {
                        Label(text, systemImage: "checkmark")
                    } else {
                        Text(text)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .font(SticksFont.sans(12.5, weight: .medium))
                    .foregroundStyle(Color.sticksInk)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.sticksMuted)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(Color.sticksBg)
            .clipShape(.rect(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func flagBinding(_ game: SideGameOption, _ setting: SideGameSetting) -> Binding<Bool> {
        Binding(
            get: { drafts[game.kind]?[setting.key]?.boolValue ?? setting.defaultValue?.boolValue ?? false },
            set: { drafts[game.kind]?[setting.key] = .flag($0) }
        )
    }

    private func numberBinding(_ game: SideGameOption, _ setting: SideGameSetting) -> Binding<Double> {
        Binding(
            get: { drafts[game.kind]?[setting.key]?.numberValue ?? setting.defaultValue?.numberValue ?? 0 },
            set: { drafts[game.kind]?[setting.key] = .number($0) }
        )
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

    /// GETs the picker and rebuilds the local on/off and settings-draft
    /// state from it.
    private func reload() async {
        do {
            let fresh = try await viewModel.sideGamesPicker(session: session)
            picker = fresh
            var state: [String: Bool] = [:]
            var freshDrafts: [String: [String: SideGameConfigValue]] = [:]
            for game in fresh.games {
                state[game.kind] = game.on
                var draft: [String: SideGameConfigValue] = [:]
                for setting in game.settings {
                    draft[setting.key] = game.config?[setting.key] ?? setting.defaultValue
                }
                freshDrafts[game.kind] = draft
            }
            onState = state
            drafts = freshDrafts
        } catch let error as APIError {
            loadFailed = error.message
        } catch {
            loadFailed = "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// POSTs the FULL desired set (locked-on games ride along), then
    /// reconciles against the response's kinds — the server legitimately
    /// drops games this round can't play. Settings drafts that drifted
    /// from what's stored go up afterwards, one side-game-config POST
    /// per game that's still on. Quiet-refreshes the detail behind the
    /// sheet so standings move as soon as it dismisses.
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

                // Settings ride after the kinds replacement — a game
                // that just came on gets its draft applied too.
                for game in picker.games where state[game.kind] == true && !game.settings.isEmpty {
                    guard var draft = drafts[game.kind] else { continue }
                    let stored = game.config ?? [:]
                    // Drop untouched fields so a server default change
                    // isn't frozen in by an old draft.
                    draft = draft.filter { key, value in
                        game.settings.first(where: { $0.key == key }) != nil && value != stored[key]
                    }
                    guard !draft.isEmpty else { continue }
                    try await viewModel.setSideGameConfig(
                        kind: game.kind,
                        config: draft,
                        session: session
                    )
                }

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
