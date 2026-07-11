//
//  ScoreEntryView.swift
//  Sticks
//
//  Score entry sheet, shared by the scorecard grid and the on-course GPS
//  screen. Slice 18: the web app's par-relative grid — one 5-column grid
//  whose cells self-describe against the hole's par (tap selects, SAVE
//  posts), plus X (pickup, logs par × 2) and — (skip, dismisses blank).
//  Saving updates the scorecard optimistically, then cycles to the next
//  seat-ordered player still missing a score on the hole. The FIRST
//  saved score notifies the caller via `onScoreSaved` (the GPS screen
//  advances its map to the next hole immediately); when the hole is
//  complete the sheet dismisses and fires `onHoleComplete`.
//

import SwiftUI

struct ScoreEntryView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore
    let hole: Int
    let par: Int
    /// Fired after every successful (non-clear) save — the GPS screen
    /// uses it to auto-advance the map as soon as a score goes in.
    let onScoreSaved: () -> Void
    let onHoleComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentPlayerId: String
    @State private var pendingScore: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        cell: ScoreCellSelection,
        viewModel: MatchDetailViewModel,
        session: SessionStore,
        onScoreSaved: @escaping () -> Void = {},
        onHoleComplete: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.session = session
        self.hole = cell.hole
        self.par = cell.par
        self.onScoreSaved = onScoreSaved
        self.onHoleComplete = onHoleComplete
        _currentPlayerId = State(initialValue: cell.player.id)
        _pendingScore = State(initialValue: cell.player.scoresByHole[cell.hole])
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

            scoreGrid

            saveButton

            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(isSaving ? 0.65 : 1)
        .animation(.easeOut(duration: 0.15), value: isSaving)
        .presentationDetents([.height(544)])
        .presentationBackground(Color.sticksBg)
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
            pendingScore = player.scoresByHole[hole]
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Text(player.displayName)
                    .font(SticksFont.sans(13, weight: .semibold))
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

    // MARK: - Par-relative grid

    /// Unselected cell tone for a par-relative value.
    private struct CellTone {
        let fill: Color
        let border: Color
        let text: Color
    }

    private func cellTone(relative: Int) -> CellTone {
        switch relative {
        case ..<(-1):
            return CellTone(
                fill: Color.sticksGold.opacity(0.1),
                border: Color.sticksGold.opacity(0.4),
                text: .sticksGold
            )
        case -1:
            return CellTone(
                fill: Color.sticksGreen.opacity(0.1),
                border: Color.sticksGreen.opacity(0.35),
                text: .sticksGreen
            )
        case 0:
            return CellTone(fill: .sticksCard, border: .sticksHairline, text: .sticksInk)
        case 1:
            return CellTone(fill: .sticksCard, border: .sticksHairline, text: .sticksMuted)
        default:
            return CellTone(fill: .sticksCard, border: .sticksHairline, text: .sticksError)
        }
    }

    /// Par-relative label under the stroke number; nil below albatross.
    private func relativeLabel(_ relative: Int) -> String? {
        switch relative {
        case -3: return "ALBATROSS"
        case -2: return "EAGLE"
        case -1: return "BIRDIE"
        case 0: return "PAR"
        case 1: return "BOGEY"
        case 2: return "DOUBLE"
        case 3: return "TRIPLE"
        case let diff where diff > 3: return "+\(diff)"
        default: return nil
        }
    }

    /// 5-column grid: strokes 1–9, then PICKUP (X) and SKIP (—) on the
    /// last row. Labels and tones recompute against this hole's par.
    private var scoreGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
            spacing: 8
        ) {
            ForEach(1 ... 9, id: \.self) { value in
                numberCell(value)
            }
            // Spacer completing the second row so the special cells sit
            // together on the last row.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
            specialCell(glyph: "X") {
                // Pickup: log par × 2 so the round rolls forward.
                save(par * 2)
            }
            specialCell(glyph: "—") {
                // Skip: leave the hole blank.
                dismiss()
            }
        }
    }

    private func numberCell(_ value: Int) -> some View {
        let selected = pendingScore == value
        let relative = value - par
        let tone = cellTone(relative: relative)
        return Button {
            guard !isSaving else { return }
            pendingScore = value
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(SticksFont.mono(22))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.sticksCream : tone.text)
                if let label = relativeLabel(relative) {
                    Text(label)
                        .font(SticksFont.label(9))
                        .kerning(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? Color.sticksCream.opacity(0.85) : tone.text.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(selected ? Color.sticksGreen : tone.fill)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.clear : tone.border, lineWidth: 1)
            )
            .shadow(
                color: selected ? Color.sticksGreen.opacity(0.35) : .clear,
                radius: 8,
                y: 3
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSaving)
    }

    /// Dashed, faint action cell — X (pickup) and — (skip).
    private func specialCell(glyph: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !isSaving else { return }
            action()
        } label: {
            Text(glyph)
                .font(SticksFont.mono(18))
                .foregroundStyle(Color.sticksFaint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .contentShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.sticksHairline,
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                        )
                )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isSaving)
    }

    // MARK: - Save button

    /// True when another player (not the current one) still has no score
    /// on this hole after the pending save.
    private var othersStillNeedScore: Bool {
        viewModel.nextUnscoredPlayer(onHole: hole, after: currentPlayerId) != nil
    }

    /// "Save" while others still need a score on this hole; when the
    /// caller is the last, "Save · go to {next}" or "Save · finish round"
    /// on the round's final hole.
    private var saveLabel: String {
        if othersStillNeedScore { return "Save" }
        guard let detail = viewModel.detail,
              let index = (0 ..< detail.holes).first(where: { detail.holeNumber(at: $0) == hole })
        else { return "Save" }
        if index + 1 < detail.holes {
            return "Save · go to \(detail.holeNumber(at: index + 1))"
        }
        return "Save · finish round"
    }

    private var saveButton: some View {
        Button {
            if let pendingScore {
                save(pendingScore)
            }
        } label: {
            Text(saveLabel)
                .font(SticksFont.sans(15, weight: .bold))
                .foregroundStyle(Color.sticksCream)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(pendingScore == nil ? 0.5 : 1)
        .disabled(isSaving || pendingScore == nil)
    }

    // MARK: - Footer (clear / error)

    private var footer: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(errorMessage)
                        .font(SticksFont.sans(13))
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
                    pendingScore = nil
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onScoreSaved()
                if let next = viewModel.nextUnscoredPlayer(onHole: hole, after: playerId) {
                    withAnimation(.easeInOut(duration: 0.2)) { currentPlayerId = next.id }
                    pendingScore = next.scoresByHole[hole]
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
