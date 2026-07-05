//
//  MatchListView.swift
//  Sticks
//
//  The signed-in home screen. Groups matches into Live / Upcoming /
//  Recent with pull-to-refresh; each match renders as a status-aware
//  card (MatchCardView) and the whole card navigates to the detail.
//

import SwiftUI

struct MatchListView: View {
    let user: User
    let session: SessionStore
    /// Present when hosted inside the tab root — renders the tab bar on
    /// this screen only (pushed screens stay full-bleed).
    var tabSelection: Binding<SticksTab>? = nil

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
                    MatchCardView(match: match)
                }
                .buttonStyle(MatchCardButtonStyle())
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading matches…")
                .font(SticksFont.sans(14))
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

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

// MARK: - Pieces

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

private struct MatchCardButtonStyle: ButtonStyle {
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
