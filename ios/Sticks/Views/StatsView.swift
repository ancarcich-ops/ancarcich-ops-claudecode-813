//
//  StatsView.swift
//  Sticks
//
//  Slice 15: the Stats tab — identity header with SHARE, the hero index
//  card, rounds-over-time bars, scoring analysis vs handicap baselines,
//  at-a-glance grid, wins by game, course bests, and logged rounds.
//  Slice 19: index goal (set/clear via the hero pencil) and logged-round
//  delete (creator-only, confirm alert, verbatim 403 messages).
//  Slice 22: bar score labels + per-round HI reference ticks on the
//  chart, the baseline selector moved atop Scoring analysis (with an HI
//  option), and remove-my-score on rounds the caller didn't create.
//  Slice 25: web-parity chart + scoring analysis — the compact VS HI
//  picker (shared by both headers), a continuous dotted baseline across
//  the chart, strokes-gained par cards, and track+triangle distribution
//  rows.
//

import SwiftUI

struct StatsView: View {
    let user: User
    let session: SessionStore
    var tabSelection: Binding<SticksTab>? = nil

    @State private var viewModel = StatsViewModel()
    @State private var baselineSelection: BaselineSelection = .hcp(10)

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
                        index: stats.index,
                        baselines: viewModel.baselines,
                        selection: $baselineSelection
                    )
                }

                if stats.distribution.totalHolesPlayed > 0 {
                    ScoringAnalysisCard(
                        stats: stats,
                        baselines: viewModel.baselines,
                        selection: $baselineSelection
                    )
                }

                if stats.matchesPlayed > 0 {
                    AtAGlanceGrid(stats: stats)
                    WinsByGameGrid(wins: stats.winsByGame)
                }

                if !stats.courseRecords.isEmpty {
                    CourseBestsCard(records: stats.courseRecords)
                }

                if !stats.rounds.isEmpty {
                    LoggedRoundsCard(
                        rounds: stats.rounds,
                        currentUserId: user.id,
                        onDelete: { round in
                            await viewModel.deleteRound(matchId: round.matchId, session: session)
                        },
                        onRemoveScores: { round in
                            await viewModel.removeMyScores(matchId: round.matchId, session: session)
                        }
                    )
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

private struct StatsSectionCard<Content: View, Accessory: View>: View {
    let title: String
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(SticksFont.display(13, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer(minLength: 0)

                accessory
            }

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

extension StatsSectionCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, accessory: { EmptyView() }, content: content)
    }
}

// MARK: - Baseline selection

/// A fixed comparison handicap, or the player's own index ("HI") —
/// shared by the chart and the scoring analysis so both stay in sync.
private enum BaselineSelection: Equatable {
    case hcp(Int)
    case myIndex
}

/// The compact "VS HI [10 ▾]" control — a bordered capsule showing the
/// selected comparison handicap; tapping opens a menu of the fixed
/// baselines plus HI (the player's own index). Selection applies
/// instantly — the baselines are already local.
private struct BaselinePickerControl: View {
    @Binding var selection: BaselineSelection
    let baselines: [StatsBaseline]
    let hasIndex: Bool

    private var selectedLabel: String {
        switch selection {
        case .hcp(let value): return "\(value)"
        case .myIndex: return "HI"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("VS HI")
                .font(SticksFont.mono(9))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)

            Menu {
                ForEach(baselines.sorted { $0.hcp < $1.hcp }) { entry in
                    Button {
                        selection = .hcp(entry.hcp)
                    } label: {
                        if selection == .hcp(entry.hcp) {
                            Label("\(entry.hcp)", systemImage: "checkmark")
                        } else {
                            Text("\(entry.hcp)")
                        }
                    }
                }

                if hasIndex {
                    Button {
                        selection = .myIndex
                    } label: {
                        if selection == .myIndex {
                            Label("HI — my index", systemImage: "checkmark")
                        } else {
                            Text("HI — my index")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedLabel)
                        .font(SticksFont.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksGreen)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.sticksFaint)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.rect)
            }
            .accessibilityLabel("Comparison handicap")
        }
    }
}

// MARK: - Rounds over time

/// Vertical accent-green bars, one per round — height ∝ |vsPar| — each
/// carrying its vs-par score. A dark-green dotted baseline weaves across
/// the chart at every round's expected vs-par for the selected
/// comparison handicap (18-hole expectation scaled to that round's
/// holes). Control row, sparse month labels, and a legend underneath.
private struct RoundsOverTimeCard: View {
    /// Chronological, capped to the last ~20 by the caller.
    let rounds: [LoggedRound]
    let index: Double?
    let baselines: [StatsBaseline]
    @Binding var selection: BaselineSelection

    private let chartHeight: CGFloat = 84
    /// Headroom above the tallest bar for its score label.
    private let labelBand: CGFloat = 13
    private let barSpacing: CGFloat = 3

    /// The handicap the dotted baseline tracks — the player's own index
    /// for HI.
    private var targetHcp: Double? {
        switch selection {
        case .hcp(let value): return Double(value)
        case .myIndex: return index
        }
    }

    /// Bars AND the baseline share one scale so everything fits.
    private var maxAbs: Double {
        let bars = rounds.map { Double(abs($0.vsPar)) }.max() ?? 1
        let line = rounds.compactMap { expectedVsPar($0) }.max() ?? 0
        return max(bars, line, 1)
    }

    private var recentAvg: Double? {
        guard !rounds.isEmpty else { return nil }
        return Double(rounds.reduce(0) { $0 + $1.vsPar }) / Double(rounds.count)
    }

    /// The legend's baseline name — the fixed handicap, or the player's
    /// own index for HI.
    private var baselineName: String? {
        switch selection {
        case .hcp(let value): return "\(value)"
        case .myIndex: return index.map { String(format: "%.1f", $0) }
        }
    }

    var body: some View {
        StatsSectionCard(title: "Rounds over time") {
            Text("vs par · lower is better")
                .font(SticksFont.sans(11))
                .foregroundStyle(Color.sticksFaint)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                controlRow

                VStack(spacing: 6) {
                    chart
                    monthLabels
                }

                if hasBaseline, let baselineName {
                    Text("Dotted line = \(baselineName) HI baseline")
                        .font(SticksFont.mono(9))
                        .kerning(0.4)
                        .foregroundStyle(Color.sticksFaint)
                }
            }
        }
    }

    private var hasBaseline: Bool {
        !baselines.isEmpty && targetHcp != nil
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Text("\(rounds.count) ROUNDS")
                .font(SticksFont.mono(9))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)

            Spacer(minLength: 4)

            if !baselines.isEmpty {
                BaselinePickerControl(
                    selection: $selection,
                    baselines: baselines,
                    hasIndex: index != nil
                )
            }

            Spacer(minLength: 4)

            if let recentAvg {
                (
                    Text("recent avg ")
                        .foregroundStyle(Color.sticksFaint)
                    + Text(String(format: "%+.1f", recentAvg))
                        .foregroundStyle(Color.sticksInk)
                )
                .font(SticksFont.mono(9))
                .kerning(0.4)
            }
        }
    }

    private var chart: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(rounds) { round in
                    column(round)
                }
            }

            if hasBaseline {
                baselineLine
            }
        }
        .frame(height: chartHeight + labelBand, alignment: .bottom)
    }

    /// One accent-green bar with its score label riding the top.
    private func column(_ round: LoggedRound) -> some View {
        let height = barHeight(round.vsPar)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.sticksGreen)
                .frame(height: height)
                .frame(maxWidth: .infinity)

            Text(StatsFormat.vsPar(round.vsPar))
                .font(SticksFont.mono(7.5))
                .monospacedDigit()
                .foregroundStyle(labelColor(round.vsPar))
                .fixedSize()
                .offset(y: -(height + 3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight + labelBand, alignment: .bottom)
        .allowsHitTesting(false)
    }

    /// The continuous dotted baseline — one point per round at
    /// targetHcp × (holesPlayed / 18), connected across the chart so a
    /// 9-hole round's expectation dips to about half an 18-hole one's.
    private var baselineLine: some View {
        GeometryReader { geo in
            let count = max(rounds.count, 1)
            let columnWidth = (geo.size.width - barSpacing * CGFloat(count - 1)) / CGFloat(count)
            Path { path in
                var started = false
                for (position, round) in rounds.enumerated() {
                    guard let expected = expectedVsPar(round) else { continue }
                    let x = CGFloat(position) * (columnWidth + barSpacing) + columnWidth / 2
                    let y = geo.size.height - lineOffset(expected)
                    if started {
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.move(to: CGPoint(x: x, y: y))
                        started = true
                    }
                }
            }
            .stroke(
                Color.sticksGreenDark,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5])
            )
        }
        .allowsHitTesting(false)
    }

    /// targetHcp × (holesPlayed / 18) — the expectation scales with the
    /// round length. Holes-scaled only (no per-round slope/rating is
    /// stored) — course difficulty shows up naturally in the bar height.
    private func expectedVsPar(_ round: LoggedRound) -> Double? {
        guard let targetHcp, targetHcp >= 0, round.holesPlayed > 0 else { return nil }
        return targetHcp * Double(round.holesPlayed) / 18
    }

    private func lineOffset(_ expected: Double) -> CGFloat {
        min(CGFloat(expected / maxAbs) * chartHeight, chartHeight - 1)
    }

    /// Labels keep their quality color even though bars are uniform:
    /// over par green, under par gold, even par mute (readable on cream).
    private func labelColor(_ vsPar: Int) -> Color {
        if vsPar > 0 { return .sticksGreen }
        if vsPar < 0 { return .sticksGold }
        return .sticksMuted
    }

    private func barHeight(_ vsPar: Int) -> CGFloat {
        guard vsPar != 0 else { return 3 }
        return max(3, CGFloat(Double(abs(vsPar)) / maxAbs) * chartHeight)
    }

    /// Sparse month labels — only where the month changes.
    private var monthLabels: some View {
        HStack(alignment: .top, spacing: barSpacing) {
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

// MARK: - Scoring analysis

/// Strokes-gained par cards + track-and-triangle distribution rows,
/// compared against a selectable handicap baseline. The compact VS HI
/// picker sits in the header; "HI" compares against the player's own
/// index. Selection is shared with the chart above.
private struct ScoringAnalysisCard: View {
    let stats: PlayerStats
    let baselines: [StatsBaseline]
    @Binding var selection: BaselineSelection

    /// The handicap the selection points at — the player's own index
    /// for HI.
    private var targetHcp: Double? {
        switch selection {
        case .hcp(let value): return Double(value)
        case .myIndex: return stats.index
        }
    }

    private var baseline: StatsBaseline? {
        guard let targetHcp else { return nil }
        return baselines.min {
            abs(Double($0.hcp) - targetHcp) < abs(Double($1.hcp) - targetHcp)
        }
    }

    /// The footer's baseline name — the fixed handicap, or the player's
    /// own index for HI.
    private var baselineName: String {
        switch selection {
        case .hcp(let value): return "\(value)"
        case .myIndex:
            return stats.index.map { String(format: "%.1f", $0) } ?? "HI"
        }
    }

    var body: some View {
        StatsSectionCard(title: "Scoring analysis") {
            if !baselines.isEmpty {
                BaselinePickerControl(
                    selection: $selection,
                    baselines: baselines,
                    hasIndex: stats.index != nil
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    parCard(title: "PAR 3S", bucket: stats.par3, expected: baseline?.avgScores.par3)
                    parCard(title: "PAR 4S", bucket: stats.par4, expected: baseline?.avgScores.par4)
                    parCard(title: "PAR 5S", bucket: stats.par5, expected: baseline?.avgScores.par5)
                }

                distributionRows

                if baseline != nil {
                    Text("Per 18 holes vs a \(baselineName) HI baseline. Triangle = baseline, bar = your average.")
                        .font(SticksFont.sans(11))
                        .foregroundStyle(Color.sticksFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Par cards

    /// "PAR 3S / 4.0 / Avg. Score / -0.5 SG / Hole" — strokes gained per
    /// hole vs the baseline (baseline expected avg − player avg).
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

            Text("Avg. Score")
                .font(SticksFont.sans(10))
                .foregroundStyle(Color.sticksMuted)

            if let sg = strokesGained(bucket: bucket, expected: expected) {
                Text(String(format: "%+.1f SG / Hole", sg))
                    .font(SticksFont.mono(9))
                    .kerning(0.2)
                    .foregroundStyle(sgColor(sg))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.sticksPanel2)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func strokesGained(bucket: ParBucket, expected: Double?) -> Double? {
        guard let avg = bucket.avgScore, let expected, expected > 0 else { return nil }
        return expected - avg
    }

    /// Gaining strokes reads green, losing reads danger; a rounding-flat
    /// value stays neutral so "+0.0" never screams either way.
    private func sgColor(_ sg: Double) -> Color {
        if sg > 0.049 { return .sticksGreen }
        if sg < -0.049 { return .sticksError }
        return .sticksMuted
    }

    // MARK: Distribution

    private struct DistributionKind: Identifiable {
        let label: String
        let player: Double
        let expected: Double
        /// Birdies/pars: more is better. Bogeys/doubles: fewer is better.
        let moreIsBetter: Bool
        var id: String { label }
    }

    private var kinds: [DistributionKind] {
        let player = stats.distribution.per18
        let expected = baseline?.distribution ?? .zero
        return [
            DistributionKind(label: "BIRDIES−", player: player.birdiesOrBetter, expected: expected.birdiesOrBetter, moreIsBetter: true),
            DistributionKind(label: "PARS", player: player.pars, expected: expected.pars, moreIsBetter: true),
            DistributionKind(label: "BOGEYS", player: player.bogeys, expected: expected.bogeys, moreIsBetter: false),
            DistributionKind(label: "DOUBLES+", player: player.doublesOrWorse, expected: expected.doublesOrWorse, moreIsBetter: false),
        ]
    }

    /// Shared scale — the max count across rows nearly fills the track.
    private var scaleMax: Double {
        max(kinds.flatMap { [$0.player, $0.expected] }.max() ?? 1, 0.5) * 1.05
    }

    private var distributionRows: some View {
        VStack(spacing: 6) {
            ForEach(kinds) { kind in
                distributionRow(kind)
            }
        }
    }

    /// One track row: a light tan full-width track, the player's colored
    /// bar over it (green when beating the baseline, danger when
    /// trailing), the player's count above the bar end, and a triangle +
    /// number marking the baseline's position on the track.
    private func distributionRow(_ kind: DistributionKind) -> some View {
        let showBaseline = baseline != nil
        return HStack(spacing: 10) {
            Text(kind.label)
                .font(SticksFont.mono(9.5))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
                .frame(width: 66, alignment: .leading)

            GeometryReader { geo in
                let width = geo.size.width
                let barEnd = max(x(kind.player, in: width), 3)
                let baselineX = min(max(x(kind.expected, in: width), 6), width - 6)

                ZStack(alignment: .topLeading) {
                    Text(String(format: "%.1f", kind.player))
                        .font(SticksFont.mono(9.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksInk)
                        .position(x: min(max(barEnd, 10), width - 10), y: 5)

                    Capsule()
                        .fill(Color.sticksHairline.opacity(0.45))
                        .frame(width: width, height: 6)
                        .position(x: width / 2, y: 16)

                    Capsule()
                        .fill(barColor(kind))
                        .frame(width: barEnd, height: 6)
                        .position(x: barEnd / 2, y: 16)

                    if showBaseline {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.sticksMuted)
                            .position(x: baselineX, y: 24)

                        Text(String(format: "%.1f", kind.expected))
                            .font(SticksFont.mono(8.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.sticksFaint)
                            .position(x: baselineX, y: 33)
                    }
                }
            }
            .frame(height: showBaseline ? 38 : 22)
        }
    }

    private func x(_ value: Double, in width: CGFloat) -> CGFloat {
        CGFloat(value / scaleMax) * width
    }

    /// Green when beating the baseline for this category, danger when
    /// trailing it (no baseline reads neutral green).
    private func barColor(_ kind: DistributionKind) -> Color {
        guard baseline != nil else { return .sticksGreen }
        let beating = kind.moreIsBetter
            ? kind.player >= kind.expected
            : kind.player <= kind.expected
        return beating ? .sticksGreen : .sticksError
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

/// Round history, newest first — tap pushes the match detail (scores are
/// editable there). Rounds the caller created get … → Delete round
/// (removes it for everyone); rounds they're merely in get … → Remove my
/// score (their scores only). Both confirm first; 403s surface the
/// server's message verbatim.
private struct LoggedRoundsCard: View {
    let rounds: [LoggedRound]
    let currentUserId: String
    /// DELETE /matches/:id — returns a user-facing error, or nil.
    let onDelete: (LoggedRound) async -> String?
    /// DELETE /matches/:id/my-scores — returns a user-facing error, or nil.
    let onRemoveScores: (LoggedRound) async -> String?

    private struct PendingAction: Identifiable {
        enum Kind { case deleteRound, removeMyScores }

        let kind: Kind
        let round: LoggedRound

        var id: String { round.matchId }
    }

    @State private var pendingAction: PendingAction?
    @State private var busyId: String?
    @State private var actionError: String?

    var body: some View {
        StatsSectionCard(title: "Logged rounds") {
            VStack(spacing: 0) {
                ForEach(Array(rounds.reversed().enumerated()), id: \.element.id) { position, round in
                    if position > 0 {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
                    HStack(spacing: 2) {
                        NavigationLink(value: matchSummary(for: round)) {
                            row(round)
                        }
                        .buttonStyle(.plain)

                        if busyId == round.matchId {
                            ProgressView()
                                .tint(Color.sticksGreen)
                                .frame(width: 30, height: 30)
                        } else {
                            actionsMenu(round)
                        }
                    }
                }
            }
        }
        .alert(
            pendingAction?.kind == .removeMyScores ? "Remove your score?" : "Delete this round?",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(
                action.kind == .removeMyScores ? "Remove" : "Delete",
                role: .destructive
            ) {
                perform(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            switch action.kind {
            case .deleteRound:
                Text("\(action.round.courseName) will be removed for everyone in the match.")
            case .removeMyScores:
                Text("This removes your scores from this round. Other players keep theirs.")
            }
        }
        .alert(
            "That didn't work",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Actions

    /// Full delete is creator-only — trust the server flag, fall back to
    /// the id. Everyone else gets remove-my-score.
    private func isCreator(_ round: LoggedRound) -> Bool {
        round.createdByMe || round.creatorId == currentUserId
    }

    private func actionsMenu(_ round: LoggedRound) -> some View {
        Menu {
            if isCreator(round) {
                Button(role: .destructive) {
                    pendingAction = PendingAction(kind: .deleteRound, round: round)
                } label: {
                    Label("Delete round", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    pendingAction = PendingAction(kind: .removeMyScores, round: round)
                } label: {
                    Label("Remove my score", systemImage: "minus.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sticksFaint)
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .accessibilityLabel("Round options")
    }

    private func perform(_ action: PendingAction) {
        busyId = action.round.matchId
        Task {
            let error: String?
            switch action.kind {
            case .deleteRound:
                error = await onDelete(action.round)
            case .removeMyScores:
                error = await onRemoveScores(action.round)
            }
            busyId = nil
            if let error {
                actionError = error
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
