//
//  CreateTournamentView.swift
//  Sticks
//
//  Slice 55: the "new tournament" sheet — name, Net/Gross scoring,
//  a 1–12 rounds stepper, optional start date and notes. POSTs
//  /tournaments and hands the new id back so the caller can push the
//  detail (where the invite code sits front and center).
//

import SwiftUI
import UIKit

struct CreateTournamentView: View {
    let viewModel: TournamentsViewModel
    let session: SessionStore
    /// Called with the new tournament's id after a successful POST.
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scoringMode = "NET"
    @State private var roundsPlanned = 3
    @State private var hasStartDate = false
    @State private var startDate: Date = .now
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isCreating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        eyebrow("THE FIELD IS FORMING")

                        nameSection
                        scoringSection
                        roundsSection
                        startDateSection
                        notesSection

                        if let error = viewModel.createError {
                            Text(error)
                                .font(SticksFont.sans(13))
                                .foregroundStyle(Color.sticksError)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
            .toolbarBackground(Color.sticksBg, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { createBar }
            .tint(Color.sticksGreen)
            .onAppear { isNameFocused = true }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10.5))
            .kerning(1.47)
            .foregroundStyle(Color.sticksGreen)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME")

            TextField(
                "",
                text: $name,
                prompt: Text("Club championship, Ryder week…")
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksFaint)
            )
            .font(SticksFont.sans(15))
            .foregroundStyle(Color.sticksInk)
            .focused($isNameFocused)
            .submitLabel(.done)
            .onChange(of: name) { _, _ in
                if viewModel.createError != nil { viewModel.clearCreateError() }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isNameFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private var scoringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SCORING")

            HStack(spacing: 8) {
                scoringChip("NET", caption: "Handicaps applied")
                scoringChip("GROSS", caption: "Raw strokes")
            }
        }
    }

    private func scoringChip(_ mode: String, caption: String) -> some View {
        let isSelected = scoringMode == mode
        return Button {
            scoringMode = mode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode)
                    .font(SticksFont.mono(13))
                    .kerning(1.2)
                    .foregroundStyle(isSelected ? Color.sticksCream : Color.sticksInk)
                Text(caption)
                    .font(SticksFont.sans(11.5))
                    .foregroundStyle(isSelected ? Color.sticksCream.opacity(0.75) : Color.sticksMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(isSelected ? Color.sticksGreen : Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var roundsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("ROUNDS PLANNED")

            HStack(spacing: 14) {
                stepperButton(symbol: "minus", enabled: roundsPlanned > 1) {
                    roundsPlanned = max(1, roundsPlanned - 1)
                }

                Text("\(roundsPlanned)")
                    .font(SticksFont.display(26))
                    .foregroundStyle(Color.sticksInk)
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: roundsPlanned)

                stepperButton(symbol: "plus", enabled: roundsPlanned < 12) {
                    roundsPlanned = min(12, roundsPlanned + 1)
                }

                Spacer()

                Text(roundsPlanned == 1 ? "ONE-DAY EVENT" : "\(roundsPlanned)-ROUND TOTAL")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func stepperButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Color.sticksGreen : Color.sticksFaint)
                .frame(width: 44, height: 44)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var startDateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("START DATE · OPTIONAL")

            VStack(spacing: 0) {
                Toggle(isOn: $hasStartDate.animation(.snappy(duration: 0.22))) {
                    Text("Set a start date")
                        .font(SticksFont.sans(14.5))
                        .foregroundStyle(Color.sticksInk)
                }
                .tint(Color.sticksGreen)
                .padding(.horizontal, 14)
                .frame(height: 50)

                if hasStartDate {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)

                    DatePicker(
                        "First tee",
                        selection: $startDate,
                        displayedComponents: [.date]
                    )
                    .font(SticksFont.sans(14.5))
                    .foregroundStyle(Color.sticksInk)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                }
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES · OPTIONAL")

            TextField(
                "",
                text: $notes,
                prompt: Text("Format quirks, stakes, tee assignments…")
                    .font(SticksFont.sans(14.5))
                    .foregroundStyle(Color.sticksFaint),
                axis: .vertical
            )
            .font(SticksFont.sans(14.5))
            .foregroundStyle(Color.sticksInk)
            .lineLimit(3 ... 5)
            .padding(14)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10))
            .kerning(1.2)
            .foregroundStyle(Color.sticksFaint)
    }

    // MARK: - Create bar

    private var createBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)

            Button {
                create()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isCreating {
                        ProgressView()
                            .tint(Color.sticksCream)
                            .scaleEffect(0.85)
                    }
                    Text(viewModel.isCreating ? "CREATING…" : "CREATE TOURNAMENT")
                        .font(SticksFont.sans(15, weight: .bold))
                        .kerning(0.4)
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 13))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canCreate)
            .opacity(canCreate ? 1 : 0.55)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.sticksBg)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            let id = await viewModel.create(
                name: trimmed,
                scoringMode: scoringMode,
                roundsPlanned: roundsPlanned,
                scheduledStartAt: hasStartDate ? startDate : nil,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                session: session
            )
            if let id {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCreated(id)
            }
        }
    }
}
