//
//  MarketCard.swift
//  Sticks
//
//  Slice 41: the Market — the web's Live odds view. Blend header
//  (model/crowd/live), the win-probability graph upgraded with soft
//  area fills + latest-hole dots, per-player rows (win %, hcp chip,
//  bar, call count, projected net), and "Place your call" — one crowd
//  call per user via POST /matches/:id/call, applied optimistically.
//  Replaces the plain "Win odds" card from slice 34.
//

import SwiftUI
import Charts
import UIKit

struct MarketCard: View {
    let detail: MatchDetail
    let odds: MatchOdds
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    /// matchPlayerId of the in-flight call POST — blocks double taps.
    @State private var pendingCallId: String?
    @State private var callError: String?

    /// One player's polyline through the series buckets.
    private struct PlayerLine: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [(hole: Int, pct: Double)]
    }

    /// Players ranked by blended win probability, best first.
    private var rankedPlayers: [MatchDetailPlayer] {
        detail.players.sorted {
            (odds.probabilities[$0.id] ?? 0) > (odds.probabilities[$1.id] ?? 0)
        }
    }

    private var lines: [PlayerLine] {
        guard let series = odds.series else { return [] }
        return detail.players.compactMap { player in
            let points: [(hole: Int, pct: Double)] = series.compactMap { row in
                guard let probability = row.probabilities[player.id] else { return nil }
                return (row.hole, probability * 100)
            }
            guard !points.isEmpty else { return nil }
            return PlayerLine(
                id: player.id,
                name: player.displayName,
                color: MatchCardMath.seatColor(player.seat),
                points: points
            )
        }
    }

    /// "model 29% · crowd 0% · live 71%" from odds.weights, web order.
    private var blendLine: String? {
        guard let weights = odds.weights else { return nil }
        let parts: [String] = [("model", weights["model"]), ("crowd", weights["crowd"]), ("live", weights["live"])]
            .compactMap { name, value in
                value.map { "\(name) \(Int(($0 * 100).rounded()))%" }
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        let lines = self.lines

        VStack(alignment: .leading, spacing: 14) {
            header

            if lines.contains(where: { $0.points.count >= 2 }) {
                chart(lines)
                    .frame(height: 170)
                legend(lines)
            }

            playerRows

            Rectangle()
                .fill(Color.sticksHairline.opacity(0.6))
                .frame(height: 1)

            callSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .alert(
            "Couldn't place that call",
            isPresented: Binding(
                get: { callError != nil },
                set: { if !$0 { callError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(callError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Market")
                    .font(SticksFont.display(13, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                if odds.open && detail.status == .inProgress {
                    HStack(spacing: 5) {
                        MarketRepricingDot()
                        Text("REPRICING")
                            .font(SticksFont.mono(10))
                            .kerning(1)
                    }
                    .foregroundStyle(Color.sticksGreen)
                } else if !odds.open {
                    Text("CLOSED")
                        .font(SticksFont.mono(10))
                        .kerning(1)
                        .foregroundStyle(Color.sticksMuted)
                }
            }

            if let blendLine {
                Text(blendLine)
                    .font(SticksFont.mono(10))
                    .kerning(0.5)
                    .foregroundStyle(Color.sticksMuted)
            }
        }
    }

    // MARK: - Chart (slice 34, upgraded)

    private func chart(_ lines: [PlayerLine]) -> some View {
        Chart {
            // Faint dashed gridlines at 25/50/75 — the 50% even-odds
            // line slightly stronger, like the web.
            ForEach([25, 50, 75], id: \.self) { level in
                RuleMark(y: .value("Grid", level))
                    .foregroundStyle(Color.sticksHairline.opacity(level == 50 ? 0.9 : 0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(lines) { line in
                ForEach(line.points, id: \.hole) { point in
                    // Soft area fill under the line. Explicit yStart
                    // keeps areas independent (no stacking).
                    AreaMark(
                        x: .value("Hole", point.hole),
                        yStart: .value("Base", 0),
                        yEnd: .value("Win %", point.pct),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [line.color.opacity(0.16), line.color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Hole", point.hole),
                        y: .value("Win %", point.pct),
                        series: .value("Player", line.id)
                    )
                    .foregroundStyle(line.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Dot on the latest bucket.
                if let last = line.points.last {
                    PointMark(
                        x: .value("Hole", last.hole),
                        y: .value("Win %", last.pct)
                    )
                    .foregroundStyle(line.color)
                    .symbolSize(38)
                }
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisValueLabel {
                    if let pct = value.as(Int.self) {
                        Text("\(pct)%")
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.sticksHairline.opacity(0.4))
                AxisValueLabel {
                    if let hole = value.as(Int.self) {
                        Text("\(hole)")
                            .font(SticksFont.mono(9))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
    }

    private func legend(_ lines: [PlayerLine]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(lines) { line in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(line.color)
                        .frame(width: 14, height: 4)
                    Text(line.name)
                        .font(SticksFont.sans(11))
                        .foregroundStyle(Color.sticksMuted)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Per-player rows

    private var playerRows: some View {
        VStack(spacing: 14) {
            ForEach(rankedPlayers) { player in
                playerRow(player)
            }
        }
    }

    private func playerRow(_ player: MatchDetailPlayer) -> some View {
        let probability = odds.probabilities[player.id] ?? 0
        let calls = odds.wagerCounts[player.id] ?? 0
        let projNet = odds.projNet[player.id]
        let color = MatchCardMath.seatColor(player.seat)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                MarketAvatar(player: player)

                Text(player.displayName)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                if let handicap = player.handicap {
                    Text("hcp \(handicapText(handicap))")
                        .font(SticksFont.mono(9))
                        .foregroundStyle(Color.sticksMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.sticksPanel2)
                        .clipShape(.capsule)
                        .overlay(
                            Capsule().stroke(Color.sticksHairline, lineWidth: 1)
                        )
                }

                Spacer(minLength: 8)

                Text("\(Int((probability * 100).rounded()))%")
                    .font(SticksFont.display(18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
            }

            // Full-width win bar in the player's identity color.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sticksPanel2)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * min(max(probability, 0), 1), 4))
                        .animation(.easeOut(duration: 0.35), value: probability)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(calls) \(calls == 1 ? "call" : "calls")")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)

                Spacer()

                if let projNet {
                    Text("proj net \(String(format: "%.1f", projNet))")
                        .font(SticksFont.mono(10))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        }
    }

    /// "12" for whole-number handicaps, "8.4" otherwise.
    private func handicapText(_ handicap: Double) -> String {
        handicap.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(handicap))
            : String(format: "%.1f", handicap)
    }

    // MARK: - Place your call

    private var callSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Place your call")
                    .font(SticksFont.display(13, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                if odds.totalCalls > 0 {
                    Text("\(odds.totalCalls) TOTAL")
                        .font(SticksFont.mono(10))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksMuted)
                }
            }

            if !odds.open {
                Text("Market closed — this round is final.")
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
            }

            VStack(spacing: 8) {
                ForEach(rankedPlayers) { player in
                    callRow(player)
                }
            }

            if odds.open {
                Text(odds.myCall == nil
                    ? "Tap a player to call the winner — one call per person."
                    : "Tap your pick again to withdraw your call.")
                    .font(SticksFont.sans(11))
                    .foregroundStyle(Color.sticksFaint)
            }
        }
    }

    private func callRow(_ player: MatchDetailPlayer) -> some View {
        let isMine = odds.myCall == player.id
        let probability = odds.probabilities[player.id] ?? 0
        let calls = odds.wagerCounts[player.id] ?? 0

        return Button {
            placeCall(player)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isMine ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isMine ? Color.sticksGreen : Color.sticksFaint)

                Text(player.displayName)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if pendingCallId == player.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.sticksGreen)
                }

                Text("\(Int((probability * 100).rounded()))%")
                    .font(SticksFont.display(13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)

                Text("\(calls) \(calls == 1 ? "call" : "calls")")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 52, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isMine ? Color.sticksGreen.opacity(0.08) : Color.sticksPanel2.opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isMine ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!odds.open || pendingCallId != nil)
        .opacity(odds.open ? 1 : 0.6)
        .accessibilityLabel("\(isMine ? "Withdraw call on" : "Call") \(player.displayName)")
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }

    /// Tapping your current pick withdraws it (pickedPlayerId: null);
    /// anyone else places/moves the call. The response applies to the
    /// odds in place — no full refetch. Light haptic on success.
    private func placeCall(_ player: MatchDetailPlayer) {
        guard odds.open, pendingCallId == nil else { return }
        let picked: String? = odds.myCall == player.id ? nil : player.id
        pendingCallId = player.id
        Task {
            defer { pendingCallId = nil }
            do {
                try await viewModel.placeCall(pickedPlayerId: picked, session: session)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch let error as APIError {
                callError = error.message
            } catch {
                callError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}

// MARK: - Pieces

/// 18pt avatar — profile photo when set, else initials on the seat color.
private struct MarketAvatar: View {
    let player: MatchDetailPlayer

    var body: some View {
        Group {
            if let urlString = player.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        initialsBubble
                    }
                }
            } else {
                initialsBubble
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(.circle)
    }

    private var initialsBubble: some View {
        Text(initials)
            .font(SticksFont.label(7, weight: .bold))
            .foregroundStyle(Color.sticksCream)
            .frame(width: 18, height: 18)
            .background(MatchCardMath.seatColor(player.seat))
    }

    private var initials: String {
        let parts = player.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// Pulsing accent dot for the REPRICING badge.
private struct MarketRepricingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 5, height: 5)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
