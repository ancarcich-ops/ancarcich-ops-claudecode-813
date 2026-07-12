//
//  TargetsConfigView.swift
//  Sticks
//
//  Slice 53: settings editor for Targets — the config-only side game
//  derived from scores. Stat (par/birdie or better), target count and
//  an optional ante, saved via POST /side-game-config then a quiet
//  refetch so the leaderboard's progress-vs-target updates. Creator-only
//  (the endpoint enforces 403); read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct TargetsConfigView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var stat: String
    @State private var target: Int
    @State private var anteText: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var anteFocused: Bool

    init(viewModel: MatchDetailViewModel, session: SessionStore) {
        self.viewModel = viewModel
        self.session = session
        let config = TargetsConfig.decode(from: viewModel.response?.sideGameConfigs["TARGETS"])
        let holes = viewModel.detail?.holes ?? 18
        _stat = State(initialValue: config?.stat ?? TargetsConfig.parOrBetter)
        _target = State(initialValue: min(max(config?.target ?? min(9, holes), 1), holes))
        let ante = config?.ante ?? 0
        _anteText = State(initialValue: ante > 0 ? String(ante) : "")
    }

    private var holes: Int {
        viewModel.detail?.holes ?? 18
    }

    private var isReadOnly: Bool {
        viewModel.detail?.status == .completed || viewModel.detail?.isCreator != true
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let errorMessage {
                Text(errorMessage)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 12) {
                    statCard
                    targetCard
                    anteCard
                    if !isReadOnly {
                        saveButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                Text("Targets")
                    .font(SticksFont.display(26, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer(minLength: 8)

                Button {
                    dismiss()
                } label: {
                    Text("DONE")
                        .font(SticksFont.mono(11))
                        .kerning(1)
                        .foregroundStyle(Color.sticksGreen)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Color.sticksGreen.opacity(0.1))
                        .clipShape(.capsule)
                        .overlay(
                            Capsule().stroke(Color.sticksGreen.opacity(0.3), lineWidth: 1)
                        )
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }

            Text(helperText)
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var helperText: String {
        if viewModel.detail?.status == .completed {
            return "Round is final — settings are read-only."
        }
        if viewModel.detail?.isCreator != true {
            return "Only the round's creator can change Targets settings."
        }
        return "Pick the stat to chase and how many holes to hit it — progress comes straight from the scorecard."
    }

    // MARK: - Cards

    private var statCard: some View {
        settingCard(label: "STAT", hint: "What counts as hitting the target on a hole.") {
            HStack(spacing: 6) {
                statChip(label: "Par or better", value: TargetsConfig.parOrBetter)
                statChip(label: "Birdie or better", value: TargetsConfig.birdieOrBetter)
            }
        }
    }

    private func statChip(label: String, value: String) -> some View {
        let isOn = stat == value
        return Button {
            guard stat != value else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            stat = value
        } label: {
            Text(label)
                .font(SticksFont.sans(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.sticksCream : Color.sticksInk)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isOn ? Color.sticksGreen : Color.sticksPanel2)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(isOn ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isReadOnly || isSaving)
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var targetCard: some View {
        settingCard(label: "TARGET", hint: "How many holes you need to hit the stat.") {
            HStack(spacing: 12) {
                stepButton(system: "minus") {
                    guard target > 1 else { return }
                    target -= 1
                }
                .disabled(isReadOnly || isSaving || target <= 1)

                Text("\(target) OF \(holes)")
                    .font(SticksFont.display(20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: target)

                stepButton(system: "plus") {
                    guard target < holes else { return }
                    target += 1
                }
                .disabled(isReadOnly || isSaving || target >= holes)
            }
        }
    }

    private func stepButton(system: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.sticksGreen)
                .frame(width: 44, height: 36)
                .background(Color.sticksGreen.opacity(0.1))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.sticksGreen.opacity(0.3), lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var anteCard: some View {
        settingCard(label: "ANTE", hint: "Optional — dollars on the line. Leave blank for none.") {
            HStack(spacing: 8) {
                Text("$")
                    .font(SticksFont.display(16, weight: .bold))
                    .foregroundStyle(Color.sticksMuted)

                TextField("0", text: $anteText)
                    .font(SticksFont.display(16, weight: .bold))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .focused($anteFocused)
                    .disabled(isReadOnly || isSaving)
                    .onChange(of: anteText) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue { anteText = digits }
                        if digits.count > 5 { anteText = String(digits.prefix(5)) }
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func settingCard(label: String, hint: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)
                Text(hint)
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Color.sticksCream)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
                Text("Save Targets settings")
                    .font(SticksFont.sans(15, weight: .semibold))
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.sticksGreen)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSaving)
        .padding(.top, 4)
    }

    // MARK: - Behavior

    private func save() {
        guard !isSaving, !isReadOnly else { return }
        anteFocused = false
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let config = TargetsConfig(stat: stat, target: target, ante: Int(anteText) ?? 0)
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGameConfig(kind: "TARGETS", config: config, session: session)
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
