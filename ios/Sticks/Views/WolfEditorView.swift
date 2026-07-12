//
//  WolfEditorView.swift
//  Sticks
//
//  Slice 53: the Wolf editor — rotation + push rule config (creator,
//  POST /side-game-config) and per-hole picks (seated players, POST
//  /side-game-event). Each hole computes whose turn it is to be the
//  wolf from the SAVED rotation; the wolf picks a partner, goes lone
//  wolf, or calls it blind (pre-lone), with an optional PUSH override.
//  The hole winner is derived server-side from the logged scores.
//  Read-only once the round is COMPLETED.
//

import SwiftUI
import UIKit

struct WolfEditorView: View {
    let game: SideGame
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var draftRotation: [String] = []
    @State private var draftPushRule: String = WolfConfig.carry
    @State private var hasSeededDraft = false
    @State private var errorMessage: String?
    @State private var isPosting = false
    @State private var isSavingConfig = false

    /// The three mutually-exclusive picks per hole.
    private static let pickKinds = ["PARTNER", "LONE_WOLF", "PRE_LONE_WOLF"]

    private var isReadOnly: Bool {
        viewModel.detail?.status == .completed
    }

    private var isCreator: Bool {
        viewModel.detail?.isCreator == true
    }

    private var savedConfig: WolfConfig? {
        WolfConfig.decode(from: viewModel.response?.sideGameConfigs["WOLF"])
    }

    /// Rotation that derives each hole's wolf — the SAVED config when
    /// every id maps to a seated player, else seat order. Draft edits
    /// don't shift the per-hole section until saved.
    private var effectiveRotation: [String] {
        let players = viewModel.seatOrderedPlayers
        let ids = Set(players.map(\.id))
        if let saved = savedConfig?.rotation, !saved.isEmpty, saved.allSatisfy(ids.contains) {
            return saved
        }
        return players.map(\.id)
    }

    /// Current events for Wolf only.
    private var events: [SideGameEvent] {
        viewModel.response?.sideGameEvents.filter {
            MatchDetailMath.eventGameKey($0.gameKind) == "WOLF"
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
                        VStack(spacing: 12) {
                            configCard

                            VStack(alignment: .leading, spacing: 10) {
                                Text("PICKS BY HOLE")
                                    .font(SticksFont.mono(10))
                                    .kerning(1)
                                    .foregroundStyle(Color.sticksFaint)

                                ForEach(0 ..< detail.holes, id: \.self) { index in
                                    holeCard(detail: detail, index: index)
                                        .id(index)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                    .onAppear {
                        // Land on the current hole — but only once the
                        // rotation is saved; a fresh Wolf shows config first.
                        if savedConfig != nil {
                            proxy.scrollTo(focusHoleIndex(detail), anchor: .top)
                        }
                    }
                }
            }
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .onAppear(perform: seedDraft)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                Text("Wolf")
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

            Text(isReadOnly
                ? "Round is final — picks are read-only."
                : "Each hole's wolf picks a partner or goes alone — the winner comes from the scores.")
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    // MARK: - Config card

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ROTATION")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)
                Text(canEditConfig
                    ? "The order players take being the wolf. Hole 1 starts at the top."
                    : "The order players take being the wolf.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(draftRotation.enumerated()), id: \.element) { position, playerId in
                    if position > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline.opacity(0.6))
                            .frame(height: 1)
                    }
                    rotationRow(position: position, playerId: playerId)
                }
            }
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("PUSH RULE")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)

                HStack(spacing: 6) {
                    pushRuleChip(label: "Carry over", value: WolfConfig.carry)
                    pushRuleChip(label: "No carry", value: WolfConfig.noCarry)
                }
            }

            if canEditConfig {
                Button {
                    saveConfig()
                } label: {
                    HStack(spacing: 8) {
                        if isSavingConfig {
                            ProgressView()
                                .tint(Color.sticksCream)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text("Save rotation & rule")
                            .font(SticksFont.sans(14, weight: .semibold))
                    }
                    .foregroundStyle(Color.sticksCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isSavingConfig)
            } else if !isReadOnly {
                Text("Only the round's creator can change the rotation.")
                    .font(SticksFont.sans(11.5))
                    .foregroundStyle(Color.sticksFaint)
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

    private var canEditConfig: Bool {
        isCreator && !isReadOnly
    }

    private func rotationRow(position: Int, playerId: String) -> some View {
        HStack(spacing: 10) {
            Text("\(position + 1)")
                .font(SticksFont.mono(11))
                .monospacedDigit()
                .foregroundStyle(Color.sticksFaint)
                .frame(width: 16, alignment: .trailing)

            Text(playerName(playerId))
                .font(SticksFont.sans(13, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            if canEditConfig {
                reorderButton(system: "chevron.up", disabled: position == 0) {
                    move(from: position, by: -1)
                }
                reorderButton(system: "chevron.down", disabled: position == draftRotation.count - 1) {
                    move(from: position, by: 1)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func reorderButton(system: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(disabled ? Color.sticksFaint : Color.sticksGreen)
                .frame(width: 30, height: 30)
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled || isSavingConfig)
    }

    private func pushRuleChip(label: String, value: String) -> some View {
        let isOn = draftPushRule == value
        return Button {
            guard draftPushRule != value else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            draftPushRule = value
        } label: {
            Text(label)
                .font(SticksFont.sans(13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isOn ? Color.sticksCream : Color.sticksInk)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isOn ? Color.sticksGreen : Color.sticksPanel2)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(isOn ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canEditConfig || isSavingConfig)
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Per-hole picks

    private func holeCard(detail: MatchDetail, index: Int) -> some View {
        let hole = detail.holeNumber(at: index)
        let wolf = wolfPlayer(at: index)
        let isPushed = events.contains { $0.kind == "PUSH" && $0.hole == hole }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("HOLE \(hole)")
                    .font(SticksFont.mono(11))
                    .kerning(1)
                    .foregroundStyle(Color.sticksInk)
                Text("PAR \(detail.par(at: index))")
                    .font(SticksFont.mono(9))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksFaint)

                Spacer(minLength: 8)

                Text("WOLF: \(wolf.map { firstName($0).uppercased() } ?? "—")")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGold)
            }

            if let wolf {
                pickChips(hole: hole, wolf: wolf)
                pushRow(hole: hole, isPushed: isPushed)
            } else {
                Text("Waiting on seated players.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
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

    /// One partner chip per non-wolf player, then LONE and BLIND.
    private func pickChips(hole: Int, wolf: MatchDetailPlayer) -> some View {
        let partners = viewModel.seatOrderedPlayers.filter { $0.id != wolf.id }
        let pick = events.first { Self.pickKinds.contains($0.kind) && $0.hole == hole }
        let columns = [GridItem(.adaptive(minimum: 96), spacing: 6)]

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(partners) { partner in
                let isOn = pick?.kind == "PARTNER" && pick?.matchPlayerId == partner.id
                pickChip(
                    label: firstName(partner),
                    sublabel: "PARTNER",
                    isOn: isOn,
                    fill: MatchCardMath.seatColor(partner.seat)
                ) {
                    send(kind: "PARTNER", hole: hole, matchPlayerId: partner.id)
                }
            }

            pickChip(
                label: "Lone wolf",
                sublabel: "1 VS ALL",
                isOn: pick?.kind == "LONE_WOLF",
                fill: Color.sticksGold
            ) {
                send(kind: "LONE_WOLF", hole: hole, matchPlayerId: wolf.id)
            }

            pickChip(
                label: "Blind",
                sublabel: "PRE-TEE LONE",
                isOn: pick?.kind == "PRE_LONE_WOLF",
                fill: Color.sticksGold
            ) {
                send(kind: "PRE_LONE_WOLF", hole: hole, matchPlayerId: wolf.id)
            }
        }
    }

    private func pickChip(
        label: String,
        sublabel: String,
        isOn: Bool,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(isOn ? Color.sticksCream : Color.sticksInk)
                Text(sublabel)
                    .font(SticksFont.mono(7.5))
                    .kerning(0.8)
                    .foregroundStyle(isOn ? Color.sticksCream.opacity(0.85) : Color.sticksFaint)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isOn ? fill : Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? Color.clear : Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isReadOnly || isPosting)
        .animation(.easeOut(duration: 0.12), value: isOn)
        .accessibilityLabel("\(label), \(sublabel.lowercased())")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// PUSH override — the hole splits regardless of scores; clearing
    /// restores the score-derived winner.
    private func pushRow(hole: Int, isPushed: Bool) -> some View {
        Button {
            send(kind: "PUSH", hole: hole, matchPlayerId: nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isPushed ? "equal.circle.fill" : "equal.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(isPushed ? "PUSHED — TAP TO RESTORE SCORES" : "PUSH THE HOLE")
                    .font(SticksFont.mono(9.5))
                    .kerning(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isPushed ? Color.sticksGold : Color.sticksMuted)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isPushed ? Color.sticksGold.opacity(0.1) : Color.sticksPanel2.opacity(0.6))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPushed ? Color.sticksGold.opacity(0.35) : Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isReadOnly || isPosting)
        .accessibilityLabel(isPushed ? "Hole \(hole) pushed, tap to restore" : "Push hole \(hole)")
    }

    // MARK: - Behavior

    private func seedDraft() {
        guard !hasSeededDraft else { return }
        hasSeededDraft = true
        draftRotation = effectiveRotation
        draftPushRule = savedConfig?.pushRule ?? WolfConfig.carry
    }

    private func move(from position: Int, by offset: Int) {
        let destination = position + offset
        guard draftRotation.indices.contains(position),
              draftRotation.indices.contains(destination) else { return }
        draftRotation.swapAt(position, destination)
    }

    private func wolfPlayer(at index: Int) -> MatchDetailPlayer? {
        let rotation = effectiveRotation
        guard !rotation.isEmpty else { return nil }
        let id = rotation[index % rotation.count]
        return viewModel.seatOrderedPlayers.first { $0.id == id }
    }

    private func playerName(_ playerId: String) -> String {
        viewModel.seatOrderedPlayers.first { $0.id == playerId }?.displayName ?? "—"
    }

    private func firstName(_ player: MatchDetailPlayer) -> String {
        player.displayName.split(separator: " ").first.map(String.init) ?? player.displayName
    }

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

    /// POST /side-game-config with the draft, then quiet refetch — the
    /// per-hole wolves re-derive from the saved rotation.
    private func saveConfig() {
        guard !isSavingConfig, canEditConfig else { return }
        isSavingConfig = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let config = WolfConfig(rotation: draftRotation, pushRule: draftPushRule)
        Task {
            defer { isSavingConfig = false }
            do {
                try await viewModel.setSideGameConfig(kind: "WOLF", config: config, session: session)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    /// POST one pick/push event. One in-flight write at a time; server
    /// errors (game not enabled, round final) show inline verbatim.
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
