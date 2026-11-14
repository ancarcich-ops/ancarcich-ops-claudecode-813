//
//  RecapTabView.swift
//  Sticks
//
//  Slice 101: the post-round recap. Two surfaces, one server-computed
//  payload (GET /matches/:id/recap):
//    - RecapHeadlineCard — fires once per person per round when the
//      round goes final. Headline only; tapping through opens the tab.
//    - RecapTabView — the whole thing, on the round screen. Default tab
//      on a finished round.
//
//  The server computes the maths (naming scores against par, walking
//  the real routing, allocating strokes by position); the app lays it
//  out. Numbers tie out by contract — if they don't, that's a server
//  bug to report, not to patch around.
//
//  House language (the web went through two rounds of correction):
//  "Straight up" / "Handicap", never bare "gross"/"net"; "Tied", never
//  "halved"; signed figures always labelled so a +2 against a +16 can't
//  read as the same unit.
//

import SwiftUI

// MARK: - Formatting

/// Shared recap formatting — signed vs-par text and its colour.
enum RecapFormat {
    /// "+3" over par, "-1" under, "E" at level — the app's convention.
    static func vsPar(_ value: Int) -> String {
        value == 0 ? "E" : (value > 0 ? "+\(value)" : "\(value)")
    }

    static func vsPar(_ value: Double) -> String {
        if value == 0 { return "E" }
        let rounded = (value * 10).rounded() / 10
        return rounded > 0 ? "+\(String(format: "%.1f", rounded))" : String(format: "%.1f", rounded)
    }

    /// Red over par, green under, muted at level.
    static func vsParColor(_ value: Int) -> Color {
        value > 0 ? .sticksError : (value < 0 ? .sticksGreen : .sticksMuted)
    }

    /// A stretch of holes in playing order, named for speech: any
    /// stretch crossing the turn is "17 through 2", never "17–2" —
    /// so every stretch says "through" and none misleads.
    static func stretchText(_ arc: [RecapArcPoint], _ stretch: RecapStretch) -> String? {
        guard arc.indices.contains(stretch.from) else { return nil }
        let to = min(stretch.to, arc.count - 1)
        guard to >= stretch.from, to < arc.count else { return nil }
        let firstHole = arc[stretch.from].hole
        let lastHole = arc[to].hole
        let direction = stretch.vsPar < 0
            ? "\(-stretch.vsPar) UNDER"
            : (stretch.vsPar > 0 ? "\(stretch.vsPar) OVER" : "LEVEL")
        return firstHole == lastHole
            ? "HOLE \(firstHole) · \(direction)"
            : "HOLES \(firstHole) THROUGH \(lastHole) · \(direction)"
    }

    static func countLabel(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

// MARK: - Tab

struct RecapTabView: View {
    let recap: RoundRecap
    let detail: MatchDetail

    @Environment(\.openURL) private var openURL
    /// Which opponent's swings are showing — nearest finish first, so
    /// the closest match lands first (that's the one people argue about).
    @State private var swingIndex = 0
    @State private var arcSelection: Int?

    private var payload: RecapBody { recap.recap }
    /// Whether the payload is the caller's own card (history only
    /// exists then; the seat tells a spectator whose round they read).
    private var isOwnSeat: Bool {
        recap.seat.matchPlayerId.isEmpty || recap.seat.matchPlayerId == detail.myMatchPlayerId
    }
    private var settledWithHandicaps: String {
        guard let net = recap.netRecap, let totals = net.totals else { return "" }
        let figure = String(totals.net ?? 0)
        return figure + " (" + RecapFormat.vsPar(totals.netToPar ?? 0) + ")"
    }

    private var isNetRound: Bool { (recap.scoringMode ?? "").uppercased() != "GROSS" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headlineCard
            netRecapLine
            swingsSection
            theRoundSection
            scoringSection
            difficultySection
            historySection
        }
    }

    // MARK: Headline

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isOwnSeat ? "YOUR ROUND" : "\(recap.seat.displayName.uppercased())'S ROUND")
                .font(SticksFont.mono(11))
                .kerning(0.8)
                .foregroundStyle(Color.sticksMuted)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recap.headline.score)
                    .font(SticksFont.display(52, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                if !recap.headline.toPar.isEmpty {
                    Text(recap.headline.toPar)
                        .font(SticksFont.display(22, weight: .semibold))
                        .foregroundStyle(Color.sticksError)
                }
                Spacer(minLength: 0)
            }

            Text(recap.headline.story)
                .font(SticksFont.sans(15))
                .foregroundStyle(Color.sticksInk)
                .fixedSize(horizontal: false, vertical: true)

            if let best = payload.best, let worst = payload.worst {
                RecapArcChart(
                    arc: payload.arc,
                    best: best,
                    worst: worst,
                    selection: $arcSelection
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    /// Where gross and net disagree about who won, the settled result
    /// prints beside the gross one — never hidden behind a toggle.
    private var netRecapLine: some View {
        Group {
            if isNetRound, let net = recap.netRecap, let netTotals = net.totals {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WITH HANDICAPS")
                        .font(SticksFont.mono(10.5))
                        .kerning(0.8)
                        .foregroundStyle(Color.sticksMuted)
                    HStack(spacing: 8) {
                        Text(settledWithHandicaps)
                            .font(SticksFont.sans(13.5, weight: .semibold))
                            .foregroundStyle(RecapFormat.vsParColor(netTotals.netToPar ?? 0))
                        Text("settled with handicaps — where that disagrees with the straight-up result, both are shown below.")
                            .font(SticksFont.sans(12))
                            .foregroundStyle(Color.sticksMuted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.sticksGreen.opacity(0.07))
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sticksGreen.opacity(0.35), lineWidth: 1)
                )
            }
        }
    }

    // MARK: Where the match was won

    @ViewBuilder
    private var swingsSection: some View {
        let swings = payload.swings
        if !swings.isEmpty {
            section("WHERE THE MATCH WAS WON") {
                if swings.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(Array(swings.enumerated()), id: \.offset) { index, swing in
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { swingIndex = index }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(swing.opponentName)
                                    .font(SticksFont.mono(11))
                                    .kerning(0.4)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(swingIndex == index ? Color.sticksGreen : Color.sticksBg)
                                    .foregroundStyle(swingIndex == index ? Color.sticksCream : Color.sticksMuted)
                                    .clipShape(.capsule)
                                    .overlay(
                                        Capsule().stroke(
                                            swingIndex == index ? Color.clear : Color.sticksHairline,
                                            lineWidth: 1
                                        )
                                    )
                            }
                            .buttonStyle(PressableButtonStyle())
                            .accessibilityLabel("Match versus \(swing.opponentName)")
                            .accessibilityAddTraits(swingIndex == index ? .isSelected : [])
                        }
                    }
                }

                if swings.indices.contains(swingIndex) {
                    swingRows(swings[swingIndex])
                }
            }
        }
    }

    private func swingRows(_ swing: RecapSwing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(marginText(swing))
                .font(SticksFont.sans(14, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .padding(.bottom, 10)

            ForEach(Array(swing.holes.enumerated()), id: \.element.position) { _, hole in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("H\(hole.hole)")
                        .font(SticksFont.mono(11))
                        .kerning(0.4)
                        .foregroundStyle(Color.sticksMuted)
                        .frame(width: 30, alignment: .leading)

                    Text("\(hole.yourLabel ?? "\(hole.yourStrokes)") v \(hole.theirLabel ?? "\(hole.theirStrokes)")")
                        .font(SticksFont.sans(12.5))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(swingDirection(hole.swing))
                        .font(SticksFont.mono(11.5, weight: .semibold))
                        .kerning(0.3)
                        .foregroundStyle(hole.swing > 0 ? Color.sticksGreen : Color.sticksError)
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) {
                    Color.sticksHairline.opacity(0.6).frame(height: 1)
                }
            }

            Text(RecapFormat.countLabel(swing.halved, "hole tied", "holes tied"))
                .font(SticksFont.mono(11))
                .kerning(0.4)
                .foregroundStyle(Color.sticksMuted)
                .padding(.top, 10)
        }
    }

    /// "2 your way" / "2 their way" — a signed figure with words
    /// beside it, so it can't be misread as vs-par.
    private func swingDirection(_ swing: Int) -> String {
        if swing > 0 { return "\(swing) YOUR WAY" }
        if swing < 0 { return "\(-swing) THEIR WAY" }
        return "EVEN"
    }

    private func marginText(_ swing: RecapSwing) -> String {
        let across = " across \(swing.comparedHoles) holes"
        if swing.total > 0 { return "You finished \(swing.total) ahead of \(swing.opponentName)\(across)." }
        if swing.total < 0 { return "\(swing.opponentName) finished \(-swing.total) ahead of you\(across)." }
        return "All square with \(swing.opponentName)\(across)."
    }

    // MARK: The round

    @ViewBuilder
    private var theRoundSection: some View {
        if let totals = payload.totals {
            section("THE ROUND") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    totalColumn("HOLES", "\(totals.holesScored ?? 0)")
                    totalColumn("STRAIGHT UP", "\(totals.gross ?? 0)", vsPar: totals.grossToPar ?? 0)
                    totalColumn("HANDICAP", "\(totals.net ?? 0)", vsPar: totals.netToPar ?? 0)
                }

                if let best = payload.best, let worst = payload.worst {
                    RecapArcChart(arc: payload.arc, best: best, worst: worst, selection: $arcSelection)
                }

                if let best = payload.best,
                   let bestText = RecapFormat.stretchText(payload.arc, best) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.sticksGreen).frame(width: 7, height: 7)
                        Text("Best run — \(bestText.lowercased(with: .current))")
                            .font(SticksFont.sans(12))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
                if let worst = payload.worst,
                   let worstText = RecapFormat.stretchText(payload.arc, worst) {
                    HStack(spacing: 6) {
                        // Dashed in the chart; dashed here too — red
                        // alone isn't the cue (colourblindness).
                        Image(systemName: "minus.dashed")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.sticksError)
                        Text("Worst run — \(worstText.lowercased(with: .current))")
                            .font(SticksFont.sans(12))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }
            }
        }
    }

    private func totalColumn(_ label: String, _ value: String, vsPar: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SticksFont.mono(10))
                .kerning(0.7)
                .foregroundStyle(Color.sticksMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(SticksFont.display(24, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                if let vsPar {
                    Text(RecapFormat.vsPar(vsPar))
                        .font(SticksFont.mono(12, weight: .semibold))
                        .foregroundStyle(RecapFormat.vsParColor(vsPar))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Scoring

    @ViewBuilder
    private var scoringSection: some View {
        let distributionRows = distributionChips
        if !distributionRows.isEmpty || !payload.byPar.isEmpty {
            section("SCORING") {
                if !distributionRows.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(distributionRows, id: \.0) { label, count in
                            VStack(spacing: 3) {
                                Text("\(count)")
                                    .font(SticksFont.display(19, weight: .bold))
                                    .foregroundStyle(Color.sticksInk)
                                Text(label)
                                    .font(SticksFont.mono(9))
                                    .kerning(0.5)
                                    .foregroundStyle(Color.sticksMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.sticksBg)
                    .clipShape(.rect(cornerRadius: 10))
                }

                if !payload.byPar.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            byParCell("PAR", header: true, alignment: .leading)
                            byParCell("HOLES", header: true)
                            byParCell("AVG", header: true)
                            byParCell("VS PAR", header: true)
                        }
                        ForEach(payload.byPar, id: \.par) { row in
                            HStack(spacing: 0) {
                                byParCell("PAR \(row.par)", alignment: .leading)
                                byParCell("\(row.holes)")
                                byParCell(row.avgScore.map { String(format: "%.1f", $0) } ?? "—")
                                let vs = row.avgVsPar ?? 0
                                byParCell(
                                    RecapFormat.vsPar(vs),
                                    color: RecapFormat.vsParColor(Int(vs.rounded()))
                                )
                            }
                            .overlay(alignment: .top) {
                                Color.sticksHairline.opacity(0.6).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Only the counts that happened — a row of zeroes is noise.
    private var distributionChips: [(String, Int)] {
        guard let d = payload.distribution else { return [] }
        return [
            ("EAGLES+", d.eaglesOrBetter ?? 0),
            ("BIRDIES", d.birdies ?? 0),
            ("PARS", d.pars ?? 0),
            ("BOGEYS", d.bogeys ?? 0),
            ("DOUBLES", d.doubles ?? 0),
            ("3 OR MORE", d.triplesOrWorse ?? 0),
        ]
        .filter { $0.1 > 0 }
    }

    private func byParCell(
        _ text: String,
        header: Bool = false,
        alignment: Alignment = .trailing,
        color: Color = .sticksInk
    ) -> some View {
        Text(text)
            .font(header ? SticksFont.mono(10) : SticksFont.mono(12))
            .kerning(0.4)
            .foregroundStyle(header ? Color.sticksMuted : color)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.vertical, header ? 6 : 8)
    }

    // MARK: Hard holes vs easy

    @ViewBuilder
    private var difficultySection: some View {
        let rows = payload.difficulty
        if !rows.isEmpty {
            // A course with no stroke index sends an empty array — the
            // section is absent, not empty.
            section("HARD HOLES VS EASY") {
                let maxMagnitude = max(
                    rows.map { abs($0.avgVsPar ?? 0) }.max() ?? 1,
                    0.1
                )
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        let value = row.avgVsPar ?? 0
                        HStack(spacing: 10) {
                            Text(row.label.uppercased())
                                .font(SticksFont.mono(10.5))
                                .kerning(0.5)
                                .foregroundStyle(Color.sticksMuted)
                                .frame(width: 68, alignment: .leading)

                            // Diverging bars from a centre line —
                            // over par right (red), under left (green).
                            GeometryReader { geo in
                                let centre = geo.size.width / 2
                                let halfSpan = geo.size.width / 2 - 4
                                let barWidth = max((abs(value) / maxMagnitude) * halfSpan, 3)
                                ZStack {
                                    // The centre line — level.
                                    Rectangle()
                                        .fill(Color.sticksHairline.opacity(0.6))
                                        .frame(width: 1)
                                        .position(x: centre, y: 8)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(value >= 0 ? Color.sticksError : Color.sticksGreen)
                                        .frame(width: barWidth, height: 14)
                                        .position(
                                            x: value >= 0 ? centre + barWidth / 2 : centre - barWidth / 2,
                                            y: 8
                                        )
                                }
                            }
                            .frame(height: 16)

                            Text(RecapFormat.vsPar(value))
                                .font(SticksFont.mono(12, weight: .semibold))
                                .foregroundStyle(RecapFormat.vsParColor(Int(value.rounded())))
                                .frame(width: 38, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(row.label): \(RecapFormat.vsPar(value)) average against par")
                    }
                }

                Text("The card ranks its holes 1 to 18 by difficulty — 1 is the hardest. This is your average against par in each third.")
                    .font(SticksFont.sans(11.5))
                    .foregroundStyle(Color.sticksFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        if let history = recap.history, let label = recap.historyLabel, !history.rows.isEmpty {
            section(label.uppercased()) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(history.rows) { row in
                        HStack {
                            Text(row.key.replacingOccurrences(of: "_", with: " ").uppercased())
                                .font(SticksFont.mono(10.5))
                                .kerning(0.5)
                                .foregroundStyle(Color.sticksMuted)
                            Spacer()
                            Text(row.value)
                                .font(SticksFont.mono(12.5, weight: .semibold))
                                .foregroundStyle(Color.sticksInk)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) {
                            Color.sticksHairline.opacity(0.6).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(SticksFont.mono(11))
                .kerning(0.8)
                .foregroundStyle(Color.sticksMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }
}

// MARK: - Arc chart

/// Cumulative strokes against par, one point per scored hole, in
/// playing order. ABOVE PAR IS UP — the line follows the number it
/// draws: a round that got worse climbs.
///
/// Straight segments, deliberately: a smoothed curve can overshoot its
/// endpoints and invent a birdie between two pars. Best runs solid
/// green; worst runs dashed — red alone isn't the cue the commonest
/// colourblindness can separate. The hole readout lives UNDER the
/// chart, fixed, where it's always legible; idle it doubles as legend.
struct RecapArcChart: View {
    let arc: [RecapArcPoint]
    let best: RecapStretch
    let worst: RecapStretch
    @Binding var selection: Int?
    /// The headline card draws a compact version: no labels, no readout.
    var compact = false

    private var bestRange: ClosedRange<Int> {
        best.from...min(best.to, max(arc.count - 1, 0))
    }
    private var worstRange: ClosedRange<Int> {
        worst.from...min(worst.to, max(arc.count - 1, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let layout = ArcLayout(
                    arc: arc,
                    size: CGSize(width: geo.size.width, height: geo.size.height)
                )
                ZStack {
                    // Dashed reference line at par, labelled.
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: layout.y(for: 0)))
                        path.addLine(to: CGPoint(x: geo.size.width, y: layout.y(for: 0)))
                    }
                    .stroke(Color.sticksHairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    Text("PAR")
                        .font(SticksFont.mono(8.5))
                        .kerning(0.6)
                        .foregroundStyle(Color.sticksFaint)
                        .position(x: geo.size.width - 2, y: layout.y(for: 0) - 8)

                    // Highlight segments under the dots and line.
                    if arc.count > 1 {
                        Path { path in
                            addRange(layout, bestRange, to: &path)
                        }
                        .stroke(Color.sticksGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

                        Path { path in
                            addRange(layout, worstRange, to: &path)
                        }
                        .stroke(
                            Color.sticksError,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 4])
                        )

                        // The joining line — only joining the dots.
                        Path { path in
                            for (index, point) in arc.enumerated() {
                                let p = layout.point(for: index, value: point.toPar)
                                if index == 0 {
                                    path.move(to: p)
                                } else {
                                    path.addLine(to: p)
                                }
                            }
                        }
                        .stroke(Color.sticksMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5))

                        // One dot per hole — the data.
                        ForEach(arc.indices, id: \.self) { index in
                            let p = layout.point(for: index, value: arc[index].toPar)
                            Circle()
                                .fill(
                                    selected == index
                                        ? Color.sticksInk
                                        : (arc[index].toPar > 0 ? Color.sticksError : Color.sticksGreen)
                                )
                                .frame(width: selected == index ? 10 : 7, height: selected == index ? 10 : 7)
                                .position(p)
                        }
                    }
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selection = layout.index(forX: value.location.x)
                        }
                        .onEnded { _ in }
                )
            }
            .frame(height: compact ? 80 : 170)

            if !compact {
                if arc.isEmpty {
                    Text("NO HOLES SCORED YET")
                        .font(SticksFont.mono(11))
                        .kerning(0.5)
                        .foregroundStyle(Color.sticksFaint)
                } else {
                    // The readout lives under the chart — a floating
                    // tooltip escapes the card at the top edge and sits
                    // under the thumb that summoned it. Idle it's the
                    // legend, so it costs no extra height.
                    HStack {
                        if let selected, arc.indices.contains(selected) {
                            let point = arc[selected]
                            Text("HOLE \(point.hole) · \(point.strokes) STROKES · \(RecapFormat.vsPar(point.delta)) ON THE HOLE")
                                .font(SticksFont.mono(11, weight: .semibold))
                                .kerning(0.4)
                                .foregroundStyle(Color.sticksInk)
                        } else {
                            Text("\(arc.count) HOLES · TAP THE LINE FOR A HOLE")
                                .font(SticksFont.mono(11))
                                .kerning(0.4)
                                .foregroundStyle(Color.sticksMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: 16)

                    // X labels from `hole`, in playing order — off the
                    // tenth this reads 10 … 18, 1 … 9. Not sorted.
                    HStack {
                        ForEach(arc.indices, id: \.self) { index in
                            Spacer(minLength: 0)
                            if labelIndexes.contains(index) {
                                Text("\(arc[index].hole)")
                                    .font(SticksFont.mono(9))
                                    .foregroundStyle(
                                        selected == index ? Color.sticksInk : Color.sticksFaint
                                    )
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(arcSummary)
    }

    private var selected: Int? {
        selection.flatMap { arc.indices.contains($0) ? $0 : nil }
    }

    /// Label at most every third hole plus the last, so 18 fit without
    /// crowding.
    private var labelIndexes: Set<Int> {
        guard arc.count > 3 else { return Set(arc.indices) }
        var indexes = Set(stride(from: 0, to: arc.count, by: 3))
        indexes.insert(arc.count - 1)
        return indexes
    }

    private var arcSummary: String {
        guard let first = arc.first, let last = arc.last else {
            return "No holes scored yet."
        }
        return "Round arc across \(arc.count) holes, from \(RecapFormat.vsPar(first.toPar)) at hole \(first.hole) to \(RecapFormat.vsPar(last.toPar)) at hole \(last.hole)."
    }

    private func addRange(_ layout: ArcLayout, _ range: ClosedRange<Int>, to path: inout Path) {
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, arc.count - 1)
        guard upper > lower else { return }
        for index in lower...upper {
            let p = layout.point(for: index, value: arc[index].toPar)
            if index == lower {
                path.move(to: p)
            } else {
                path.addLine(to: p)
            }
        }
    }

    /// Even spacing in playing order, y scaled to the toPar range with
    /// the par line pinned inside the view.
    private struct ArcLayout {
        let arc: [RecapArcPoint]
        let size: CGSize

        func point(for index: Int, value: Int) -> CGPoint {
            CGPoint(x: x(for: index), y: y(for: value))
        }

        func x(for index: Int) -> CGFloat {
            guard arc.count > 1 else { return size.width / 2 }
            return (CGFloat(index) / CGFloat(arc.count - 1)) * (size.width - 12) + 6
        }

        func y(for value: Int) -> CGFloat {
            guard let minValue = arc.map(\.toPar).min(),
                  let maxValue = arc.map(\.toPar).max() else { return size.height / 2 }
            let low = Double(min(minValue, 0))
            let high = Double(max(maxValue, 0))
            let span = max(high - low, 1)
            let inset: CGFloat = 14
            let usable = size.height - inset * 2
            // Above par is UP: bigger toPar sits higher on screen.
            return inset + CGFloat((high - Double(value)) / span) * usable
        }

        func index(forX x: CGFloat) -> Int? {
            guard !arc.isEmpty else { return nil }
            guard arc.count > 1 else { return 0 }
            let fraction = (x - 6) / (size.width - 12)
            return min(max(Int((fraction * CGFloat(arc.count - 1)).rounded()), 0), arc.count - 1)
        }
    }
}

// MARK: - The once-only headline card

/// Fires once per person per round, when the round goes final — keyed
/// off local storage per round, so re-checking the score never brings
/// it back. A second device may show it once more; nothing is harmed.
enum RecapCardStore {
    static func hasShown(userId: String, matchId: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(userId: userId, matchId: matchId))
    }

    static func markShown(userId: String, matchId: String) {
        UserDefaults.standard.set(true, forKey: key(userId: userId, matchId: matchId))
    }

    private static func key(userId: String, matchId: String) -> String {
        "recap-card-shown.\(userId).\(matchId)"
    }
}

/// Headline only: score, toPar, the one sentence, a small arc, and the
/// ends of the scale — birdies and blow-ups. The four sections live in
/// the tab; repeating them here makes a page on top of a page.
struct RecapHeadlineCard: View {
    let recap: RoundRecap
    let courseName: String
    let isOwnSeat: Bool
    let onReadRecap: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("FINAL — \(courseName.uppercased())")
                    .font(SticksFont.mono(10.5))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksMuted)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(recap.headline.score)
                        .font(SticksFont.display(56, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                    if !recap.headline.toPar.isEmpty {
                        Text(recap.headline.toPar)
                            .font(SticksFont.display(22, weight: .semibold))
                            .foregroundStyle(Color.sticksError)
                    }
                    Spacer(minLength: 0)
                }

                Text(recap.headline.story)
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksInk)
                    .fixedSize(horizontal: false, vertical: true)

                if let best = recap.recap.best, let worst = recap.recap.worst {
                    RecapArcChart(
                        arc: recap.recap.arc,
                        best: best,
                        worst: worst,
                        selection: .constant(nil),
                        compact: true
                    )
                }

                // Ends of the scale only — "14 bogeys" is a statistic,
                // not a highlight.
                HStack(spacing: 8) {
                    if let birdies = recap.recap.distribution?.birdies, birdies > 0 {
                        endChip("🔥", RecapFormat.countLabel(birdies, "birdie", "birdies"))
                    }
                    if let blowups = recap.recap.distribution?.triplesOrWorse, blowups > 0 {
                        endChip("💥", RecapFormat.countLabel(blowups, "blow-up", "blow-ups"))
                    }
                    Spacer(minLength: 0)
                }

                Button {
                    dismiss()
                    // Let the sheet finish dismissing before the tab
                    // switches underneath it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        onReadRecap()
                    }
                } label: {
                    Text("READ THE RECAP")
                        .font(SticksFont.sans(14, weight: .semibold))
                        .foregroundStyle(Color.sticksCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.sticksGreen)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint("Opens the full recap for this round")

                if !isOwnSeat {
                    Text("Showing \(recap.seat.displayName)'s card.")
                        .font(SticksFont.sans(11.5))
                        .foregroundStyle(Color.sticksFaint)
                }
            }
            .padding(20)
        }
        .presentationBackground(Color.sticksBg.opacity(0.94))
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private func endChip(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Text(emoji)
            Text(text.uppercased())
                .font(SticksFont.mono(11))
                .kerning(0.4)
                .foregroundStyle(Color.sticksInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.sticksCard)
        .clipShape(.capsule)
        .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
