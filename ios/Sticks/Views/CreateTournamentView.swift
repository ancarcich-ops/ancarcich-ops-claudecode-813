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
    // Gross by default, matching the round creator — Net stays one tap
    // away for groups that play with handicaps.
    @State private var scoringMode = "GROSS"
    @State private var roundsPlanned = 3
    @State private var hasStartDate = false
    @State private var startDate: Date = .now
    @State private var notes = ""
    /// Slice 84: side size + format, chosen from the server's registry.
    @State private var selectedSize = 2
    @State private var selectedFormatID: String?
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
                        formatSection
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
            .task {
                isNameFocused = true
                await viewModel.loadFormats(session: session)
                // Default to the 2-man bucket's first format so what's
                // on screen is always a combination the server scores.
                if let group = defaultGroup {
                    selectedSize = group.size
                    selectedFormatID = group.formats.first?.id
                }
            }
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

    // MARK: - Format (slice 84)

    private var formatGroups: [FormatGroup] { viewModel.formatGroups }

    /// The bucket the picker defaults to: 2-man teams when the server
    /// offers it, otherwise the first group it sent.
    private var defaultGroup: FormatGroup? {
        formatGroups.first(where: { $0.size == 2 }) ?? formatGroups.first
    }

    private var selectedGroup: FormatGroup? {
        formatGroups.first(where: { $0.size == selectedSize }) ?? formatGroups.first
    }

    /// The format to send: the user's pick, falling back to the
    /// group's first so a stale id never leaves the screen.
    private var selectedFormat: TournamentFormat? {
        guard let group = selectedGroup else { return nil }
        return group.formats.first(where: { $0.id == selectedFormatID }) ?? group.formats.first
    }

    @ViewBuilder
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("SIDES & FORMAT")

            if formatGroups.isEmpty {
                formatsPlaceholder
            } else if let group = selectedGroup {
                // 1. Team size — drives which formats are offered.
                HStack(spacing: 6) {
                    ForEach(formatGroups) { bucket in
                        sizeChip(bucket)
                    }
                }

                // 2. How scores count — only this size's formats.
                Picker("How scores count", selection: $selectedFormatID) {
                    ForEach(group.formats) { format in
                        Text(format.label).tag(Optional(format.id))
                    }
                }
                .pickerStyle(.menu)
                .font(SticksFont.sans(15, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .padding(.top, 2)

                if let format = selectedFormat, let blurb = format.blurb, !blurb.isEmpty {
                    Text(blurb)
                        .font(SticksFont.sans(13))
                        .foregroundStyle(Color.sticksMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
            }
        }
    }

    private func sizeChip(_ bucket: FormatGroup) -> some View {
        let isSelected = bucket.size == selectedSize
        return Button {
            guard bucket.size != selectedSize else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Changing size selects that group's FIRST format, so the
            // visible pair is always one the server can score.
            selectedSize = bucket.size
            selectedFormatID = bucket.formats.first?.id
        } label: {
            Text(bucket.label)
                .font(SticksFont.sans(12, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(isSelected ? Color.sticksCream : Color.sticksInk)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? Color.sticksGreen : Color.sticksCard)
                .clipShape(.rect(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(isSelected ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sides: \(bucket.label)")
    }

    @ViewBuilder
    private var formatsPlaceholder: some View {
        if viewModel.formatsFailed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Formats couldn't load — the event will be scored the classic way.")
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksMuted)
                Button("Retry") {
                    Task { await viewModel.loadFormats(session: session, force: true) }
                }
                .font(SticksFont.sans(13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Color.sticksGreen)
                Text("Loading formats…")
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksMuted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
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
                format: selectedFormat?.id,
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
