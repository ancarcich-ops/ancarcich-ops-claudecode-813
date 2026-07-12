//
//  BbbConfigView.swift
//  Sticks
//
//  Slice 57: settings editor for Bingo Bango Bongo — the points each
//  award is worth (default 1/1/1), saved via POST /side-game-config
//  then a quiet refetch so the leaderboard reweights. Creator-only
//  (the endpoint enforces 403); read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct BbbConfigView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var bingo: Int
    @State private var bango: Int
    @State private var bongo: Int
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(viewModel: MatchDetailViewModel, session: SessionStore) {
        self.viewModel = viewModel
        self.session = session
        let saved = BbbConfig.decode(from: viewModel.response?.sideGameConfigs["BBB"])?.points ?? .deflt
        _bingo = State(initialValue: max(saved.bingo, 0))
        _bango = State(initialValue: max(saved.bango, 0))
        _bongo = State(initialValue: max(saved.bongo, 0))
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
                    pointsCard
                    if !isReadOnly {
                        saveButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                Text("Bingo Bango Bongo")
                    .font(SticksFont.display(26, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

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
            return "Only the round's creator can change BBB settings."
        }
        return "First on the green, closest once on, first in the hole. Default 1 each."
    }

    // MARK: - Cards

    private var pointsCard: some View {
        settingCard(label: "POINTS PER AWARD", hint: "How much each award is worth on the leaderboard.") {
            VStack(spacing: 0) {
                pointRow(label: "Bingo", subtitle: "First on the green", value: $bingo)
                Rectangle()
                    .fill(Color.sticksHairline.opacity(0.6))
                    .frame(height: 1)
                pointRow(label: "Bango", subtitle: "Closest once all are on", value: $bango)
                Rectangle()
                    .fill(Color.sticksHairline.opacity(0.6))
                    .frame(height: 1)
                pointRow(label: "Bongo", subtitle: "First in the hole", value: $bongo)
            }
        }
    }

    private func pointRow(label: String, subtitle: String, value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                Text(subtitle)
                    .font(SticksFont.sans(11.5))
                    .foregroundStyle(Color.sticksMuted)
            }

            Spacer(minLength: 8)

            stepButton(system: "minus") {
                value.wrappedValue = max(value.wrappedValue - 1, 0)
            }
            .disabled(isReadOnly || isSaving || value.wrappedValue <= 0)

            Text("\(value.wrappedValue)")
                .font(SticksFont.display(17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)
                .frame(width: 36)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: value.wrappedValue)

            stepButton(system: "plus") {
                value.wrappedValue = min(value.wrappedValue + 1, 20)
            }
            .disabled(isReadOnly || isSaving || value.wrappedValue >= 20)
        }
        .padding(.vertical, 8)
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
                Text("Save BBB settings")
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
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let config = BbbConfig(points: BbbPoints(bingo: bingo, bango: bango, bongo: bongo))
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGameConfig(kind: "BBB", config: config, session: session)
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
