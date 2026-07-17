//
//  GroupMembersView.swift
//  Sticks
//
//  Slice 64: the group Members roster — mirrors the website's Members
//  section. Owner badge, "(you)" marker, join dates; rows with a real
//  username push that member's read-only profile (slice 63), the
//  caller's own row hops to the editable Stats tab, and account-less
//  rows render but stay inert.
//

import SwiftUI
import UIKit

/// Push destination for a group's members roster, registered on the
/// Groups tab's NavigationStack.
struct GroupMembersDestination: Hashable {
    let group: SticksGroup
}

struct GroupMembersView: View {
    let group: SticksGroup
    let session: SessionStore
    /// Called when the caller taps their own row — the owner lands on
    /// the editable Stats tab, not a read-only mirror.
    var onOpenOwnStats: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = GroupMembersViewModel()

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            switch viewModel.phase {
            case .loading:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        titleBlock(count: nil)
                        MembersSkeleton()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
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
        .task {
            await viewModel.load(groupId: group.id, session: session)
        }
    }

    // MARK: - Back chip

    /// "← #GROUPNAME" — long names fall back to "← BACK".
    private var backChip: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Text("←")
                    .layoutPriority(1)

                Text(backLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(SticksFont.mono(11.5))
            .kerning(1.15)
            .foregroundStyle(Color.sticksGreen)
            .frame(maxWidth: 180, alignment: .leading)
            .padding(.leading, 4)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(group.name)")
    }

    private var backLabel: String {
        hashtagName.count > 14 ? "BACK" : "#\(hashtagName)"
    }

    private var hashtagName: String {
        group.name.uppercased().replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBlock(count: viewModel.members.count)

                if viewModel.members.isEmpty {
                    emptyCard
                } else {
                    rosterCard
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

    private func titleBlock(count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Members")
                .font(SticksFont.display(38, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Color.sticksInk)

            (
                Text(group.name)
                    .font(SticksFont.sans(13.5, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                + Text(countSuffix(count))
                    .font(SticksFont.sans(13.5))
                    .foregroundStyle(Color.sticksMuted)
            )
            .lineLimit(1)
        }
    }

    private func countSuffix(_ count: Int?) -> String {
        guard let count else { return "" }
        return count == 1 ? " · 1 member" : " · \(count) members"
    }

    // MARK: - Roster

    private var rosterCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.members.enumerated()), id: \.element.id) { position, member in
                if position > 0 {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                        .padding(.leading, 64)
                }
                memberRow(member)
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    /// Rows with a real username open that member's read-only profile;
    /// the caller's own row hops to the editable Stats tab. Account-less
    /// entries stay inert — never a dead push.
    @ViewBuilder
    private func memberRow(_ member: GroupMemberRow) -> some View {
        if member.isYou {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenOwnStats()
            } label: {
                rowContent(member, isTappable: true)
            }
            .buttonStyle(MemberRowPressStyle())
            .accessibilityHint("Opens your stats")
        } else if let username = member.username, !username.isEmpty {
            NavigationLink(
                value: MemberProfileDestination(username: username, displayName: member.displayName)
            ) {
                rowContent(member, isTappable: true)
            }
            .buttonStyle(MemberRowPressStyle())
            .accessibilityHint("Opens \(member.displayName)'s stats")
        } else {
            rowContent(member, isTappable: false)
        }
    }

    private func rowContent(_ member: GroupMemberRow, isTappable: Bool) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(
                userId: member.userId,
                name: member.displayName,
                avatarUrl: member.avatarUrl,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(member.displayName)
                        .font(SticksFont.sans(15, weight: .bold))
                        .foregroundStyle(Color.sticksInk)
                        .lineLimit(1)

                    if member.isYou {
                        Text("(you)")
                            .font(SticksFont.sans(12.5))
                            .foregroundStyle(Color.sticksMuted)
                    }
                }

                Text(subtitleLine(member))
                    .font(SticksFont.mono(10.5))
                    .foregroundStyle(Color.sticksFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if member.isOwner {
                ownerBadge
            }

            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 60)
        .contentShape(.rect)
    }

    /// "@handle · Joined May 1, 2026" — "No account" for name-only rows.
    private func subtitleLine(_ member: GroupMemberRow) -> String {
        var line = member.username.map { "@\($0)" } ?? "No account"
        if let joined = member.joinedAt {
            line += " · Joined \(joined.formatted(date: .abbreviated, time: .omitted))"
        }
        return line
    }

    private var ownerBadge: some View {
        Text("OWNER")
            .font(SticksFont.mono(9))
            .kerning(1.2)
            .foregroundStyle(Color.sticksGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.sticksGold.opacity(0.12))
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(Color.sticksGold.opacity(0.35), lineWidth: 1)
            )
    }

    // MARK: - States

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No members yet.")
                .font(SticksFont.display(18))
                .foregroundStyle(Color.sticksInk)
            Text("Share the invite code to bring people in.")
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

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
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

// MARK: - Press style

/// Press feedback for tappable roster rows — a faint accent wash.
private struct MemberRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sticksGreen.opacity(0.07) : Color.clear)
    }
}

// MARK: - Avatar

/// Avatar — photo from avatarUrl, else initials on a stable identity
/// color hashed from the userId.
private struct MemberAvatar: View {
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

// MARK: - Skeleton

/// Loading placeholder — pulsing roster rows in the card shell.
private struct MembersSkeleton: View {
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< 5, id: \.self) { position in
                if position > 0 {
                    Rectangle()
                        .fill(Color.sticksHairline)
                        .frame(height: 1)
                        .padding(.leading, 64)
                }
                skeletonRow
            }
        }
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .opacity(isPulsing ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.sticksPanel2)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.sticksPanel2)
                    .frame(width: 120, height: 11)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.sticksPanel2)
                    .frame(width: 170, height: 8)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
    }
}
