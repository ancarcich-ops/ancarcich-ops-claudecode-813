//
//  ReactionListSheet.swift
//  Sticks
//
//  The who-reacted sheet: long-press a used reaction chip on the round
//  page to see the people behind that emoji's tally. Backed by
//  GET /matches/:id/reactions?target=… (docs/reactions-who-reacted-spec.md)
//  — until the endpoint ships, the sheet reports the fetch failure and
//  offers a retry.
//

import SwiftUI

struct ReactionListSheet: View {
    let matchId: String
    /// "round" or "hole:<matchPlayerId>:<hole>" — the long-pressed chip's target.
    let targetKey: String
    /// The chip the sheet was opened from — its group pins to the top
    /// so the answer to the tap is the first thing on screen.
    let emoji: String
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var tallies: [ReactionTallyWithUsers] = []

    private enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    /// The opened emoji's group first, then biggest tally first.
    private var orderedTallies: [ReactionTallyWithUsers] {
        tallies
            .filter { $0.count > 0 && !$0.users.isEmpty }
            .sorted {
                if $0.emoji == emoji { return true }
                if $1.emoji == emoji { return false }
                return $0.count > $1.count
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .failed(let message):
                    failedView(message)
                case .loaded:
                    listView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.sticksBg)
            .navigationTitle("Reacted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        phase = .loading
        do {
            let response = try await APIClient.shared.reactionUsers(
                matchId: matchId,
                targetKey: targetKey,
                token: token
            )
            tallies = response.tallies
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            // 405 means the server hasn't shipped the who-reacted route
            // yet (docs/reactions-who-reacted-spec.md) — say so instead
            // of a bare status code.
            if error.statusCode == 405 {
                phase = .failed("Seeing who reacted isn't available yet — it needs a Sticks server update.")
            } else {
                phase = .failed(error.message)
            }
        } catch {
            phase = .failed("Can't reach Sticks. Check your connection and try again.")
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.sticksGreen)
            Text("Loading reactions…")
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var listView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if orderedTallies.isEmpty {
                    Text("Nobody has reacted here yet.")
                        .font(SticksFont.sans(13))
                        .foregroundStyle(Color.sticksMuted)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                }
                ForEach(Array(orderedTallies.enumerated()), id: \.element.emoji) { index, group in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.sticksHairline.opacity(0.6))
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                    emojiGroup(group)
                }
            }
        }
    }

    private func emojiGroup(_ group: ReactionTallyWithUsers) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(group.emoji)
                    .font(.system(size: 17))
                Text(RecapFormat.countLabel(group.count, "reacted", "reacted"))
                    .font(SticksFont.mono(11, weight: .semibold))
                    .kerning(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.sticksMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)

            ForEach(group.users) { user in
                HStack(spacing: 10) {
                    avatar(for: user)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .font(SticksFont.sans(14, weight: .semibold))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)
                        if let handle = user.handle, !handle.isEmpty {
                            Text("@\(handle)")
                                .font(SticksFont.mono(11))
                                .kerning(0.4)
                                .foregroundStyle(Color.sticksMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func avatar(for user: ReactionUser) -> some View {
        if let urlString = user.avatarUrl, let url = URL(string: urlString) {
            RemoteAvatarImage(url: url) {
                Circle().fill(Color.sticksPanel2)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.sticksHairline, lineWidth: 1))
        } else {
            Circle()
                .fill(Color.sticksPanel2)
                .overlay(
                    Text(String(user.displayName.first ?? "?").uppercased())
                        .font(SticksFont.mono(12, weight: .semibold))
                        .foregroundStyle(Color.sticksMuted)
                )
                .overlay(Circle().stroke(Color.sticksHairline, lineWidth: 1))
                .frame(width: 32, height: 32)
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksMuted)
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("TRY AGAIN")
                    .font(SticksFont.label(12, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksCream)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.sticksGreen)
                    .clipShape(.capsule)
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 24)
    }
}
