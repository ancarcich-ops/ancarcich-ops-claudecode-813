//
//  MatchListView.swift
//  Sticks
//
//  Slice 2: the signed-in home screen. Groups matches into
//  Live / Upcoming / Recent with pull-to-refresh.
//

import SwiftUI

struct MatchListView: View {
    let user: User
    let session: SessionStore

    @State private var viewModel = MatchListViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                switch viewModel.phase {
                case .loading:
                    loadingView
                case .failed(let message):
                    failedView(message)
                case .loaded:
                    if viewModel.matches.isEmpty {
                        emptyView
                    } else {
                        matchList
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .navigationDestination(for: MatchSummary.self) { match in
                MatchDetailView(match: match, session: session)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load(session: session)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("SticksMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .accessibilityHidden(true)

            Text("Sticks")
                .font(SticksFont.display(30))
                .foregroundStyle(Color.sticksInk)

            Spacer()

            Menu {
                Section("@\(user.username)") {
                    Button(role: .destructive) {
                        session.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Text(initials(of: user.displayName))
                    .font(SticksFont.label(13, weight: .bold))
                    .foregroundStyle(Color.sticksCream)
                    .frame(width: 36, height: 36)
                    .background(Color.sticksGreen)
                    .clipShape(.circle)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.sticksBg.opacity(0.97))
    }

    // MARK: - List

    private var matchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if !viewModel.liveMatches.isEmpty {
                    matchSection(
                        title: "Live",
                        matches: viewModel.liveMatches,
                        showsLiveDot: true
                    )
                }
                if !viewModel.upcomingMatches.isEmpty {
                    matchSection(title: "Upcoming", matches: viewModel.upcomingMatches)
                }
                if !viewModel.recentMatches.isEmpty {
                    matchSection(title: "Recent", matches: viewModel.recentMatches)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(session: session)
        }
    }

    private func matchSection(
        title: String,
        matches: [MatchSummary],
        showsLiveDot: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if showsLiveDot {
                    PulsingDot()
                }
                Text(title)
                    .font(SticksFont.label(12))
                    .kerning(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(showsLiveDot ? Color.sticksGreen : Color.sticksMuted)
            }
            .padding(.leading, 4)

            ForEach(matches) { match in
                NavigationLink(value: match) {
                    MatchRowView(match: match)
                }
                .buttonStyle(MatchRowButtonStyle())
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading matches…")
                .font(.system(size: 14))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text("No matches yet")
                .font(SticksFont.display(24))
                .foregroundStyle(Color.sticksInk)
            Text("Create a match on the Sticks web app\nand it'll show up here.")
                .font(.system(size: 14))
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
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.load(session: session) }
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sticksCream)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Row

private struct MatchRowView: View {
    let match: MatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                StatusChip(status: match.status)
                Spacer()
                Text(Self.dateText(for: match))
                    .font(SticksFont.label(11, weight: .medium))
                    .kerning(0.6)
                    .foregroundStyle(Color.sticksMuted)
            }

            Text(match.courseName)
                .font(SticksFont.display(22))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 10) {
                AvatarStack(players: match.players)

                Text(detailText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sticksMuted)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksHairline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var detailText: String {
        let count = match.players.count
        let playersPart = count == 1 ? "1 player" : "\(count) players"
        return "\(playersPart) · \(match.holes) holes · \(match.scoringMode.capitalized)"
    }

    private static func dateText(for match: MatchSummary) -> String {
        if Calendar.current.isDateInToday(match.scheduledAt) {
            return "TODAY · \(match.scheduledAt.formatted(date: .omitted, time: .shortened))"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: match.scheduledAt).uppercased()
    }
}

// MARK: - Pieces

private struct AvatarStack: View {
    let players: [MatchPlayerSummary]

    private var visible: [MatchPlayerSummary] { Array(players.prefix(4)) }
    private var overflow: Int { max(0, players.count - 4) }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(visible) { player in
                Text(initial(of: player.displayName))
                    .font(SticksFont.label(11, weight: .bold))
                    .foregroundStyle(Color.sticksCream)
                    .frame(width: 26, height: 26)
                    .background(Color.sticksGreen)
                    .clipShape(.circle)
                    .overlay(
                        Circle().stroke(Color.sticksCard, lineWidth: 2)
                    )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(SticksFont.label(10, weight: .bold))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 26, height: 26)
                    .background(Color.sticksPanel2)
                    .clipShape(.circle)
                    .overlay(
                        Circle().stroke(Color.sticksCard, lineWidth: 2)
                    )
            }
        }
    }

    private func initial(of name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.sticksGreen)
            .frame(width: 8, height: 8)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

private struct MatchRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    MatchListView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore()
    )
}
