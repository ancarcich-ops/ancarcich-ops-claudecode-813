//
//  PeopleView.swift
//  Sticks
//
//  Slice 68: the native /people — find players (debounced open search),
//  approve or decline incoming follow requests, and manage the
//  Following / Followers lists. Rows push the member's read-only
//  profile; every list action is optimistic with revert-on-error.
//

import SwiftUI
import UIKit

/// Push destination for the People screen, registered on the Settings
/// tab's NavigationStack.
struct PeopleDestination: Hashable {}

struct PeopleView: View {
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = PeopleViewModel()
    @State private var searchText = ""

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    searchField

                    if !trimmedQuery.isEmpty {
                        searchSection
                    } else {
                        listsContent
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { backChip }
        }
        .toolbarBackground(Color.sticksBg, for: .navigationBar)
        .tint(Color.sticksGreen)
        .task {
            await viewModel.load(session: session)
        }
        // Debounced search — retyping cancels the pending lookup.
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty else {
                viewModel.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await viewModel.search(trimmedQuery, session: session)
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    // MARK: - Back chip

    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("←")
                    .layoutPriority(1)
                Text("BACK")
            }
            .font(SticksFont.mono(11.5))
            .kerning(1.15)
            .foregroundStyle(Color.sticksGreen)
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    // MARK: - Title + search

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("People")
                .font(SticksFont.display(38, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Color.sticksInk)

            Text("Follow players outside your groups — their rounds show in your feed once they approve.")
                .font(SticksFont.sans(13.5))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sticksFaint)

            TextField("Name, @username, or email", text: $searchText)
                .font(SticksFont.sans(15))
                .foregroundStyle(Color.sticksInk)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.sticksFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchSection: some View {
        if !viewModel.searchResults.isEmpty {
            sectionBlock("RESULTS") {
                listCard {
                    ForEach(Array(viewModel.searchResults.enumerated()), id: \.element.id) { position, result in
                        if position > 0 { hairline }
                        personRow(result.user, subtitle: "@\(result.user.username)") {
                            FollowButton(
                                targetUserId: result.user.id,
                                initialState: result.followState,
                                session: session
                            )
                        }
                    }
                }
            }
        } else if viewModel.isSearching || !viewModel.hasSearched {
            statusCard(icon: nil, text: "Looking…")
        } else {
            statusCard(
                icon: "person.crop.circle.badge.questionmark",
                text: "No one found for “\(trimmedQuery)”. Emails and phone numbers only match exactly."
            )
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private var listsContent: some View {
        switch viewModel.phase {
        case .loading:
            statusCard(icon: nil, text: "Loading…")
        case .failed(let message):
            failedCard(message)
        case .loaded:
            if !viewModel.requests.isEmpty {
                requestsSection
            }
            followingSection
            followersSection
        }
    }

    private var requestsSection: some View {
        sectionBlock("REQUESTS") {
            listCard {
                ForEach(Array(viewModel.requests.enumerated()), id: \.element.id) { position, row in
                    if position > 0 { hairline }
                    personRow(row.user, subtitle: requestSubtitle(row)) {
                        HStack(spacing: 8) {
                            actionChip("ACCEPT", style: .filled) {
                                Task { await viewModel.accept(row, session: session) }
                            }
                            actionChip("DECLINE", style: .ghost) {
                                Task { await viewModel.decline(row, session: session) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func requestSubtitle(_ row: FollowRequestRow) -> String {
        var line = "@\(row.user.username)"
        if let since = row.since {
            line += " · Asked \(since.formatted(date: .abbreviated, time: .omitted))"
        }
        return line
    }

    private var followingSection: some View {
        sectionBlock("FOLLOWING") {
            if viewModel.following.isEmpty {
                emptyCard("You're not following anyone yet. Search for players above.")
            } else {
                listCard {
                    ForEach(Array(viewModel.following.enumerated()), id: \.element.id) { position, user in
                        if position > 0 { hairline }
                        personRow(user, subtitle: "@\(user.username)") {
                            actionChip("UNFOLLOW", style: .ghost) {
                                Task { await viewModel.unfollow(user, session: session) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var followersSection: some View {
        sectionBlock("FOLLOWERS") {
            if viewModel.followers.isEmpty {
                emptyCard("No followers yet.")
            } else {
                listCard {
                    ForEach(Array(viewModel.followers.enumerated()), id: \.element.id) { position, user in
                        if position > 0 { hairline }
                        personRow(user, subtitle: "@\(user.username)") {
                            actionChip("REMOVE", style: .ghost) {
                                Task { await viewModel.removeFollower(user, session: session) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    /// Avatar + name + subtitle push the profile; trailing controls
    /// stay independent buttons.
    private func personRow<Trailing: View>(
        _ user: FollowUser,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            NavigationLink(
                value: MemberProfileDestination(username: user.username, displayName: user.name)
            ) {
                HStack(spacing: 12) {
                    PersonAvatar(
                        userId: user.id,
                        name: user.name,
                        avatarUrl: user.avatarUrl,
                        size: 38
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                            .font(SticksFont.sans(15, weight: .bold))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(SticksFont.mono(10.5))
                            .foregroundStyle(Color.sticksFaint)
                            .lineLimit(1)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(user.name)'s stats")

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 60)
    }

    private enum ChipStyle {
        case filled
        case ghost
    }

    private func actionChip(
        _ title: String,
        style: ChipStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(SticksFont.mono(10))
                .kerning(1.1)
                .foregroundStyle(style == .filled ? Color.sticksCream : Color.sticksMuted)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(style == .filled ? Color.sticksGreen : Color.sticksBg)
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .stroke(style == .filled ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Pieces

    private func sectionBlock<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(SticksFont.mono(10))
                .kerning(1.2)
                .foregroundStyle(Color.sticksFaint)
                .padding(.leading, 2)

            content()
        }
    }

    private func listCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.sticksHairline)
            .frame(height: 1)
            .padding(.leading, 64)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.sans(13.5))
            .foregroundStyle(Color.sticksMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
    }

    private func statusCard(icon: String?, text: String) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sticksMuted)
            } else {
                ProgressView()
                    .tint(Color.sticksGreen)
            }

            Text(text)
                .font(SticksFont.sans(13.5))
                .foregroundStyle(Color.sticksMuted)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private func failedCard(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
            Text(message)
                .font(SticksFont.sans(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.sticksInk)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Avatar

/// Avatar — photo from avatarUrl, else initials on a stable identity
/// color hashed from the userId (same convention as everywhere else).
private struct PersonAvatar: View {
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
