//
//  ScoreEntryView.swift
//  Sticks
//
//  Slice 5: one-tap score entry sheet, shared by the scorecard grid and
//  the on-course GPS screen. Tapping a value posts /score immediately,
//  updates the scorecard optimistically, then cycles to the next
//  seat-ordered player still missing a score on the hole. When the hole
//  is complete the sheet dismisses and notifies the caller (the GPS
//  screen advances to the next hole).
//

import SwiftUI

struct ScoreEntryView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore
    let hole: Int
    let par: Int
    let onHoleComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPlayerId: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        cell: ScoreCellSelection,
        viewModel: MatchDetailViewModel,
        session: SessionStore,
        onHoleComplete: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.session = session
        self.hole = cell.hole
        self.par = cell.par
        self.onHoleComplete = onHoleComplete
        _currentPlayerId = State(initialValue: cell.player.id)
    }

    /// Live view of the current player so optimistic updates show through.
    private var currentPlayer: MatchDetailPlayer? {
        viewModel.detail?.players.first { $0.id == currentPlayerId }
    }

    private var currentScore: Int? {
        currentPlayer?.scoresByHole[hole]
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            if viewModel.seatOrderedPlayers.count > 1 {
                playerCycleRow
            }

            quickChips

            numberGrid

            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isSaving ? 0.65 : 1)
        .animation(.easeOut(duration: 0.15), value: isSaving)
        .presentationDetents([.height(478)])
        .presentationBackground(Color.sticksCream)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("HOLE \(hole) · PAR \(par)")
                .font(SticksFont.label(11))
                .kerning(1.8)
                .foregroundStyle(Color.sticksMuted)

            HStack(spacing: 7) {
                Text(currentPlayer?.displayName ?? "")
                    .font(SticksFont.display(28))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if isMe(currentPlayerId) {
                    Text("YOU")
                        .font(SticksFont.label(9, weight: .heavy))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksCream)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.sticksGreen)
                        .clipShape(.capsule)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: currentPlayerId)
        }
    }

    // MARK: - Player cycle row

    private var playerCycleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.seatOrderedPlayers) { player in
                    playerChip(player)
                }
            }
        }
        .contentMargins(.horizontal, 4, for: .scrollContent)
    }

    private func playerChip(_ player: MatchDetailPlayer) -> some View {
        let isCurrent = player.id == currentPlayerId
        let score = player.scoresByHole[hole]

        return Button {
            guard !isSaving else { return }
            withAnimation(.easeInOut(duration: 0.2)) { currentPlayerId = player.id }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(player.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let score {
                    Text("\(score)")
                        .font(SticksFont.display(12, weight: .bold))
                        .foregroundStyle(isCurrent ? Color.sticksGreen : Color.sticksCream)
                        .frame(width: 19, height: 19)
                        .background(isCurrent ? Color.sticksCream : Color.sticksMuted)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .stroke(
                            isCurrent ? Color.sticksCream.opacity(0.7) : Color.sticksHairline,
                            style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2])
                        )
                        .frame(width: 16, height: 16)
                }
            }
            .foregroundStyle(isCurrent ? Color.sticksCream : Color.sticksInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isCurrent ? Color.sticksGreen : Color.sticksCard)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(
                    isCurrent ? Color.sticksGreen : Color.sticksHairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Par-relative chips

    /// Quick values from eagle range through triple bogey, clamped at 1.
    private var quickValues: [Int] {
        Array(max(1, par - 2) ... (par + 3))
    }

    private var quickChips: some View {
        HStack(spacing: 8) {
            ForEach(quickValues, id: \.self) { value in
                quickChip(value)
            }
        }
    }

    private func quickChip(_ value: Int) -> some View {
        let selected = currentScore == value
        return Button {
            save(value)
        } label: {
            VStack(spacing: 3) {
                Text(quickLabel(for: value))
                    .font(SticksFont.label(8.5, weight: .bold))
                    .kerning(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(selected ? Color.sticksCream.opacity(0.8) : Color.sticksMuted)
                Text("\(value)")
                    .font(SticksFont.display(23))
                    .foregroundStyle(selected ? Color.sticksCream : Color.sticksInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(selected ? Color.sticksGreen : Color.sticksCard)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSaving)
    }

    private func quickLabel(for value: Int) -> String {
        if value == 1 { return "ACE" }
        switch value - par {
        case -3: return "ALBA"
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DBL"
        case 3: return "TRPL"
        case let diff where diff > 0: return "+\(diff)"
        case let diff: return "\(diff)"
        }
    }

    // MARK: - Number grid 1–12

    private var numberGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
            spacing: 8
        ) {
            ForEach(1 ... 12, id: \.self) { value in
                numberCell(value)
            }
        }
    }

    private func numberCell(_ value: Int) -> some View {
        let selected = currentScore == value
        return Button {
            save(value)
        } label: {
            Text("\(value)")
                .font(SticksFont.display(19))
                .foregroundStyle(selected ? Color.sticksCream : Color.sticksInk)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(selected ? Color.sticksGreen : Color.sticksCard)
                .clipShape(.rect(cornerRadius: 11))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(selected ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
                )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSaving)
    }

    // MARK: - Footer (clear / error)

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Color.sticksError)
            }

            if currentScore != nil {
                Button {
                    save(nil)
                } label: {
                    Text("CLEAR SCORE")
                        .font(SticksFont.label(12, weight: .bold))
                        .kerning(1.6)
                        .foregroundStyle(Color.sticksError)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    // MARK: - Saving

    /// Posts the score (nil clears), then cycles to the next unscored
    /// player in seat order, or dismisses when the hole is complete.
    private func save(_ strokes: Int?) {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let playerId = currentPlayerId

        Task {
            do {
                try await viewModel.submitScore(
                    playerId: playerId,
                    hole: hole,
                    strokes: strokes,
                    session: session
                )
                isSaving = false
                if strokes == nil {
                    // Cleared — stay on this player so a new score can go in.
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let next = viewModel.nextUnscoredPlayer(onHole: hole, after: playerId) {
                    withAnimation(.easeInOut(duration: 0.2)) { currentPlayerId = next.id }
                } else {
                    dismiss()
                    onHoleComplete()
                }
            } catch let error as APIError {
                isSaving = false
                errorMessage = error.message
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } catch {
                isSaving = false
                errorMessage = "Couldn't save the score. Try again."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Helpers

    private func isMe(_ playerId: String) -> Bool {
        viewModel.detail?.myMatchPlayerId == playerId
    }
}
