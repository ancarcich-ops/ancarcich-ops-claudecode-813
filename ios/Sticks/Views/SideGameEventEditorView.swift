//
//  SideGameEventEditorView.swift
//  Sticks
//
//  Slice 50: per-hole event editors for the event-driven side games —
//  Snake (tap a player to toggle a 3-putt), BBB (assign Bingo/Bango/
//  Bongo per hole) and Match (tap holes to toggle presses). Every tap
//  POSTs /side-game-event, applies optimistically and quiet-refetches
//  so the game's leaderboard tab updates live. Read-only once the
//  round is COMPLETED.
//

import SwiftUI
import UIKit

struct SideGameEventEditorView: View {
    let game: SideGame
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isPosting = false

    private enum EditorKind {
        case snake, bbb, press
    }

    private var editorKind: EditorKind {
        switch MatchDetailMath.eventGameKey(game.kind) {
        case "SNAKE": return .snake
        case "BBB": return .bbb
        default: return .press
        }
    }

    /// BBB's three single-holder awards, in web order.
    private static let bbbAwards: [(kind: String, label: String, hint: String)] = [
        ("BINGO", "Bingo", "First on the green"),
        ("BANGO", "Bango", "Closest once on"),
        ("BONGO", "Bongo", "First in the hole"),
    ]

    private var isReadOnly: Bool {
        viewModel.detail?.status == .completed
    }

    /// Current events for THIS game (aliases normalized).
    private var events: [SideGameEvent] {
        let key = MatchDetailMath.eventGameKey(game.kind)
        return viewModel.response?.sideGameEvents.filter {
            MatchDetailMath.eventGameKey($0.gameKind) == key
        } ?? []
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

            if let detail = viewModel.detail {
                ScrollViewReader { proxy in
                    ScrollView {
                        content(detail)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 30)
                    }
                    .onAppear {
                        proxy.scrollTo(focusHoleIndex(detail), anchor: .top)
                    }
                }
            }
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                Text(title)
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

            Text(isReadOnly ? "Round is final — events are read-only." : helper)
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private var title: String {
        switch editorKind {
        case .snake: return "Snake — 3-putts"
        case .bbb: return "Bingo Bango Bongo"
        case .press: return "Match presses"
        }
    }

    private var helper: String {
        switch editorKind {
        case .snake: return "Tap a player to mark a 3-putt on that hole; tap again to clear."
        case .bbb: return "Tap a player to hand them the award — tap the holder again to clear it."
        case .press: return "Tap a hole to add or remove a press."
        }
    }

    // MARK: - Content

    @ViewBuilder private func content(_ detail: MatchDetail) -> some View {
        switch editorKind {
        case .snake:
            VStack(spacing: 10) {
                ForEach(0 ..< detail.holes, id: \.self) { index in
                    snakeCard(detail: detail, index: index)
                        .id(index)
                }
            }
        case .bbb:
            VStack(spacing: 10) {
                ForEach(0 ..< detail.holes, id: \.self) { index in
                    bbbCard(detail: detail, index: index)
                        .id(index)
                }
            }
        case .press:
            pressGrid(detail)
        }
    }

    // MARK: - Snake

    private func snakeCard(detail: MatchDetail, index: Int) -> some View {
        let hole = detail.holeNumber(at: index)
        let count = events.filter { $0.kind == "THREE_PUTT" && $0.hole == hole }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                holeLabel(hole: hole, detail: detail, index: index)
                Spacer(minLength: 8)
                Text(count == 0 ? "—" : "\(count) 3-PUTT\(count == 1 ? "" : "S")")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(count == 0 ? Color.sticksFaint : Color.sticksError)
            }

            chipStrip { player in
                let isOn = events.contains {
                    $0.kind == "THREE_PUTT" && $0.hole == hole && $0.matchPlayerId == player.id
                }
                return (isOn, { send(kind: "THREE_PUTT", hole: hole, matchPlayerId: player.id) })
            }
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

    // MARK: - BBB

    private func bbbCard(detail: MatchDetail, index: Int) -> some View {
        let hole = detail.holeNumber(at: index)

        return VStack(alignment: .leading, spacing: 12) {
            holeLabel(hole: hole, detail: detail, index: index)

            ForEach(Self.bbbAwards, id: \.kind) { award in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(award.label.uppercased())
                            .font(SticksFont.mono(10))
                            .kerning(1)
                            .foregroundStyle(Color.sticksInk)
                        Text("· \(award.hint.uppercased())")
                            .font(SticksFont.mono(9))
                            .kerning(0.6)
                            .foregroundStyle(Color.sticksFaint)
                    }

                    chipStrip { player in
                        let holder = events.first { $0.kind == award.kind && $0.hole == hole }?.matchPlayerId
                        let isOn = holder == player.id
                        return (isOn, {
                            // Tapping the holder clears (no matchPlayerId);
                            // tapping anyone else moves the award.
                            send(kind: award.kind, hole: hole, matchPlayerId: isOn ? nil : player.id)
                        })
                    }
                }
            }
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

    // MARK: - Press

    private func pressGrid(_ detail: MatchDetail) -> some View {
        let pressed = Set(events.filter { $0.kind == "PRESS" }.map(\.hole))
        let columns = [GridItem(.adaptive(minimum: 52), spacing: 8)]

        return VStack(alignment: .leading, spacing: 12) {
            Text(pressed.isEmpty ? "NO PRESSES YET" : "\(pressed.count) PRESS\(pressed.count == 1 ? "" : "ES")")
                .font(SticksFont.mono(10))
                .kerning(1)
                .foregroundStyle(pressed.isEmpty ? Color.sticksFaint : Color.sticksGold)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0 ..< detail.holes, id: \.self) { index in
                    let hole = detail.holeNumber(at: index)
                    pressCell(hole: hole, isOn: pressed.contains(hole))
                        .id(index)
                }
            }
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

    private func pressCell(hole: Int, isOn: Bool) -> some View {
        Button {
            send(kind: "PRESS", hole: hole, matchPlayerId: nil)
        } label: {
            VStack(spacing: 2) {
                Text("\(hole)")
                    .font(SticksFont.display(17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isOn ? Color.sticksCream : Color.sticksInk)
                Text(isOn ? "PRESS" : "HOLE")
                    .font(SticksFont.mono(7.5))
                    .kerning(0.8)
                    .foregroundStyle(isOn ? Color.sticksCream.opacity(0.85) : Color.sticksFaint)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isOn ? Color.sticksGold : Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.clear : Color.sticksHairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isReadOnly || isPosting)
        .accessibilityLabel("Hole \(hole)\(isOn ? ", pressed" : "")")
    }

    // MARK: - Shared pieces

    private func holeLabel(hole: Int, detail: MatchDetail, index: Int) -> some View {
        HStack(spacing: 6) {
            Text("HOLE \(hole)")
                .font(SticksFont.mono(11))
                .kerning(1)
                .foregroundStyle(Color.sticksInk)
            Text("PAR \(detail.par(at: index))")
                .font(SticksFont.mono(9))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
        }
    }

    /// One equal-width chip per seated player, in seat order. The
    /// builder returns (isOn, tap action) for each player.
    private func chipStrip(
        state: @escaping (MatchDetailPlayer) -> (isOn: Bool, action: () -> Void)
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(viewModel.seatOrderedPlayers) { player in
                let (isOn, action) = state(player)
                playerChip(player, isOn: isOn, action: action)
            }
        }
    }

    private func playerChip(_ player: MatchDetailPlayer, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(firstName(player))
                .font(SticksFont.sans(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.sticksCream : Color.sticksInk)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isOn ? MatchCardMath.seatColor(player.seat) : Color.sticksPanel2)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(isOn ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isReadOnly || isPosting)
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityLabel(player.displayName)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func firstName(_ player: MatchDetailPlayer) -> String {
        player.displayName.split(separator: " ").first.map(String.init) ?? player.displayName
    }

    // MARK: - Behavior

    /// Round index to focus on open — the live GPS session's hole when
    /// this match is on-course, else the first hole anyone hasn't scored.
    private func focusHoleIndex(_ detail: MatchDetail) -> Int {
        let roundSession = RoundSessionService.shared
        if roundSession.activeMatchId == detail.id {
            return min(roundSession.holeIndex, detail.holes - 1)
        }
        guard !detail.players.isEmpty else { return 0 }
        for index in 0 ..< detail.holes {
            let hole = detail.holeNumber(at: index)
            if detail.players.contains(where: { $0.scoresByHole[hole] == nil }) {
                return index
            }
        }
        return detail.holes - 1
    }

    /// POST one event. One in-flight write at a time; server errors
    /// (game not enabled, round final) show inline verbatim.
    private func send(kind: String, hole: Int, matchPlayerId: String?) {
        guard !isPosting, !isReadOnly else { return }
        isPosting = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            defer { isPosting = false }
            do {
                try await viewModel.recordSideGameEvent(
                    gameKind: game.kind,
                    kind: kind,
                    hole: hole,
                    matchPlayerId: matchPlayerId,
                    session: session
                )
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}
