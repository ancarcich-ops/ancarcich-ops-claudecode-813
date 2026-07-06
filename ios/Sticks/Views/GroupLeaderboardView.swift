//
//  GroupLeaderboardView.swift
//  Sticks
//
//  Slice 14: the group leaderboard — wins table (name column pinned,
//  game-type columns scroll), reigning champs, course records, and
//  streaks. Loading shows skeleton rows, not a spinner.
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

    @State private var viewModel = GroupLeaderboardViewModel()

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleBlock(roundsCounted: nil)
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
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .task {
            await viewModel.load(groupId: group.id, session: session)
        }
    }

    // MARK: - Content

    private func content(_ leaderboard: GroupLeaderboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock(roundsCounted: leaderboard.completedMatches)

                LeaderboardTable(leaderboard: leaderboard)

                if !leaderboard.champions.isEmpty {
                    ChampionsCard(champions: leaderboard.champions)
                }

                if !leaderboard.courseRecords.isEmpty {
                    CourseRecordsCard(records: leaderboard.courseRecords)
                }

                let streaks = leaderboard.streaks.filter { $0.bestMainStreak >= 2 }
                if !streaks.isEmpty {
                    StreaksCard(streaks: streaks)
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

    // MARK: - Title

    private func titleBlock(roundsCounted: Int?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.name)
                .font(SticksFont.display(24, weight: .bold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Text(subtitleText(roundsCounted: roundsCounted))
                .font(SticksFont.mono(10))
                .kerning(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.sticksFaint)
        }
    }

    private func subtitleText(roundsCounted: Int?) -> String {
        guard let roundsCounted else { return "LEADERBOARD" }
        let rounds = roundsCounted == 1 ? "1 ROUND" : "\(roundsCounted) ROUNDS"
        return "LEADERBOARD · \(rounds) COUNTED"
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

// MARK: - Table

/// The wins table: rank + avatar + name pinned on the left; one mono
/// column per game type whose has* flag is true, then TOTAL, scrolling
/// horizontally when they overflow.
private struct LeaderboardTable: View {
    let leaderboard: GroupLeaderboard

    private struct GameColumn: Identifiable {
        let header: String
        let value: (LeaderboardRow) -> Int
        var id: String { header }
    }

    private static let nameColumnWidth: CGFloat = 158
    private static let gameColumnWidth: CGFloat = 52
    private static let totalColumnWidth: CGFloat = 56
    private static let headerHeight: CGFloat = 24
    private static let rowHeight: CGFloat = 44

    private var columns: [GameColumn] {
        var visible: [GameColumn] = []
        if leaderboard.hasMain { visible.append(GameColumn(header: "MAIN") { $0.mainWins }) }
        if leaderboard.hasStableford { visible.append(GameColumn(header: "STAPLE") { $0.stablefordWins }) }
        if leaderboard.hasSkins { visible.append(GameColumn(header: "SKINS") { $0.skinsWins }) }
        if leaderboard.hasNassau { visible.append(GameColumn(header: "NASSAU") { $0.nassauWins }) }
        if leaderboard.hasBbb { visible.append(GameColumn(header: "BBB") { $0.bbbWins }) }
        if leaderboard.hasSnake { visible.append(GameColumn(header: "SNAKE") { $0.snakeWins }) }
        if leaderboard.hasWolf { visible.append(GameColumn(header: "WOLF") { $0.wolfWins }) }
        return visible
    }

    var body: some View {
        Group {
            if leaderboard.completedMatches == 0 {
                emptyState
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        Text("No finished rounds yet — the board starts counting when a match goes final.")
            .font(SticksFont.sans(13.5))
            .foregroundStyle(Color.sticksMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private var table: some View {
        let rows = leaderboard.sortedRows
        return HStack(alignment: .top, spacing: 0) {
            // Pinned: rank + avatar + name.
            VStack(spacing: 0) {
                Color.clear.frame(height: Self.headerHeight)
                ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                    pinnedCell(row: row, rank: position + 1)
                }
            }
            .frame(width: Self.nameColumnWidth)

            // Scrolling: per-game columns + TOTAL.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                        valueRow(row: row, isLast: position == rows.count - 1)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                Text(column.header)
                    .font(SticksFont.mono(8.5))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksFaint)
                    .frame(width: Self.gameColumnWidth, alignment: .trailing)
            }
            Text("TOTAL")
                .font(SticksFont.mono(8.5))
                .kerning(0.6)
                .foregroundStyle(Color.sticksFaint)
                .frame(width: Self.totalColumnWidth, alignment: .trailing)
        }
        .frame(height: Self.headerHeight, alignment: .bottom)
        .padding(.bottom, 2)
    }

    private func pinnedCell(row: LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 9) {
            Text("\(rank)")
                .font(SticksFont.mono(12))
                .foregroundStyle(rank == 1 ? Color.sticksGold : Color.sticksFaint)
                .frame(width: 18, alignment: .leading)

            LeaderboardAvatar(row: row, size: 22)

            Text(row.name)
                .font(SticksFont.sans(13, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.sticksHairline).frame(height: 1)
        }
    }

    private func valueRow(row: LeaderboardRow, isLast: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
                Text("\(column.value(row))")
                    .font(SticksFont.mono(12))
                    .monospacedDigit()
                    .foregroundStyle(column.value(row) > 0 ? Color.sticksInk : Color.sticksFaint)
                    .frame(width: Self.gameColumnWidth, alignment: .trailing)
            }
            Text("\(row.totalWins)")
                .font(SticksFont.display(13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)
                .frame(width: Self.totalColumnWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.sticksHairline).frame(height: 1)
        }
    }
}

/// Avatar — photo from avatarUrl, else initials on a stable color
/// hashed from the userId.
private struct LeaderboardAvatar: View {
    let row: LeaderboardRow
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString = row.avatarUrl, let url = URL(string: urlString) {
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
            GroupIdentity.color(for: row.userId)
            Text(initials)
                .font(SticksFont.label(size * 0.38, weight: .bold))
                .foregroundStyle(Color.sticksCream)
        }
    }

    private var initials: String {
        let parts = row.name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Champions

private struct ChampionsCard: View {
    let champions: [ChampionEntry]

    var body: some View {
        LeaderboardSectionCard(title: "Reigning champs") {
            ForEach(Array(champions.enumerated()), id: \.element.id) { position, champ in
                if position > 0 {
                    Rectangle().fill(Color.sticksHairline).frame(height: 1)
                }
                row(champ)
            }
        }
    }

    private func row(_ champ: ChampionEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(champ.label)
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.sticksFaint)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(champ.winners.map(\.displayName).joined(separator: " · "))
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(courseDateText(champ))
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    private func courseDateText(_ champ: ChampionEntry) -> String {
        var parts: [String] = []
        if !champ.courseName.isEmpty { parts.append(champ.courseName.uppercased()) }
        if let date = champ.scheduledAt {
            parts.append(LeaderboardDateFormat.short(date))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Course records

private struct CourseRecordsCard: View {
    let records: [CourseRecord]

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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.courseName)
                    .font(SticksFont.sans(13, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text(record.bestDisplayName)
                    .font(SticksFont.sans(12))
                    .foregroundStyle(Color.sticksMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            scoreText(record)
                .font(SticksFont.mono(12))
                .lineLimit(1)
        }
        .padding(.vertical, 9)
    }

    /// "71 GROSS · 65.4 NET" — the net part in accent.
    private func scoreText(_ record: CourseRecord) -> Text {
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
        HStack(spacing: 10) {
            Text(streak.displayName)
                .font(SticksFont.sans(13, weight: .semibold))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)

            if streak.currentMainStreak >= 2 {
                Text("W\(streak.currentMainStreak) RUNNING")
                    .font(SticksFont.mono(10))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksGreen)
            }

            Spacer(minLength: 8)

            Text("BEST W\(streak.bestMainStreak)")
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.vertical, 10)
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
                .frame(width: 22, height: 22)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.sticksPanel2)
                .frame(width: 110, height: 11)

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.sticksPanel2)
                .frame(width: 60, height: 11)
        }
        .frame(height: 44)
    }
}

// MARK: - Date helper

nonisolated enum LeaderboardDateFormat {
    /// Short date like "JUN 14".
    static func short(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }
}
