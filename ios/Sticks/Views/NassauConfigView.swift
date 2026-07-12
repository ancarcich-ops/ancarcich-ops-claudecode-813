//
//  NassauConfigView.swift
//  Sticks
//
//  Slice 58: settings editor for Nassau — auto-press (a new press bet
//  spawns whenever a side falls N holes down inside the front or back
//  match) and the dollar stake per bet (front, back, total and each
//  press are each a bet), saved via POST /side-game-config then a
//  quiet refetch so the boards redraw (a new press line can appear,
//  money updates). Creator-only (the endpoint enforces 403);
//  read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct NassauConfigView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var autoPress: Bool
    @State private var threshold: Int
    @State private var stakeText: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var stakeFocused: Bool

    init(viewModel: MatchDetailViewModel, session: SessionStore) {
        self.viewModel = viewModel
        self.session = session
        let config = NassauConfig.decode(from: viewModel.response?.sideGameConfigs["NASSAU"])
        let stake = config?.stake ?? 0
        _autoPress = State(initialValue: config?.autoPress == true)
        _threshold = State(initialValue: max(config?.autoPressThreshold ?? 2, 1))
        _stakeText = State(initialValue: stake > 0 ? Self.formatStake(stake) : "")
    }

    /// "20" for whole dollars, "20.50" otherwise.
    private static func formatStake(_ stake: Double) -> String {
        stake == stake.rounded() ? String(Int(stake)) : String(format: "%.2f", stake)
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
                    autoPressCard
                    stakeCard
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
                Text("Nassau")
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
            return "Only the round's creator can change Nassau settings."
        }
        return "Front, back & total bets. Presses apply to 2-player rounds."
    }

    // MARK: - Cards

    private var autoPressCard: some View {
        settingCard(
            label: "AUTO-PRESS",
            hint: "A new press bet starts whenever a side falls behind inside the front or back match."
        ) {
            VStack(spacing: 0) {
                Toggle(isOn: $autoPress.animation(.easeOut(duration: 0.15))) {
                    Text("Auto-press when a side goes \(threshold) down")
                        .font(SticksFont.sans(14, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                }
                .tint(Color.sticksGreen)
                .disabled(isReadOnly || isSaving)
                .onChange(of: autoPress) { _, _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }

                if autoPress {
                    Rectangle()
                        .fill(Color.sticksHairline.opacity(0.6))
                        .frame(height: 1)
                        .padding(.vertical, 10)

                    thresholdRow
                }
            }
        }
    }

    private var thresholdRow: some View {
        HStack(spacing: 12) {
            Text("Press when down")
                .font(SticksFont.sans(14, weight: .semibold))
                .foregroundStyle(Color.sticksInk)

            Spacer(minLength: 8)

            stepButton(system: "minus") {
                threshold = max(threshold - 1, 1)
            }
            .disabled(isReadOnly || isSaving || threshold <= 1)

            Text("\(threshold)")
                .font(SticksFont.display(17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)
                .frame(width: 42)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: threshold)

            stepButton(system: "plus") {
                threshold = min(threshold + 1, 9)
            }
            .disabled(isReadOnly || isSaving || threshold >= 9)

            Text(threshold == 1 ? "hole" : "holes")
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksMuted)
                .frame(width: 40, alignment: .leading)
        }
    }

    private func stepButton(system: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sticksGreen)
                .frame(width: 40, height: 32)
                .background(Color.sticksGreen.opacity(0.1))
                .clipShape(.rect(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.sticksGreen.opacity(0.3), lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var stakeCard: some View {
        settingCard(
            label: "STAKE PER BET ($)",
            hint: "Front, back, total and each press are each a bet. Leave blank or 0 for no money."
        ) {
            HStack(spacing: 8) {
                Text("$")
                    .font(SticksFont.display(16, weight: .bold))
                    .foregroundStyle(Color.sticksMuted)

                TextField("0", text: $stakeText)
                    .font(SticksFont.display(16, weight: .bold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .focused($stakeFocused)
                    .disabled(isReadOnly || isSaving)
                    .onChange(of: stakeText) { _, newValue in
                        stakeText = Self.sanitizeStake(newValue)
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

    /// Digits plus at most one decimal point with two decimals,
    /// capped at 5 whole-dollar digits.
    private static func sanitizeStake(_ text: String) -> String {
        var seenDot = false
        var filtered = ""
        for character in text {
            if character.isNumber {
                filtered.append(character)
            } else if (character == "." || character == ",") && !seenDot {
                seenDot = true
                filtered.append(".")
            }
        }
        let parts = filtered.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String((parts.first ?? "").prefix(5))
        if parts.count > 1 {
            return whole + "." + String(parts[1].prefix(2))
        }
        return whole
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
                Text("Save Nassau settings")
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

    /// Auto-press on posts `{ autoPress: true, autoPressThreshold, stake? }`;
    /// off posts just the stake — a true empty `{}` when stake is also 0.
    private func save() {
        guard !isSaving, !isReadOnly else { return }
        stakeFocused = false
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let stake = max(Double(stakeText) ?? 0, 0)
        let config = NassauConfig(
            autoPress: autoPress ? true : nil,
            autoPressThreshold: autoPress ? max(threshold, 1) : nil,
            stake: stake > 0 ? stake : nil
        )
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGameConfig(kind: "NASSAU", config: config, session: session)
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
