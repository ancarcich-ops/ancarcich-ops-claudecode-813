//
//  StablefordConfigView.swift
//  Sticks
//
//  Slice 57: settings editor for the Stableford scale. Standard (WHS)
//  or a Modified points table — six values, negatives allowed — saved
//  via POST /side-game-config then a quiet refetch so the standings
//  points recompute. Creator-only (the endpoint enforces 403);
//  read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct StablefordConfigView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var isModified: Bool
    @State private var points: StablefordPoints
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(viewModel: MatchDetailViewModel, session: SessionStore) {
        self.viewModel = viewModel
        self.session = session
        let config = StablefordConfig.decode(from: viewModel.response?.sideGameConfigs["STABLEFORD"])
        _isModified = State(initialValue: config?.points != nil)
        _points = State(initialValue: config?.points ?? .modified)
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
                    scaleCard
                    if isModified {
                        pointsCard
                    }
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
                Text("Stableford")
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
            return "Only the round's creator can change Stableford settings."
        }
        return isModified
            ? "Points per result vs par; negatives allowed."
            : "WHS: birdie 3, par 2, bogey 1, double+ 0."
    }

    // MARK: - Cards

    private var scaleCard: some View {
        settingCard(label: "SCALE", hint: "How results convert to points.") {
            HStack(spacing: 6) {
                scaleChip(label: "Standard (WHS)", modified: false)
                scaleChip(label: "Modified", modified: true)
            }
        }
    }

    private func scaleChip(label: String, modified: Bool) -> some View {
        let isOn = isModified == modified
        return Button {
            guard isModified != modified else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeOut(duration: 0.15)) {
                isModified = modified
            }
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

    /// The six editable point rows — label, keypath into the table.
    private var pointRows: [(String, WritableKeyPath<StablefordPoints, Int>)] {
        [
            ("Albatross+", \.albatross),
            ("Eagle", \.eagle),
            ("Birdie", \.birdie),
            ("Par", \.par),
            ("Bogey", \.bogey),
            ("Dbl bogey+", \.double),
        ]
    }

    private var pointsCard: some View {
        settingCard(label: "POINTS", hint: "Points per result vs par; negatives allowed.") {
            VStack(spacing: 0) {
                ForEach(Array(pointRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline.opacity(0.6))
                            .frame(height: 1)
                    }
                    pointRow(label: row.0, keyPath: row.1)
                }
            }
        }
    }

    private func pointRow(label: String, keyPath: WritableKeyPath<StablefordPoints, Int>) -> some View {
        let value = points[keyPath: keyPath]
        return HStack(spacing: 12) {
            Text(label)
                .font(SticksFont.sans(14, weight: .semibold))
                .foregroundStyle(Color.sticksInk)

            Spacer(minLength: 8)

            stepButton(system: "minus") {
                points[keyPath: keyPath] = max(value - 1, -10)
            }
            .disabled(isReadOnly || isSaving || value <= -10)

            Text("\(value)")
                .font(SticksFont.display(17, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(value < 0 ? Color.sticksError : Color.sticksInk)
                .frame(width: 42)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: value)

            stepButton(system: "plus") {
                points[keyPath: keyPath] = min(value + 1, 20)
            }
            .disabled(isReadOnly || isSaving || value >= 20)
        }
        .padding(.vertical, 7)
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
                Text("Save Stableford settings")
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

    /// Standard posts an empty config `{}` (default WHS scale);
    /// Modified posts the full points table.
    private func save() {
        guard !isSaving, !isReadOnly else { return }
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let config = StablefordConfig(points: isModified ? points : nil)
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setSideGameConfig(kind: "STABLEFORD", config: config, session: session)
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
