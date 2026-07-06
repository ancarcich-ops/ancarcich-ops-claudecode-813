//
//  GroupLeaderboardView.swift
//  Sticks
//
//  Slice 16: the group leaderboard restyle — latest winners (MAIN +
//  SKINS champions with gold medal discs), fixed-column standings with
//  sort segments and rank medals, a pinned-column head-to-head table,
//  and restyled streaks + course records. Loading keeps skeleton rows.
//

import SwiftUI

/// Push destination for a group's leaderboard, registered on the
/// Groups tab's NavigationStack.
struct LeaderboardDestination: Hashable {
    let group: SticksGroup
}

struct GroupLeaderboardView: View {
    let group: SticksGroup
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GroupLeaderboardViewModel()

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleBlock(completedMatches: nil)
                        LeaderboardSkeleton()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            case .failed(let message):
                failedView(message)
            case .loaded:
                if let leaderboard = viewModel.leaderboard {
                    content(leaderboard)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backChip }
        }
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .task {
            await viewModel.load(groupId: group.id, session: session)
        }
    }

    // MARK: - Back chip

    /// "← #GROUPNAME" — replaces the system back button.
    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            Text("← #\(hashtagName)")
                .font(SticksFont.mono(11.5))
                .kerning(1.15)
                .foregroundStyle(Color.sticksGreen)
                .lineLimit(1)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(group.name)")
    }

    private var hashtagName: String {
        group.name.uppercased().replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Content

    private func content(_ leaderboard: GroupLeaderboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock(completedMatches: leaderboard.completedMatches)

                let winners = latestWinners(leaderboard.champions)
                if !winners.isEmpty {
                    LatestWinnersCard(entries: winners)
                }

                StandingsSection(leaderboard: leaderboard)

                if leaderboard.headToHead.users.count >= 2 {
                    HeadToHeadCard(headToHead: leaderboard.headToHead)
                }

                let streaks = leaderboard.streaks.filter { $0.bestMainStreak >= 2 }
                if !streaks.isEmpty {
                    StreaksCard(streaks: streaks)
                }

                if !leaderboard.courseRecords.isEmpty {
                    CourseRecordsCard(records: leaderboard.courseRecords, rows: leaderboard.rows)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(groupId: group.id, session: session)
        }
    }

    /// MAIN first, then SKINS — the only champion kinds shown here.
    private func latestWinners(_ champions: [ChampionEntry]) -> [ChampionEntry] {
        let main = champions.filter { $0.kind.uppercased() == "MAIN" }
        let skins = champions.filter { $0.kind.uppercased() == "SKINS" }
        return main + skins
    }

    // MARK: - Title

    private func titleBlock(completedMatches: Int?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Leaderboard")
                .font(SticksFont.display(38, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Color.sticksInk)

            if let completedMatches {
                lede(completedMatches: completedMatches)
            }
        }
    }

    private func lede(completedMatches: Int) -> some View {
        let countText = completedMatches == 1
            ? "1 completed match."
            : "\(completedMatches) completed matches."
        return (
            Text(countText + " ")
                .font(SticksFont.sans(13.5, weight: .bold))
                .foregroundStyle(Color.sticksInk)
            + Text("Ties at the top of any game share the win.")
                .font(SticksFont.sans(13.5))
                .foregroundStyle(Color.sticksMuted)
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Failed

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.load(groupId: group.id, session: session) }
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

// MARK: - Medal colors

/// Radial medal discs for ranks 1–3 and the winners card.
private enum MedalPalette {
    static let goldLight = Color(red: 230 / 255, green: 201 / 255, blue: 142 / 255)   // #E6C98E
    static let goldDark = Color(red: 185 / 255, green: 138 / 255, blue: 47 / 255)     // #B98A2F
    static let silverLight = Color(red: 220 / 255, green: 214 / 255, blue: 200 / 255) // #DCD6C8
    static let silverDark = Color(red: 168 / 255, green: 160 / 255, blue: 140 / 255)  // #A8A08C
    static let bronzeLight = Color(red: 217 / 255, green: 168 / 255, blue: 120 / 255) // #D9A878
    static let bronzeDark = Color(red: 165 / 255, green: 113 / 255, blue: 63 / 255)   // #A5713F

    /// (light, dark) pair for a 1-based rank, nil past 3.
    static func gradient(rank: Int) -> (light: Color, dark: Color)? {
        switch rank {
        case 1: return (goldLight, goldDark)
        case 2: return (silverLight, silverDark)
        case 3: return (bronzeLight, bronzeDark)
        default: return nil
        }
    }
}

private struct MedalDisc: View {
    let light: Color
    let dark: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [light, dark],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: size * 0.75
                )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Latest winners

private struct LatestWinnersCard: View {
    let entries: [ChampionEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            ForEach(Array(entries.enumerated()), id: \.element.id) { position, entry in
                if position > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                row(entry)
            }
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sticksGold)
                .frame(width: 30, height: 30)
                .background(Color.sticksGold.opacity(0.14))
                .clipShape(.rect(cornerRadius: 9))

            Text("Latest winners")
                .font(SticksFont.display(18, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
        }
        .padding(.bottom, 6)
    }

    private func row(_ entry: ChampionEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Fixed kicker column.
            VStack(alignment: .leading, spacing: 3) {
                Text(kicker(entry))
                    .font(SticksFont.mono(9))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sticksFaint)

                Text(entry.courseName)
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 74, alignment: .leading)

            // Winner names + sub-line.
            VStack(alignment: .leading, spacing: 3) {
                winnerNames(entry)
                    .lineLimit(1)

                Text(subline(entry))
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Gold medal disc.
            MedalDisc(light: MedalPalette.goldLight, dark: MedalPalette.goldDark, size: 34)
                .overlay {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sticksCream)
                }
        }
        .padding(.vertical, 10)
    }

    private func kicker(_ entry: ChampionEntry) -> String {
        entry.kind.uppercased() == "MAIN" ? "MAIN GAME" : "SKINS"
    }

    /// Names in display bold, joined with an "&" lighter than the names.
    private func winnerNames(_ entry: ChampionEntry) -> Text {
        let names = entry.winners.map(\.displayName).filter { !$0.isEmpty }
        guard let first = names.first else {
            return Text("—")
                .font(SticksFont.display(19, weight: .bold))
                .foregroundStyle(Color.sticksFaint)
        }
        var combined = Text(first)
            .font(SticksFont.display(19, weight: .bold))
            .foregroundStyle(Color.sticksInk)
        for name in names.dropFirst() {
            combined = combined
                + Text(" & ")
                    .font(SticksFont.display(19, weight: .bold))
                    .foregroundStyle(Color.sticksFaint)
                + Text(name)
                    .font(SticksFont.display(19, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
        }
        return combined
    }

    private func subline(_ entry: ChampionEntry) -> String {
        entry.winners.count > 1 ? "Shared win · \(entry.courseName)" : entry.courseName
    }
}

// MARK: - Standings

/// Sort keys for the standings table — each maps to one metric column.
private enum StandingsSort: String, CaseIterable {
    case all = "All"
    case main = "Main"
    case skins = "Skins"
    case played = "Played"

    func value(_ row: LeaderboardRow) -> Int {
        switch self {
        case .all: return row.totalWins
        case .main: return row.mainWins
        case .skins: return row.skinsWins
        case .played: return row.matchesPlayed
        }
    }
}

/// One fixed metric column: GP / MAIN / SKINS / ALL.
private enum StandingsColumn: String, CaseIterable {
    case gp = "GP"
    case main = "MAIN"
    case skins = "SKINS"
    case all = "ALL"

    func value(_ row: LeaderboardRow) -> Int {
        switch self {
        case .gp: return row.matchesPlayed
        case .main: return row.mainWins
        case .skins: return row.skinsWins
        case .all: return row.totalWins
        }
    }

    /// The sort segment that highlights this column.
    var sort: StandingsSort {
        switch self {
        case .gp: return .played
        case .main: return .main
        case .skins: return .skins
        case .all: return .all
        }
    }
}

private struct StandingsSection: View {
    let leaderboard: GroupLeaderboard

    @State private var sort: StandingsSort = .all

    private static let rankWidth: CGFloat = 26
    private static let metricWidth: CGFloat = 34
    private static let rowHeight: CGFloat = 56

    private var sortedRows: [LeaderboardRow] {
        leaderboard.rows.sorted { a, b in
            let keyA = sort.value(a)
            let keyB = sort.value(b)
            if keyA != keyB { return keyA > keyB }
            if a.totalWins != b.totalWins { return a.totalWins > b.totalWins }
            if a.matchesPlayed != b.matchesPlayed { return a.matchesPlayed < b.matchesPlayed }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sortControl
            card
        }
    }

    // MARK: Sort segments

    private var sortControl: some View {
        HStack(spacing: 7) {
            Text("SORT")
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)

            ForEach(StandingsSort.allCases, id: \.self) { option in
                segment(option)
            }
        }
    }

    private func segment(_ option: StandingsSort) -> some View {
        let isActive = option == sort
        return Button {
            guard sort != option else { return }
            sort = option
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(option.rawValue)
                .font(SticksFont.mono(11))
                .foregroundStyle(isActive ? Color.sticksCream : Color.sticksMuted)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(isActive ? Color.sticksGreen : Color.sticksPanel2)
                .clipShape(.capsule)
                .overlay(
                    Capsule().stroke(
                        isActive ? Color.clear : Color.sticksHairline,
                        lineWidth: 1
                    )
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(option.rawValue)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: Card

    private var card: some View {
        Group {
            if leaderboard.completedMatches == 0 {
                Text("No finished rounds yet — the board starts counting when a match goes final.")
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                table
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var table: some View {
        let rows = sortedRows
        return VStack(spacing: 0) {
            headerRow

            ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                standingsRow(row: row, rank: position + 1)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.sticksHairline).frame(height: 1)
                    }
            }

            footer
        }
        .padding(.vertical, 10)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.rankWidth, height: 1)

            Spacer(minLength: 0)

            ForEach(StandingsColumn.allCases, id: \.self) { column in
                Text(column.rawValue)
                    .font(SticksFont.mono(8.5))
                    .kerning(0.5)
                    .foregroundStyle(column.sort == sort ? Color.sticksGreen : Color.sticksFaint)
                    .frame(width: Self.metricWidth)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 7)
    }

    private func standingsRow(row: LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 8) {
            rankView(rank)
                .frame(width: Self.rankWidth)

            HStack(spacing: 10) {
                LeaderboardAvatar(
                    userId: row.userId,
                    name: row.name,
                    avatarUrl: row.avatarUrl,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(SticksFont.sans(14.5, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    Text("@\(row.username)")
                        .font(SticksFont.mono(10.5))
                        .foregroundStyle(Color.sticksFaint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(StandingsColumn.allCases, id: \.self) { column in
                metricCell(value: column.value(row), isActive: column.sort == sort)
                    .frame(width: Self.metricWidth)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.rowHeight)
        .background {
            if rank == 1 {
                LinearGradient(
                    stops: [
                        .init(color: Color.sticksGold.opacity(0.10), location: 0),
                        .init(color: Color.sticksGold.opacity(0), location: 0.7),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    @ViewBuilder
    private func rankView(_ rank: Int) -> some View {
        if let medal = MedalPalette.gradient(rank: rank) {
            MedalDisc(light: medal.light, dark: medal.dark, size: 22)
                .overlay {
                    Text("\(rank)")
                        .font(SticksFont.mono(11))
                        .foregroundStyle(.white)
                }
        } else {
            Text("\(rank)")
                .font(SticksFont.mono(12))
                .foregroundStyle(Color.sticksFaint)
        }
    }

    private func metricCell(value: Int, isActive: Bool) -> some View {
        let color: Color
        if isActive {
            color = value == 0 ? Color.sticksGreen.opacity(0.5) : Color.sticksGreen
        } else {
            color = value == 0 ? Color.sticksFaint.opacity(0.5) : Color.sticksInk
        }
        return Text("\(value)")
            .font(SticksFont.mono(15))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.sticksFaint)

            Text("Only Sticks-linked players appear — guest names don't count.")
                .font(SticksFont.mono(10.5))
                .foregroundStyle(Color.sticksFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.sticksHairline).frame(height: 1)
        }
    }
}

// MARK: - Head to head

/// Scroll geometry snapshot for the head-to-head table's edge fade.
private struct H2HScrollState: Equatable {
    var overflows = false
    var atEnd = false
}

private struct HeadToHeadCard: View {
    let headToHead: HeadToHead

    @State private var scrollState = H2HScrollState()

    private static let pinnedWidth: CGFloat = 92
    private static let columnWidth: CGFloat = 64
    private static let headerHeight: CGFloat = 40
    private static let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Head to head")
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            table

            if scrollState.overflows {
                Text("SWIPE TO SEE ALL RIVALS →")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var table: some View {
        HStack(alignment: .top, spacing: 0) {
            pinnedColumn

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(Array(headToHead.users.enumerated()), id: \.element.id) { position, user in
                        valueRow(for: user, position: position)
                    }
                }
            }
            .onScrollGeometryChange(for: H2HScrollState.self) { geometry in
                H2HScrollState(
                    overflows: geometry.contentSize.width > geometry.containerSize.width + 1,
                    atEnd: geometry.contentOffset.x + geometry.containerSize.width
                        >= geometry.contentSize.width - 2
                )
            } action: { _, newValue in
                scrollState = newValue
            }
            .overlay(alignment: .trailing) {
                if scrollState.overflows && !scrollState.atEnd {
                    LinearGradient(
                        colors: [Color.sticksCard.opacity(0), Color.sticksCard],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// Corner + row names, pinned with an opaque panel background while
    /// the opponent columns scroll underneath.
    private var pinnedColumn: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.headerHeight)

            ForEach(Array(headToHead.users.enumerated()), id: \.element.id) { position, user in
                Text(user.name)
                    .font(SticksFont.sans(12.5, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                    .frame(height: Self.rowHeight)
                    .background(rowTint(position))
            }
        }
        .frame(width: Self.pinnedWidth)
        .background(Color.sticksCard)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(headToHead.users) { user in
                VStack(spacing: 2) {
                    Text("VS")
                        .font(SticksFont.mono(8))
                        .kerning(0.6)
                        .foregroundStyle(Color.sticksFaint)

                    Text(user.name)
                        .font(SticksFont.sans(11, weight: .bold))
                        .foregroundStyle(Color.sticksMuted)
                        .lineLimit(1)
                }
                .frame(width: Self.columnWidth)
            }
        }
        .frame(height: Self.headerHeight, alignment: .bottom)
        .padding(.bottom, 4)
    }

    private func valueRow(for rowUser: HeadToHead.Member, position: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(headToHead.users) { columnUser in
                cell(row: rowUser, column: columnUser)
                    .frame(width: Self.columnWidth, height: Self.rowHeight)
            }
        }
        .background(rowTint(position))
    }

    @ViewBuilder
    private func cell(row: HeadToHead.Member, column: HeadToHead.Member) -> some View {
        if row.userId == column.userId {
            Text("—")
                .font(SticksFont.mono(13))
                .foregroundStyle(Color.sticksFaint.opacity(0.45))
        } else {
            let wins = headToHead.wins(of: row.userId, over: column.userId)
            let losses = headToHead.wins(of: column.userId, over: row.userId)
            Text("\(wins)–\(losses)")
                .font(SticksFont.mono(13))
                .monospacedDigit()
                .foregroundStyle(cellColor(wins: wins, losses: losses))
        }
    }

    private func cellColor(wins: Int, losses: Int) -> Color {
        if wins > losses { return .sticksGreen }
        if losses > wins { return .sticksError }
        return .sticksFaint
    }

    /// Even rows (2nd, 4th, …) get a faint accent tint.
    private func rowTint(_ position: Int) -> Color {
        position % 2 == 1 ? Color.sticksGreen.opacity(0.04) : Color.clear
    }
}

// MARK: - Streaks

private struct StreaksCard: View {
    let streaks: [StreakEntry]

    var body: some View {
        LeaderboardSectionCard(title: "Streaks") {
            ForEach(Array(streaks.enumerated()), id: \.element.id) { position, streak in
                if position > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                row(streak)
            }
        }
    }

    private func row(_ streak: StreakEntry) -> some View {
        let isActive = streak.currentMainStreak > 0
        return HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.sticksError : Color.sticksFaint)
                .frame(width: 30, height: 30)
                .background(isActive ? Color.sticksError.opacity(0.10) : Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 9))

            Text(streak.displayName)
                .font(SticksFont.sans(13.5, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(streak.currentMainStreak)")
                    .font(SticksFont.display(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Color.sticksError : Color.sticksMuted)

                Text("best \(streak.bestMainStreak)")
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksFaint)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Course records

private struct CourseRecordsCard: View {
    let records: [CourseRecord]
    let rows: [LeaderboardRow]

    var body: some View {
        LeaderboardSectionCard(title: "Course records") {
            ForEach(Array(records.enumerated()), id: \.element.id) { position, record in
                if position > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                row(record)
            }
        }
    }

    private func row(_ record: CourseRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.courseName)
                    .font(SticksFont.sans(14, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(GroupIdentity.color(for: identityKey(record)))
                        .frame(width: 7, height: 7)

                    Text(record.bestDisplayName)
                        .font(SticksFont.mono(10.5))
                        .foregroundStyle(Color.sticksFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                Text(record.gross.map { "\($0)" } ?? "—")
                    .font(SticksFont.display(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.sticksInk)

                if let net = record.net {
                    Text("net \(net, specifier: "%.1f")")
                        .font(SticksFont.mono(10.5))
                        .foregroundStyle(Color.sticksFaint)
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// Identity hash key — the holder's userId when the server provides
    /// one, else the matching leaderboard row's userId, else the name
    /// (so the dot stays stable either way).
    private func identityKey(_ record: CourseRecord) -> String {
        if let userId = record.userId, !userId.isEmpty { return userId }
        if let row = rows.first(where: { $0.name == record.bestDisplayName }) {
            return row.userId
        }
        return record.bestDisplayName
    }
}

// MARK: - Avatar

/// Avatar — photo from avatarUrl, else initials on a stable identity
/// color hashed from the userId.
private struct LeaderboardAvatar: View {
    let userId: String
    let name: String
    let avatarUrl: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = avatarUrl, let url = URL(string: urlString) {
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
    }

    private var initialsBubble: some View {
        ZStack {
            GroupIdentity.color(for: userId)
            Text(initials)
                .font(SticksFont.label(size * 0.38, weight: .bold))
                .foregroundStyle(Color.sticksCream)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Section card shell

private struct LeaderboardSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SticksFont.display(13, weight: .bold))
                .foregroundStyle(Color.sticksInk)
                .padding(.bottom, 2)

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

// MARK: - Skeleton

/// Loading placeholder — pulsing skeleton rows in the table card shell.
private struct LeaderboardSkeleton: View {
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 5, id: \.self) { position in
                if position > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                skeletonRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .opacity(isPulsing ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }

    private var skeletonRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.sticksPanel2)
                .frame(width: 34, height: 34)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.sticksPanel2)
                .frame(width: 110, height: 11)

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.sticksPanel2)
                .frame(width: 60, height: 11)
        }
        .frame(height: 52)
    }
}
