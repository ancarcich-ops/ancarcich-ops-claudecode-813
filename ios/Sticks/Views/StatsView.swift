//
//  StatsView.swift
//  Sticks
//
//  Slice 15: the Stats tab — identity header with SHARE, the hero index
//  card, rounds-over-time bars, scoring analysis vs handicap baselines,
//  at-a-glance grid, wins by game, course bests, and logged rounds
//  (tap → match detail, read-only on iOS).
//

import SwiftUI

struct StatsView: View {
    let user: User
    let session: SessionStore
    var tabSelection: Binding<SticksTab>? = nil

    @State private var viewModel = StatsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    loadingView
                case .failed(let message):
                    failedView(message)
                case .empty:
                    emptyView
                case .loaded:
                    if let stats = viewModel.stats {
                        content(stats)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let tabSelection {
                    SticksTabBar(selection: tabSelection)
                }
            }
            .navigationDestination(for: MatchSummary.self) { match in
                MatchDetailView(match: match, session: session)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load(session: session)
        }
    }

    // MARK: - Content

    private func content(_ stats: PlayerStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identityHeader(stats)

                StatsHeroCard(stats: stats)

                if stats.rounds.count >= 2 {
                    RoundsOverTimeCard(
                        rounds: Array(stats.rounds.suffix(20)),
                        index: stats.index
                    )
                }

                if stats.distribution.totalHolesPlayed > 0 {
                    ScoringAnalysisCard(stats: stats, baselines: viewModel.baselines)
                }

                if stats.matchesPlayed > 0 {
                    AtAGlanceGrid(stats: stats)
                    WinsByGameGrid(wins: stats.winsByGame)
                }

                if !stats.courseRecords.isEmpty {
                    CourseBestsCard(records: stats.courseRecords)
                }

                if !stats.rounds.isEmpty {
                    LoggedRoundsCard(rounds: stats.rounds)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(session: session)
        }
    }

    // MARK: - Identity header

    private func identityHeader(_ stats: PlayerStats) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            (
                Text(displayName(stats))
                    .font(SticksFont.display(25, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                + Text(" · personal stats")
                    .font(SticksFont.display(17, weight: .regular))
                    .foregroundStyle(Color.sticksMuted)
            )
            .lineLimit(2)

            Spacer(minLength: 8)

            sharePill(stats)
        }
    }

    private func displayName(_ stats: PlayerStats) -> String {
        stats.displayName.isEmpty ? user.displayName : stats.displayName
    }

    private func sharePill(_ stats: PlayerStats) -> some View {
        let username = stats.username.isEmpty ? user.username : stats.username
        let url = URL(string: "https://sticks-golf.vercel.app/u/\(username)")!
        return ShareLink(item: url) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text("SHARE")
                    .font(SticksFont.mono(10))
                    .kerning(1)
            }
            .foregroundStyle(Color.sticksGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.sticksCard)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading stats…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text("Nothing logged yet")
                .font(SticksFont.display(24))
                .foregroundStyle(Color.sticksInk)
            Text("Your stats fill in as rounds wrap up.")
                .font(SticksFont.sans(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.horizontal, 40)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.load(session: session) }
            } label: {
                Text("Try Again")
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksCream)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}

// MARK: - Section card shell

private struct StatsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }
}

// MARK: - Rounds over time

/// Vertical bars, one per round — height ∝ |vsPar|, over par in accent
/// green, under par in gold, zero a 3pt nub — with a dotted line at the
/// current index labeled "HI" and sparse month labels underneath.
private struct RoundsOverTimeCard: View {
    /// Chronological, capped to the last ~20 by the caller.
    let rounds: [LoggedRound]
    let index: Double?

    private let chartHeight: CGFloat = 84

    private var maxAbs: Double {
        max(rounds.map { Double(abs($0.vsPar)) }.max() ?? 1, 1)
    }

    var body: some View {
        StatsSectionCard(title: "Rounds over time") {
            VStack(spacing: 6) {
                chart
                monthLabels
            }
        }
    }

    private var chart: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(rounds) { round in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(round.vsPar))
                        .frame(height: barHeight(round.vsPar))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight, alignment: .bottom)

            if let index, index > 0 {
                indexLine(at: index)
            }
        }
        .frame(height: chartHeight)
    }

    private func indexLine(at index: Double) -> some View {
        let offset = min(CGFloat(index / maxAbs) * chartHeight, chartHeight - 4)
        return HStack(spacing: 4) {
            DottedLine()
                .stroke(
                    Color.sticksFaint,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                .frame(height: 1)

            Text("HI")
                .font(SticksFont.mono(8))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
        }
        .offset(y: -offset)
        .allowsHitTesting(false)
    }

    private func barColor(_ vsPar: Int) -> Color {
        if vsPar > 0 { return .sticksGreen }
        if vsPar < 0 { return .sticksGold }
        return .sticksFaint
    }

    private func barHeight(_ vsPar: Int) -> CGFloat {
        guard vsPar != 0 else { return 3 }
        return max(3, CGFloat(Double(abs(vsPar)) / maxAbs) * chartHeight)
    }

    /// Sparse month labels — only where the month changes.
    private var monthLabels: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(rounds.enumerated()), id: \.element.id) { position, round in
                Group {
                    if let label = monthLabel(at: position) {
                        Text(label)
                            .font(SticksFont.mono(8))
                            .kerning(0.4)
                            .foregroundStyle(Color.sticksFaint)
                            .fixedSize()
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12, alignment: .top)
        .clipped()
    }

    private func monthLabel(at position: Int) -> String? {
        guard let date = rounds[position].scheduledAt else { return nil }
        let month = Calendar.current.component(.month, from: date)
        if position > 0,
           let previous = rounds[position - 1].scheduledAt,
           Calendar.current.component(.month, from: previous) == month {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }
}

private struct DottedLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Scoring analysis

/// Par-bucket cards + distribution bars, compared against a selectable
/// handicap baseline (local state only, default 10).
private struct ScoringAnalysisCard: View {
    let stats: PlayerStats
    let baselines: [StatsBaseline]

    @State private var selectedHcp: Int = 10

    private var baseline: StatsBaseline? {
        baselines.first { $0.hcp == selectedHcp }
            ?? baselines.min { abs($0.hcp - selectedHcp) < abs($1.hcp - selectedHcp) }
    }

    var body: some View {
        StatsSectionCard(title: "Scoring analysis") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    parCard(title: "PAR 3S", bucket: stats.par3, expected: baseline?.avgScores.par3)
                    parCard(title: "PAR 4S", bucket: stats.par4, expected: baseline?.avgScores.par4)
                    parCard(title: "PAR 5S", bucket: stats.par5, expected: baseline?.avgScores.par5)
                }

                distributionRows

                if !baselines.isEmpty {
                    baselinePicker
                }
            }
        }
    }

    // MARK: Par cards

    private func parCard(title: String, bucket: ParBucket, expected: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SticksFont.mono(9))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)

            Text(bucket.avgScore.map { String(format: "%.1f", $0) } ?? "—")
                .font(SticksFont.display(20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)

            Text(vsParLine(bucket.avgVsPar))
                .font(SticksFont.mono(10))
                .kerning(0.4)
                .foregroundStyle(vsParColor(bucket.avgVsPar))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let expected, expected > 0 {
                Text("\(selectedHcp) HI: \(String(format: "%.1f", expected))")
                    .font(SticksFont.mono(9))
                    .kerning(0.4)
                    .foregroundStyle(Color.sticksFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.sticksPanel2)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func vsParLine(_ avgVsPar: Double?) -> String {
        guard let avgVsPar else { return "—" }
        return String(format: "%+.1f VS PAR", avgVsPar)
    }

    private func vsParColor(_ avgVsPar: Double?) -> Color {
        guard let avgVsPar else { return .sticksFaint }
        if avgVsPar < 0 { return .sticksGreen }
        if avgVsPar > 0 { return .sticksError }
        return .sticksMuted
    }

    // MARK: Distribution

    private struct DistributionKind: Identifiable {
        let label: String
        let player: Double
        let expected: Double
        var id: String { label }
    }

    private var kinds: [DistributionKind] {
        let player = stats.distribution.per18
        let expected = baseline?.distribution ?? .zero
        return [
            DistributionKind(label: "BIRDIES−", player: player.birdiesOrBetter, expected: expected.birdiesOrBetter),
            DistributionKind(label: "PARS", player: player.pars, expected: expected.pars),
            DistributionKind(label: "BOGEYS", player: player.bogeys, expected: expected.bogeys),
            DistributionKind(label: "DOUBLES+", player: player.doublesOrWorse, expected: expected.doublesOrWorse),
        ]
    }

    private var distributionRows: some View {
        let maxValue = max(kinds.flatMap { [$0.player, $0.expected] }.max() ?? 1, 0.1)
        return VStack(spacing: 10) {
            ForEach(kinds) { kind in
                distributionRow(kind, maxValue: maxValue)
            }
        }
    }

    private func distributionRow(_ kind: DistributionKind, maxValue: Double) -> some View {
        HStack(spacing: 10) {
            Text(kind.label)
                .font(SticksFont.mono(9.5))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
                .frame(width: 66, alignment: .leading)

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule()
                        .fill(Color.sticksGreen)
                        .frame(width: barWidth(kind.player, maxValue: maxValue, available: geo.size.width), height: 4)
                    Capsule()
                        .fill(Color.sticksHairline)
                        .frame(width: barWidth(kind.expected, maxValue: maxValue, available: geo.size.width), height: 4)
                }
            }
            .frame(height: 11)

            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.1f", kind.player))
                    .font(SticksFont.mono(10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)
                Text(String(format: "%.1f", kind.expected))
                    .font(SticksFont.mono(9))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksFaint)
            }
            .frame(width: 36, alignment: .trailing)
        }
    }

    private func barWidth(_ value: Double, maxValue: Double, available: CGFloat) -> CGFloat {
        max(2, CGFloat(value / maxValue) * available)
    }

    // MARK: Baseline picker

    private var baselinePicker: some View {
        HStack(spacing: 6) {
            Text("VS")
                .font(SticksFont.mono(9))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)

            ForEach(baselines.sorted { $0.hcp < $1.hcp }) { entry in
                let isSelected = baseline?.hcp == entry.hcp
                Button {
                    selectedHcp = entry.hcp
                } label: {
                    Text("\(entry.hcp)")
                        .font(SticksFont.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.sticksGreen : Color.sticksFaint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.sticksGreen.opacity(0.1) : .clear)
                        .clipShape(.capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }

            Text("HI")
                .font(SticksFont.mono(9))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - At a glance

private struct AtAGlanceGrid: View {
    let stats: PlayerStats

    var body: some View {
        StatsSectionCard(title: "At a glance") {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                cell(label: "MATCHES", value: "\(stats.matchesPlayed)")
                cell(label: "TOTAL WINS", value: "\(stats.totalWins)", valueColor: .sticksGreen)
                cell(label: "WIN RATE", value: winRateText, sub: mainWinsText)
                cell(
                    label: "CURRENT STREAK",
                    value: "\(stats.currentMainStreak)",
                    sub: "BEST \(stats.bestMainStreak)"
                )
            }
        }
    }

    private var winRateText: String {
        guard stats.matchesPlayed > 0 else { return "0%" }
        let rate = Double(stats.mainWins) / Double(stats.matchesPlayed) * 100
        return "\(Int(rate.rounded()))%"
    }

    private var mainWinsText: String {
        stats.mainWins == 1 ? "1 MAIN WIN" : "\(stats.mainWins) MAIN WINS"
    }

    private func cell(
        label: String,
        value: String,
        sub: String? = nil,
        valueColor: Color = .sticksInk
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(SticksFont.mono(9))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(SticksFont.display(22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)

            if let sub {
                Text(sub)
                    .font(SticksFont.mono(9))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.sticksPanel2)
        .clipShape(.rect(cornerRadius: 10))
    }
}

// MARK: - Wins by game

private struct WinsByGameGrid: View {
    let wins: WinsByGame

    private var chips: [(label: String, count: Int)] {
        [
            ("MAIN", wins.main),
            ("STAPLE", wins.stableford),
            ("SKINS", wins.skins),
            ("NASSAU", wins.nassau),
            ("BBB", wins.bbb),
            ("SNAKE", wins.snake),
            ("WOLF", wins.wolf),
        ]
    }

    var body: some View {
        StatsSectionCard(title: "Wins by game") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(chips, id: \.label) { chip in
                    chipView(label: chip.label, count: chip.count)
                }
            }
        }
    }

    private func chipView(label: String, count: Int) -> some View {
        let earned = count > 0
        return VStack(spacing: 1) {
            Text("\(count)")
                .font(SticksFont.display(16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(earned ? Color.sticksGreen : Color.sticksFaint)

            Text(label)
                .font(SticksFont.mono(9))
                .kerning(0.6)
                .foregroundStyle(earned ? Color.sticksGreen : Color.sticksFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(earned ? Color.sticksGreen.opacity(0.1) : Color.sticksPanel2.opacity(0.6))
        .clipShape(.rect(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(earned ? Color.sticksGreen.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

// MARK: - Course bests

private struct CourseBestsCard: View {
    let records: [StatsCourseRecord]

    /// The single lowest-gross record gets the gold medal glyph.
    private var medalId: String? {
        records
            .filter { $0.gross != nil }
            .min { ($0.gross ?? .max) < ($1.gross ?? .max) }?
            .id
    }

    var body: some View {
        StatsSectionCard(title: "Course bests") {
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { position, record in
                    if position > 0 {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
                    row(record)
                }
            }
        }
    }

    private func row(_ record: StatsCourseRecord) -> some View {
        HStack(spacing: 8) {
            if record.id == medalId {
                Image(systemName: "medal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksGold)
            }

            Text(record.courseName)
                .font(SticksFont.sans(13, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            scoreText(record)
                .font(SticksFont.mono(12))
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }

    private func scoreText(_ record: StatsCourseRecord) -> Text {
        var pieces: [Text] = []
        if let gross = record.gross {
            pieces.append(Text("\(gross) GROSS").foregroundStyle(Color.sticksMuted))
        }
        if let net = record.net {
            pieces.append(
                Text("\(net, specifier: "%.1f") NET").foregroundStyle(Color.sticksGreen)
            )
        }
        guard var combined = pieces.first else {
            return Text("—").foregroundStyle(Color.sticksFaint)
        }
        for piece in pieces.dropFirst() {
            combined = combined + Text(" · ").foregroundStyle(Color.sticksFaint) + piece
        }
        return combined
    }
}

// MARK: - Logged rounds

/// Read-only round history, newest first — tap pushes the match detail.
private struct LoggedRoundsCard: View {
    let rounds: [LoggedRound]

    var body: some View {
        StatsSectionCard(title: "Logged rounds") {
            VStack(spacing: 0) {
                ForEach(Array(rounds.reversed().enumerated()), id: \.element.id) { position, round in
                    if position > 0 {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
                    NavigationLink(value: matchSummary(for: round)) {
                        row(round)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ round: LoggedRound) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text(dateText(round.scheduledAt))
                    .font(SticksFont.mono(10))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksFaint)
            }

            Spacer(minLength: 8)

            scoreChip(round.vsPar)
        }
        .padding(.vertical, 9)
        .contentShape(.rect)
    }

    /// Same coloring as the hero's BEST cell.
    private func scoreChip(_ vsPar: Int) -> some View {
        let color = StatsFormat.vsParColor(vsPar)
        return Text(StatsFormat.vsPar(vsPar))
            .font(SticksFont.mono(12))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color == .sticksInk ? Color.sticksPanel2 : color.opacity(0.1))
            .clipShape(.rect(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(color == .sticksInk ? Color.sticksHairline : color.opacity(0.3), lineWidth: 1)
            )
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date).uppercased()
    }

    /// Minimal summary to seed the detail screen — everything visible in
    /// its header is replaced as soon as GET /matches/:id loads.
    private func matchSummary(for round: LoggedRound) -> MatchSummary {
        MatchSummary(
            id: round.matchId,
            courseName: round.courseName,
            scheduledAt: round.scheduledAt ?? .now,
            completedAt: nil,
            status: .completed,
            holes: round.holesPlayed > 9 ? 18 : 9,
            startingHole: 1,
            scoringMode: "GROSS",
            format: "STROKE_PLAY",
            pars: [],
            probabilities: [:],
            myMatchPlayerId: nil,
            groupId: nil,
            players: []
        )
    }
}
