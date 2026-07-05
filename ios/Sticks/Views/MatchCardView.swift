//
//  MatchCardView.swift
//  Sticks
//
//  Slice 11: status-aware home-feed match cards. The whole card is the
//  tap target. LIVE cards carry per-player stat rows, the solid-fill
//  hole dot row, and momentum chips; UPCOMING cards show a countdown
//  pill and compact player rows; FINAL cards get the gold winner band
//  and a recap footer.
//
//  TO PAR here is GROSS to par through played holes (deliberate v1
//  simplification — net arrives with the match-detail parity slice).
//

import SwiftUI

struct MatchCardView: View {
    let match: MatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            switch match.status {
            case .inProgress:
                livePlayerBlocks
            case .upcoming:
                compactRows(showsToPar: false)
            case .completed:
                finalBody
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(
                    match.status == .inProgress
                        ? Color.sticksGreen.opacity(0.4)
                        : Color.sticksHairline,
                    lineWidth: 1
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                (
                    Text(match.courseName)
                        .foregroundStyle(Color.sticksInk)
                    + Text(" · \(nineSuffix)")
                        .foregroundStyle(Color.sticksMuted)
                )
                .font(SticksFont.display(16))
                .lineLimit(1)

                metaLine
            }

            Spacer(minLength: 8)

            statusPill
        }
    }

    /// "· 18" / "· Front 9" / "· Back 9" (9 holes starting on 10 = Back 9).
    private var nineSuffix: String {
        guard match.holes == 9 else { return "\(match.holes)" }
        return match.startingHole == 10 ? "Back 9" : "Front 9"
    }

    /// "SAT 8:44 AM", plus "· HOLE 7 NEXT · P4" on live cards with the
    /// hole part in accent.
    private var metaLine: some View {
        var line = Text(Self.dateText(for: match))
            .foregroundStyle(Color.sticksMuted)
        if match.status == .inProgress {
            let index = match.nextHoleIndex
            line = line
                + Text(" · HOLE \(match.holeNumber(at: index)) NEXT")
                    .foregroundStyle(Color.sticksGreen)
                + Text(" · P\(match.par(at: index))")
                    .foregroundStyle(Color.sticksMuted)
        }
        return line
            .font(SticksFont.mono(10))
            .kerning(0.8)
            .textCase(.uppercase)
            .lineLimit(1)
    }

    private static func dateText(for match: MatchSummary) -> String {
        let date = match.status == .completed
            ? (match.completedAt ?? match.scheduledAt)
            : match.scheduledAt
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter.string(from: date).uppercased()
    }

    // MARK: - Status pill

    @ViewBuilder private var statusPill: some View {
        switch match.status {
        case .inProgress:
            CardPill(fill: .sticksGreen) {
                HStack(spacing: 5) {
                    CardPulsingDot()
                    Text("LIVE")
                }
            }
        case .completed:
            CardPill(fill: .sticksGold, borderOpacity: 0.4) {
                Text("FINAL")
            }
        case .upcoming:
            // Recomputed every 60s while visible.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                CardPill(
                    fill: Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255),
                    text: Color(red: 2 / 255, green: 132 / 255, blue: 199 / 255),
                    borderOpacity: 0.4
                ) {
                    Text(Self.countdownText(to: match.scheduledAt, now: context.date))
                }
            }
        }
    }

    /// "IN 2H 14M" / "IN 3D 2H" / "NOW".
    private static func countdownText(to date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 60 else { return "NOW" }
        let minutes = Int(seconds / 60)
        let days = minutes / (60 * 24)
        let hours = (minutes % (60 * 24)) / 60
        if days > 0 { return "IN \(days)D \(hours)H" }
        if hours > 0 { return "IN \(hours)H \(minutes % 60)M" }
        return "IN \(minutes)M"
    }

    // MARK: - LIVE player blocks

    private var livePlayerBlocks: some View {
        let showsWin = !match.probabilities.isEmpty && match.players.count > 1
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(match.players.enumerated()), id: \.element.id) { position, player in
                if position > 0 {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                }
                LivePlayerBlock(match: match, player: player, showsWin: showsWin)
            }
        }
    }

    // MARK: - Compact rows (upcoming + final)

    private func compactRows(showsToPar: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(match.players) { player in
                HStack(spacing: 10) {
                    PlayerAvatar(player: player, size: 24)

                    Text(player.displayName)
                        .font(SticksFont.sans(14, weight: .medium))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    if let handicap = player.handicap {
                        Text("HCP \(handicap, specifier: "%.1f")")
                            .font(SticksFont.mono(10))
                            .foregroundStyle(Color.sticksMuted)
                    }

                    Spacer()

                    if showsToPar {
                        ToParText(diff: MatchCardMath.grossToPar(for: player, in: match), size: 13)
                    }
                }
            }
        }
    }

    // MARK: - FINAL body

    @ViewBuilder private var finalBody: some View {
        if match.players.count > 1, let winner = MatchCardMath.winner(of: match) {
            WinnerBand(
                name: winner.displayName,
                diff: MatchCardMath.grossToPar(for: winner, in: match)
            )
        }

        compactRows(showsToPar: true)

        Rectangle()
            .fill(Color.sticksHairline)
            .frame(height: 1)

        HStack {
            Text("\(match.holes) HOLES")
            Spacer()
            Text("RECAP →")
        }
        .font(SticksFont.mono(10))
        .kerning(0.8)
        .foregroundStyle(Color.sticksMuted)
    }
}

// MARK: - Live player block

private struct LivePlayerBlock: View {
    let match: MatchSummary
    let player: MatchPlayerSummary
    let showsWin: Bool

    var body: some View {
        let holesPlayed = player.scoresByHole.count

        VStack(alignment: .leading, spacing: 9) {
            identityRow
            HoleDotRow(match: match, player: player)
            if holesPlayed > 0 {
                progressRow(holesPlayed: holesPlayed)
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 10) {
            PlayerAvatar(player: player, size: 24, ringWidth: 2)

            Text(player.displayName)
                .font(SticksFont.sans(14, weight: .medium))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            if let handicap = player.handicap {
                Text("HCP \(handicap, specifier: "%.1f")")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
            }

            Spacer(minLength: 8)

            statPair(label: "TO PAR") {
                ToParText(diff: MatchCardMath.grossToPar(for: player, in: match), size: 14)
            }

            if showsWin {
                statPair(label: "WIN") {
                    Text(winText)
                        .font(SticksFont.display(13, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                }
            }
        }
    }

    private var winText: String {
        guard let probability = match.probabilities[player.id] else { return "—" }
        return "\(Int((probability * 100).rounded()))%"
    }

    private func statPair<Content: View>(
        label: String,
        @ViewBuilder value: () -> Content
    ) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(SticksFont.mono(9))
                .kerning(0.7)
                .foregroundStyle(Color.sticksMuted.opacity(0.75))
            value()
        }
    }

    private func progressRow(holesPlayed: Int) -> some View {
        HStack(spacing: 8) {
            Text("THRU \(holesPlayed) OF \(match.holes)")
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .foregroundStyle(Color.sticksMuted)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.sticksPanel2)
                .clipShape(.capsule)

            if let chip = MatchCardMath.momentumChip(for: player, in: match) {
                Text("\(chip.emoji) \(chip.label)")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(chip.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(chip.color.opacity(0.1))
                    .clipShape(.capsule)
                    .overlay(
                        Capsule().stroke(chip.color.opacity(0.3), lineWidth: 1)
                    )
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Hole dot row

/// One square per hole, 9 + "|" + 9 for 18. This is where the
/// solid-fill score language lives (NOT the detail-grid outline style).
private struct HoleDotRow: View {
    let match: MatchSummary
    let player: MatchPlayerSummary

    var body: some View {
        HStack(spacing: 3) {
            group(indices: 0 ..< min(9, match.holes))
            if match.holes > 9 {
                Text("|")
                    .font(SticksFont.mono(9))
                    .foregroundStyle(Color.sticksHairline)
                group(indices: 9 ..< match.holes)
            }
        }
    }

    private func group(indices: Range<Int>) -> some View {
        ForEach(indices, id: \.self) { index in
            dot(at: index)
        }
    }

    @ViewBuilder private func dot(at index: Int) -> some View {
        let hole = match.holeNumber(at: index)
        let score = player.scoresByHole[hole]

        Group {
            if let score {
                scoredDot(score: score, par: match.par(at: index))
            } else if index == match.nextHoleIndex {
                // Hole currently in play: dashed accent, no number.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.sticksGreen.opacity(0.08))
                    .strokeBorder(
                        Color.sticksGreen,
                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
            } else {
                // Unplayed: outline only, empty.
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.sticksHairline, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 17)
    }

    private func scoredDot(score: Int, par: Int) -> some View {
        let style = ScoreStyle.forScore(score, par: par)
        return RoundedRectangle(cornerRadius: 3)
            .fill(style.fill)
            .strokeBorder(style.border, lineWidth: 1)
            .overlay(
                Text("\(score)")
                    .font(SticksFont.mono(8.5))
                    .foregroundStyle(style.text)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke((style.ring ?? .clear).opacity(0.45), lineWidth: 1.5)
                    .padding(-1.5)
            )
    }
}

// MARK: - Winner band

private struct WinnerBand: View {
    let name: String
    let diff: Int?

    var body: some View {
        ZStack {
            HStack {
                Text("WINNER")
                    .font(SticksFont.mono(10, weight: .medium))
                    .kerning(1)
                Spacer()
                Text(MatchCardMath.toParLabel(diff))
                    .font(SticksFont.mono(13))
            }
            .foregroundStyle(Color.sticksGold)

            Text(name)
                .font(SticksFont.sans(14, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .padding(.horizontal, 66)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.sticksGold.opacity(0.06))
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.sticksGold.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Shared pieces

/// Avatar bubble — photo from avatarUrl, else initials on a seat-colored
/// circle. Optional seat-color ring for the live identity row.
private struct PlayerAvatar: View {
    let player: MatchPlayerSummary
    let size: CGFloat
    var ringWidth: CGFloat = 0

    var body: some View {
        Group {
            if let urlString = player.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        initialsBubble
                    }
                }
            } else {
                initialsBubble
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(
            Circle().stroke(
                ringWidth > 0 ? seatColor : .clear,
                lineWidth: ringWidth
            )
        )
    }

    private var initialsBubble: some View {
        ZStack {
            seatColor
            Text(initials)
                .font(SticksFont.label(size * 0.4, weight: .bold))
                .foregroundStyle(Color.sticksCream)
        }
    }

    private var initials: String {
        let parts = player.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    private var seatColor: Color {
        MatchCardMath.seatColor(player.seat)
    }
}

/// Gross to-par value — accent negative / danger positive / mute even.
private struct ToParText: View {
    let diff: Int?
    let size: CGFloat

    var body: some View {
        Text(MatchCardMath.toParLabel(diff))
            .font(SticksFont.mono(size))
            .foregroundStyle(color)
    }

    private var color: Color {
        guard let diff, diff != 0 else { return .sticksMuted }
        return diff < 0 ? .sticksGreen : .sticksError
    }
}

/// Status pill shell shared by LIVE / FINAL / countdown variants.
private struct CardPill<Content: View>: View {
    let fill: Color
    var text: Color?
    var borderOpacity: Double = 0.3
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(SticksFont.mono(10))
            .kerning(1)
            .textCase(.uppercase)
            .foregroundStyle(text ?? fill)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(fill.opacity(0.1))
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(fill.opacity(borderOpacity), lineWidth: 1)
            )
    }
}

private struct CardPulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Card math

/// Pure helpers shared by the card's sub-views.
nonisolated enum MatchCardMath {
    struct MomentumChip {
        let emoji: String
        let label: String
        let color: Color
    }

    /// GROSS strokes over/under par through the player's scored holes.
    /// nil when the player has no scores yet.
    static func grossToPar(for player: MatchPlayerSummary, in match: MatchSummary) -> Int? {
        var diff = 0
        var played = 0
        for index in 0 ..< match.holes {
            guard let score = player.scoresByHole[match.holeNumber(at: index)] else { continue }
            diff += score - match.par(at: index)
            played += 1
        }
        return played > 0 ? diff : nil
    }

    /// "-2" / "+3" / "E" / "—".
    static func toParLabel(_ diff: Int?) -> String {
        guard let diff else { return "—" }
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    /// Winner of a completed match: lowest gross to par, ties broken by
    /// the lowest seat. nil when nobody has a score.
    static func winner(of match: MatchSummary) -> MatchPlayerSummary? {
        let ranked: [(player: MatchPlayerSummary, diff: Int)] = match.players.compactMap { player in
            grossToPar(for: player, in: match).map { (player, $0) }
        }
        return ranked.min {
            if $0.diff != $1.diff { return $0.diff < $1.diff }
            return ($0.player.seat ?? Int.max) < ($1.player.seat ?? Int.max)
        }?.player
    }

    /// ONE momentum chip when earned, in priority order:
    /// eagle on last hole → 3+ birdies → birdie on last hole → cold streak.
    static func momentumChip(for player: MatchPlayerSummary, in match: MatchSummary) -> MomentumChip? {
        // Scored holes in round order: (hole number, strokes − par).
        let scored: [(hole: Int, diff: Int)] = (0 ..< match.holes).compactMap { index in
            let hole = match.holeNumber(at: index)
            guard let score = player.scoresByHole[hole] else { return nil }
            return (hole, score - match.par(at: index))
        }
        guard let last = scored.last else { return nil }

        if last.diff <= -2 {
            return MomentumChip(emoji: "🦅", label: "EAGLE ON \(last.hole)", color: .sticksGold)
        }
        let birdieCount = scored.filter { $0.diff <= -1 }.count
        if birdieCount >= 3 {
            return MomentumChip(emoji: "🔥", label: "\(birdieCount) BIRDIES", color: .sticksGreen)
        }
        if last.diff == -1 {
            return MomentumChip(emoji: "🐥", label: "BIRDIE ON \(last.hole)", color: .sticksGreen)
        }
        let lastThree = scored.suffix(3)
        let coldSum = lastThree.reduce(0) { $0 + $1.diff }
        if lastThree.count == 3, coldSum >= 4 {
            return MomentumChip(emoji: "❄️", label: "+\(coldSum) · LAST 3", color: .sticksError)
        }
        return nil
    }

    /// Seat-colored avatar fallbacks — green/gold/blue/red rotation.
    static func seatColor(_ seat: Int?) -> Color {
        switch ((seat ?? 1) - 1) % 4 {
        case 0: .sticksGreen
        case 1: .sticksGold
        case 2: Color(red: 2 / 255, green: 132 / 255, blue: 199 / 255)
        default: .sticksError
        }
    }
}
