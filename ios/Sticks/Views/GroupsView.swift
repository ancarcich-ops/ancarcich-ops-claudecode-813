//
//  GroupsView.swift
//  Sticks
//
//  Slice 12: the Groups tab. Group cards with a deterministic identity
//  color spine, the invite ticket footer (tap = copy the code + join
//  link), plus Create and Join cards. Card top rows push the group feed.
//

import SwiftUI
import UIKit

struct GroupsView: View {
    let user: User
    let session: SessionStore
    @Binding var tabSelection: SticksTab

    @State private var viewModel = GroupsViewModel()
    @State private var showsCreate = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeaderBar(
                    title: "Groups",
                    user: user,
                    session: session,
                    showsCreate: $showsCreate,
                    tabSelection: $tabSelection
                )
            }
            .navigationDestination(for: SticksGroup.self) { group in
                GroupFeedView(group: group, session: session)
            }
            .navigationDestination(for: LeaderboardDestination.self) { destination in
                GroupLeaderboardView(
                    group: destination.group,
                    session: session,
                    onOpenOwnStats: { tabSelection = .stats }
                )
            }
            // Slice 64: the group's Members roster — reached from the
            // card's "N members" / avatar stack and the feed header.
            .navigationDestination(for: GroupMembersDestination.self) { destination in
                GroupMembersView(
                    group: destination.group,
                    session: session,
                    onOpenOwnStats: { tabSelection = .stats }
                )
            }
            // Slice 63: a member's read-only stats profile. If it
            // resolves to the caller, pop it and hop to the Stats tab.
            .navigationDestination(for: MemberProfileDestination.self) { destination in
                MemberProfileView(
                    username: destination.username,
                    fallbackName: destination.displayName,
                    session: session,
                    onOpenOwnStats: {
                        if !path.isEmpty { path.removeLast() }
                        tabSelection = .stats
                    }
                )
            }
            .navigationDestination(for: MatchSummary.self) { match in
                MatchDetailView(match: match, session: session)
            }
            // Slice 55: tournaments — the list, and detail by id (so
            // fresh create/join responses can push straight in).
            .navigationDestination(for: TournamentsDestination.self) { _ in
                TournamentsListView(user: user, session: session) { id in
                    path.append(TournamentRoute(id: id))
                }
            }
            .navigationDestination(for: TournamentRoute.self) { route in
                TournamentDetailView(tournamentId: route.id, user: user, session: session)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showsCreate) {
            CreateMatchView(user: user, session: session) { matchId in
                handleCreated(matchId)
            }
        }
        .task {
            await viewModel.load(session: session)
        }
        // Slice 37: the header switcher's "{group} leaderboard" link —
        // the menu flips to this tab and we push the leaderboard.
        .onReceive(NotificationCenter.default.publisher(for: .sticksOpenGroupLeaderboard)) { note in
            guard let groupId = note.userInfo?["groupId"] as? String else { return }
            let known = viewModel.groups.isEmpty ? GroupFilterStore.shared.groups : viewModel.groups
            guard let group = known.first(where: { $0.id == groupId }) else { return }
            path.append(LeaderboardDestination(group: group))
        }
    }

    /// A round created away from Home: refresh feeds, hop to the Home
    /// tab, and let it push the new match's detail (its create flow).
    private func handleCreated(_ matchId: String) {
        showsCreate = false
        NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
        tabSelection = .home
        NotificationCenter.default.post(
            name: .sticksOpenMatch,
            object: nil,
            userInfo: ["matchId": matchId]
        )
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("A group is a private feed. Matches you post are seen only by members. Share an invite code to add friends.")
                    .font(SticksFont.sans(14.5))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(maxWidth: 280, alignment: .leading)

                sectionHeader

                if viewModel.groups.isEmpty {
                    emptyCard
                } else {
                    VStack(spacing: 13) {
                        ForEach(viewModel.groups) { group in
                            GroupCard(group: group)
                        }
                    }
                }

                TournamentsEntryCard()

                CreateGroupCard(viewModel: viewModel, session: session)
                JoinGroupCard(viewModel: viewModel, session: session)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable {
            await viewModel.load(session: session)
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Your groups")
                .font(SticksFont.display(19))
                .foregroundStyle(Color.sticksInk)

            Spacer()

            Text(countText)
                .font(SticksFont.mono(12))
                .kerning(1)
                .textCase(.uppercase)
                .foregroundStyle(Color.sticksFaint)
        }
        .padding(.top, 4)
    }

    private var countText: String {
        let count = viewModel.groups.count
        return count == 1 ? "1 GROUP" : "\(count) GROUPS"
    }

    // MARK: - States

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No groups yet.")
                .font(SticksFont.display(18))
                .foregroundStyle(Color.sticksInk)
            Text("Spin one up below or drop in an invite code from a friend.")
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
            Text("Loading groups…")
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

// MARK: - Group identity

/// Deterministic identity color per group — FNV-1a over the id (stable
/// across launches, unlike String.hashValue) cycling the 5-color wheel.
nonisolated enum GroupIdentity {
    static let palette: [Color] = [
        .sticksGreen,
        .sticksGold,
        Color(red: 50 / 255, green: 74 / 255, blue: 99 / 255),   // navy #324A63
        .sticksError,
        Color(red: 155 / 255, green: 90 / 255, blue: 107 / 255), // rose #9B5A6B
    ]

    static func color(for id: String) -> Color {
        palette[index(for: id)]
    }

    static func index(for id: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(palette.count))
    }

    /// Copies the invite line to the pasteboard: "CODE — join link".
    @MainActor static func copyInvite(code: String) {
        UIPasteboard.general.string =
            "\(code) — https://sticks-golf.vercel.app/groups/join?code=\(code)"
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Tournaments entry (slice 55)

/// Pushes the tournaments list — the Groups tab is the home of
/// everything social, so multi-round events live behind this row.
private struct TournamentsEntryCard: View {
    var body: some View {
        NavigationLink(value: TournamentsDestination()) {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.sticksGold)
                    .frame(width: 46, height: 46)
                    .background(Color.sticksGold.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Tournaments")
                            .font(SticksFont.display(20))
                            .foregroundStyle(Color.sticksInk)

                        Text("→")
                            .font(SticksFont.mono(12))
                            .foregroundStyle(Color.sticksFaint)
                    }

                    Text("Multi-round events · cumulative leaderboard")
                        .font(SticksFont.mono(12))
                        .foregroundStyle(Color.sticksMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sticksFaint)
            }
            .padding(14)
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
        .buttonStyle(GroupCardPressStyle())
    }
}

// MARK: - Group card

private struct GroupCard: View {
    let group: SticksGroup

    @State private var showsCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var spine: Color { GroupIdentity.color(for: group.id) }

    var body: some View {
        VStack(spacing: 0) {
            topRow

            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)

            footer
        }
        .background(Color.sticksCard)
        .overlay(alignment: .leading) {
            spine.frame(width: 5).allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
        .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: Top row

    /// Slice 64: sibling tap targets — the identity (monogram + name)
    /// opens the group feed, while "N members" and the avatar stack
    /// open the Members roster. A members link can't nest inside a
    /// feed link, so the row is split instead of wrapped whole.
    private var topRow: some View {
        HStack(spacing: 12) {
            NavigationLink(value: group) {
                monogram
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name) feed")

            VStack(alignment: .leading, spacing: 3) {
                NavigationLink(value: group) {
                    HStack(spacing: 6) {
                        Text(group.name)
                            .font(SticksFont.display(20))
                            .foregroundStyle(Color.sticksInk)
                            .lineLimit(1)

                        Text("→")
                            .font(SticksFont.mono(12))
                            .foregroundStyle(Color.sticksFaint)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name) feed")

                metaLine
            }

            Spacer(minLength: 8)

            NavigationLink(value: GroupMembersDestination(group: group)) {
                avatarStack
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Group members")
        }
        .padding(.leading, 19) // 14 + the 5pt spine
        .padding(.trailing, 14)
        .padding(.vertical, 14)
    }

    private var monogram: some View {
        Text(group.initials)
            .font(SticksFont.display(20))
            .foregroundStyle(Color.sticksCream)
            .frame(width: 46, height: 46)
            .background(spine)
            .clipShape(.rect(cornerRadius: 13))
            .overlay(
                // Subtle inner shadow — a soft dark rim inside the top edge.
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 1.5)
                    .blur(radius: 1.5)
                    .clipShape(.rect(cornerRadius: 13))
                    .allowsHitTesting(false)
            )
    }

    /// "8 members › · 24 matches" — the members segment is its own
    /// link to the roster (green = tappable); matches stay plain text.
    private var metaLine: some View {
        HStack(spacing: 0) {
            NavigationLink(value: GroupMembersDestination(group: group)) {
                Text(group.memberCount == 1 ? "1 member ›" : "\(group.memberCount) members ›")
                    .font(SticksFont.mono(12))
                    .foregroundStyle(Color.sticksGreen)
                    .lineLimit(1)
                    .padding(.vertical, 2)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Group members")

            (
                Text(" · ").foregroundStyle(Color.sticksMuted)
                + Text("\(group.matchCount)").foregroundStyle(Color.sticksInk)
                + Text(group.matchCount == 1 ? " match" : " matches").foregroundStyle(Color.sticksMuted)
            )
            .font(SticksFont.mono(12))
            .lineLimit(1)
        }
    }

    private var avatarStack: some View {
        let names = Array(group.memberNames.prefix(3))
        let overflow = group.memberCount - names.count
        return HStack(spacing: -8) {
            ForEach(Array(names.enumerated()), id: \.offset) { position, name in
                MemberBubble(name: name, position: position)
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(SticksFont.mono(10))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 26, height: 26)
                    .background(Color.sticksPanel2)
                    .clipShape(.circle)
                    .overlay(Circle().stroke(Color.sticksCard, lineWidth: 2))
            }
        }
    }

    // MARK: Footer (LEADERBOARD | ticket)

    /// The design handoff's split footer: LEADERBOARD (flex 1) | 1pt
    /// hairline | the invite ticket (flex 1.15).
    private var footer: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                leaderboardButton
                    .frame(width: (proxy.size.width - 1) / 2.15)

                Rectangle()
                    .fill(Color.sticksHairline)
                    .frame(width: 1)

                inviteTicket
            }
        }
        .frame(height: 46)
    }

    /// Pushes the group leaderboard. Disabled (no tap, 50% opacity)
    /// until the group has at least one match.
    private var leaderboardButton: some View {
        NavigationLink(value: LeaderboardDestination(group: group)) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Leaderboard")
                    .font(SticksFont.sans(13.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.sticksGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .padding(.leading, 5) // visually center past the spine
            .contentShape(.rect)
        }
        .buttonStyle(LeaderboardPressStyle())
        .disabled(group.matchCount == 0)
        .opacity(group.matchCount == 0 ? 0.5 : 1)
        .accessibilityLabel("Group leaderboard")
    }

    // MARK: Invite ticket

    private var inviteTicket: some View {
        Button {
            guard !showsCopied else { return }
            GroupIdentity.copyInvite(code: group.inviteCode)
            withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
            copyResetTask?.cancel()
            copyResetTask = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { showsCopied = false }
            }
        } label: {
            ZStack {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INVITE CODE")
                            .font(SticksFont.mono(8.5))
                            .kerning(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.sticksFaint)

                        Text(group.inviteCode)
                            .font(SticksFont.mono(13.5))
                            .kerning(1.9)
                            .foregroundStyle(Color.sticksInk)
                    }

                    copyChip
                }
                .opacity(showsCopied ? 0 : 1)

                if showsCopied {
                    Text("✓ Copied")
                        .font(SticksFont.sans(13, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy invite code \(group.inviteCode)")
    }

    private var copyChip: some View {
        Image(systemName: showsCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(showsCopied ? Color.sticksCream : Color.sticksMuted)
            .frame(width: 24, height: 24)
            .background(showsCopied ? Color.sticksGreen : Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 7))
    }
}

/// 26pt initials circle for the member stack — identity colors by
/// position, 2pt panel ring, -8pt overlap handled by the stack.
private struct MemberBubble: View {
    let name: String
    let position: Int

    var body: some View {
        Text(initials)
            .font(SticksFont.label(9, weight: .bold))
            .foregroundStyle(Color.sticksCream)
            .frame(width: 26, height: 26)
            .background(GroupIdentity.palette[position % GroupIdentity.palette.count])
            .clipShape(.circle)
            .overlay(Circle().stroke(Color.sticksCard, lineWidth: 2))
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

private struct GroupCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sticksPanel2.opacity(0.6) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// LEADERBOARD footer press feedback — accent 10% background.
private struct LeaderboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.sticksGreen.opacity(0.1) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Create card

private struct CreateGroupCard: View {
    let viewModel: GroupsViewModel
    let session: SessionStore

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isCreating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("START SOMETHING")
                .font(SticksFont.mono(10.5))
                .kerning(1.47)
                .foregroundStyle(Color.sticksGreen)

            Text("Create a group")
                .font(SticksFont.display(18))
                .foregroundStyle(Color.sticksInk)

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $name,
                    prompt: Text("Saturday foursome, College buddies…")
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksFaint)
                )
                .font(SticksFont.sans(15))
                .foregroundStyle(Color.sticksInk)
                .focused($isFocused)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
                )
                .shadow(
                    color: isFocused ? Color.sticksGreen.opacity(0.25) : .clear,
                    radius: 5
                )

                Button {
                    create()
                } label: {
                    Text("CREATE")
                        .font(SticksFont.sans(15, weight: .bold))
                        .foregroundStyle(Color.sticksCream)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                }
                .buttonStyle(LedgeButtonStyle(showsLedge: canCreate))
                .disabled(!canCreate)
                .opacity(canCreate ? 1 : 0.5)
            }

            if let error = viewModel.createError {
                Text(error)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
            }

            (
                Text("You'll get an invite code to share. ")
                    .foregroundStyle(Color.sticksMuted)
                + Text("Anyone with the code can join.")
                    .font(SticksFont.sans(12.5, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
            )
            .font(SticksFont.sans(12.5))
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

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            if await viewModel.create(name: trimmed, session: session) {
                name = ""
                isFocused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// Accent-filled button sitting on a 2pt darker-green "ledge" that
/// compresses on press. No ledge when disabled.
private struct LedgeButtonStyle: ButtonStyle {
    let showsLedge: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && showsLedge
        return ZStack {
            if showsLedge {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.sticksGreenDark)
                    .offset(y: 2)
            }
            configuration.label
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 12))
                .offset(y: pressed ? 2 : 0)
        }
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Join card

private struct JoinGroupCard: View {
    let viewModel: GroupsViewModel
    let session: SessionStore

    @State private var code = ""
    @FocusState private var isFocused: Bool

    private var canJoin: Bool {
        code.count == 6 && !viewModel.isJoining
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOT AN INVITE?")
                .font(SticksFont.mono(10.5))
                .kerning(1.47)
                .foregroundStyle(Color.sticksGreen)

            Text("Join with a code")
                .font(SticksFont.display(18))
                .foregroundStyle(Color.sticksInk)

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $code,
                    prompt: Text("ABC123")
                        .font(SticksFont.mono(15))
                        .foregroundStyle(Color.sticksFaint)
                )
                .font(SticksFont.mono(15))
                .kerning(3)
                .foregroundStyle(Color.sticksInk)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.join)
                .onChange(of: code) { _, newValue in
                    // Hard 6-char cap, auto-uppercased.
                    let cleaned = String(newValue.uppercased().prefix(6))
                    if cleaned != newValue { code = cleaned }
                    if viewModel.joinError != nil { viewModel.clearJoinError() }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
                )
                .shadow(
                    color: isFocused ? Color.sticksGreen.opacity(0.25) : .clear,
                    radius: 5
                )

                Button {
                    join()
                } label: {
                    Text("JOIN")
                        .font(SticksFont.sans(15, weight: .bold))
                        .foregroundStyle(Color.sticksGreen)
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .background(Color.sticksPanel2)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.sticksHairline, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canJoin)
                .opacity(canJoin ? 1 : 0.5)
            }

            if let error = viewModel.joinError {
                Text(error)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
            }
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

    private func join() {
        guard code.count == 6 else { return }
        Task {
            if await viewModel.join(code: code, session: session) {
                code = ""
                isFocused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

#Preview {
    GroupsView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore(),
        tabSelection: .constant(.groups)
    )
}
