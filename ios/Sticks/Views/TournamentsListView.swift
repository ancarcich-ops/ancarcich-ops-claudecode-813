//
//  TournamentsListView.swift
//  Sticks
//
//  Slice 55: the tournaments list — cards with name, status chip,
//  "Round X/Y" progress and player count, plus "+ New tournament" and
//  "Join by code" actions (sheets). Pushed from the Groups tab;
//  tapping a card pushes the tournament detail.
//

import SwiftUI
import UIKit

/// Push destination for the tournaments list, registered on the
/// Groups tab's NavigationStack.
struct TournamentsDestination: Hashable {}

/// Push destination for one tournament's detail — id-only so the
/// create/join flows can push straight from a fresh POST response.
struct TournamentRoute: Hashable, Identifiable {
    let id: String
}

struct TournamentsListView: View {
    let user: User
    let session: SessionStore
    /// Pushes a tournament's detail onto the Groups stack (the stack's
    /// path lives in GroupsView).
    let onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = TournamentsViewModel()
    @State private var showsCreate = false
    @State private var showsJoin = false

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                loadingView
            case .failed(let message):
                failedView(message)
            case .loaded:
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backChip }
        }
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .sheet(isPresented: $showsCreate) {
            CreateTournamentView(viewModel: viewModel, session: session) { id in
                showsCreate = false
                onOpen(id)
            }
        }
        .sheet(isPresented: $showsJoin) {
            JoinTournamentView(viewModel: viewModel, session: session) { id in
                showsJoin = false
                onOpen(id)
            }
        }
        .task {
            await viewModel.load(session: session)
        }
    }

    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("←").layoutPriority(1)
                Text("GROUPS").lineLimit(1)
            }
            .font(SticksFont.mono(11.5))
            .kerning(1.15)
            .foregroundStyle(Color.sticksGreen)
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to groups")
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock
                actionRow

                if viewModel.tournaments.isEmpty {
                    emptyCard
                } else {
                    VStack(spacing: 13) {
                        ForEach(viewModel.tournaments) { tournament in
                            TournamentCard(tournament: tournament)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(session: session)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Tournaments")
                .font(SticksFont.display(38, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Color.sticksInk)

            Text("Multi-round events with a cumulative leaderboard. Share the invite code to fill the field.")
                .font(SticksFont.sans(14.5))
                .foregroundStyle(Color.sticksMuted)
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                showsCreate = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("New tournament")
                        .font(SticksFont.sans(14.5, weight: .bold))
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(PressableButtonStyle())

            Button {
                showsJoin = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "ticket")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Join by code")
                        .font(SticksFont.sans(14.5, weight: .bold))
                }
                .foregroundStyle(Color.sticksGreen)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.sticksGreen.opacity(0.45), lineWidth: 1)
                )
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    // MARK: - States

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No tournaments yet.")
                .font(SticksFont.display(18))
                .foregroundStyle(Color.sticksInk)
            Text("Start one above, or join a friend's with their invite code.")
                .font(SticksFont.sans(13.5))
                .foregroundStyle(Color.sticksMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading tournaments…")
                .font(SticksFont.sans(14))
                .foregroundStyle(Color.sticksMuted)
        }
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

// MARK: - Tournament card

private struct TournamentCard: View {
    let tournament: TournamentSummary

    var body: some View {
        NavigationLink(value: TournamentRoute(id: tournament.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(tournament.name)
                        .font(SticksFont.display(20))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    TournamentStatusChip(status: tournament.status)
                }

                HStack(spacing: 0) {
                    metaCell(label: "ROUND", value: roundProgress)
                    divider
                    metaCell(label: "PLAYERS", value: "\(tournament.playerCount)")
                    divider
                    metaCell(label: "SCORING", value: tournament.scoringMode.uppercased())

                    Spacer(minLength: 0)

                    Text("→")
                        .font(SticksFont.mono(13))
                        .foregroundStyle(Color.sticksFaint)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var roundProgress: String {
        "\(min(tournament.roundsPlayed, tournament.roundsPlanned))/\(tournament.roundsPlanned)"
    }

    private func metaCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(SticksFont.mono(9))
                .kerning(1)
                .foregroundStyle(Color.sticksFaint)
            Text(value)
                .font(SticksFont.mono(13))
                .foregroundStyle(Color.sticksInk)
        }
        .frame(minWidth: 64, alignment: .leading)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.sticksHairline)
            .frame(width: 1, height: 26)
            .padding(.trailing, 12)
    }
}

// MARK: - Status chip

/// Tournament status pill — LIVE (filled green), UPCOMING (outlined),
/// FINAL (muted). Mirrors the match StatusChip.
struct TournamentStatusChip: View {
    let status: TournamentStatus

    var body: some View {
        Text(label)
            .font(SticksFont.label(10, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(status == .live ? Color.sticksGreen : Color.clear)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
    }

    private var label: String {
        switch status {
        case .live: "LIVE"
        case .upcoming: "UPCOMING"
        case .final: "FINAL"
        }
    }

    private var foreground: Color {
        switch status {
        case .live: .sticksCream
        case .upcoming: .sticksGreen
        case .final: .sticksMuted
        }
    }

    private var border: Color {
        switch status {
        case .live: .clear
        case .upcoming: .sticksGreen
        case .final: .sticksHairline
        }
    }
}
