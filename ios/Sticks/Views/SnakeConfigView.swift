//
//  SnakeConfigView.swift
//  Sticks
//
//  Slice 57: settings editor for Snake — the dollar stake on the
//  snake (0/blank = no money) and whether the pot doubles each time
//  the snake is passed, saved via POST /side-game-config then a quiet
//  refetch so the holder's pot updates. Creator-only (the endpoint
//  enforces 403); read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct SnakeConfigView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var stakeText: String
    @State private var doubling: Bool
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var stakeFocused: Bool

    init(viewModel: MatchDetailViewModel, session: SessionStore) {
        self.viewModel = viewModel
        self.session = session
        let config = SnakeConfig.decode(from: viewModel.response?.sideGameConfigs["SNAKE"])
        let stake = config?.stake ?? 0
        _stakeText = State(initialValue: stake > 0 ? Self.formatStake(stake) : "")
        _doubling = State(initialValue: config?.doubling == true)
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
                    stakeCard
                    doublingCard
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
                Text("Snake")
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
            return "Only the round's creator can change Snake settings."
        }
        return "Last player to 3-putt holds the snake and owes the pot."
    }

    // MARK: - Cards

    private var stakeCard: some View {
        settingCard(label: "SNAKE STAKE ($)", hint: "Dollars on the snake. Leave blank or 0 for no money.") {
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

    private var doublingCard: some View {
        settingCard(label: "DOUBLING", hint: "The pot doubles every time the snake changes hands.") {
            Toggle(isOn: $doubling) {
                Text("Double the pot each pass")
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
            }
            .tint(Color.sticksGreen)
            .disabled(isReadOnly || isSaving)
            .onChange(of: doubling) { _, _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
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
                Text("Save Snake settings")
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

    /// Posts `{ stake, doubling }` — doubling omitted when off; a 0
    /// stake clears the money.
    private func save() {
        guard !isSaving, !isReadOnly else { return }
        stakeFocused = false
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let stake = max(Double(stakeText) ?? 0, 0)
        let config = SnakeConfig(stake: stake, doubling: doubling ? true : nil)
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGameConfig(kind: "SNAKE", config: config, session: session)
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
