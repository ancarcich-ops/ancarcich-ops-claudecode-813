//
//  SettingsView.swift
//  Sticks
//
//  Slice 21: the Settings tab mirrors the web profile — an editable
//  profile card (avatar, display name, @username), a handicap card
//  (computed Sticks index, index goal, GHIN), and the account card
//  (version + sign out with a confirm). Every successful save re-fetches
//  /me/profile so all dependent lines stay consistent.
//

import SwiftUI

struct SettingsView: View {
    let user: User
    let session: SessionStore
    var tabSelection: Binding<SticksTab>? = nil

    @State private var viewModel = SettingsViewModel()

    // Display name editing
    @State private var showsNameAlert = false
    @State private var nameText = ""

    // GHIN editing
    @State private var showsGhinAlert = false
    @State private var ghinText = ""

    // Index goal editing
    @State private var showsGoalAlert = false
    @State private var goalText = ""

    // Sign out confirm + save errors
    @State private var showsSignOutConfirm = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header

                        if let loadError = viewModel.loadError, viewModel.profile == nil {
                            loadErrorCard(loadError)
                        }

                        profileCard
                        handicapCard
                        accountCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.load(session: session)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let tabSelection {
                    SticksTabBar(selection: tabSelection)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load(session: session)
        }
        .alert("Edit display name", isPresented: $showsNameAlert) {
            TextField(username, text: $nameText)
            Button("Save") { saveDisplayName() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Up to 40 characters. Leave it empty to go by @\(username).")
        }
        .alert("Edit GHIN number", isPresented: $showsGhinAlert) {
            TextField("1234567", text: $ghinText)
                .keyboardType(.numberPad)
            Button("Save") { saveGhin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("6–10 digits. Leave it empty to clear.")
        }
        .alert("Set index goal", isPresented: $showsGoalAlert) {
            TextField("9.0", text: $goalText)
                .keyboardType(.numbersAndPunctuation)
            Button("Save") { saveGoal() }
            if viewModel.profile?.targetIndex != nil {
                Button("Clear goal", role: .destructive) { postGoal(nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your target Sticks index — it shows on the stats hero card with how far there is to go.")
        }
        .alert("Sign out of Sticks?", isPresented: $showsSignOutConfirm) {
            Button("Sign out", role: .destructive) { session.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any active round session ends on this device.")
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Derived values (profile with session fallbacks)

    private var username: String {
        let value = viewModel.profile?.username ?? ""
        return value.isEmpty ? user.username : value
    }

    /// Effective display name — the profile's custom name, else @username.
    private var displayName: String {
        if let custom = viewModel.profile?.displayName, !custom.isEmpty {
            return custom
        }
        if viewModel.profile != nil { return username }
        return user.displayName.isEmpty ? user.username : user.displayName
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(SticksFont.display(40, weight: .bold))
                .kerning(-0.8)
                .foregroundStyle(Color.sticksInk)

            (
                Text("@\(username)")
                    .font(SticksFont.mono(12))
                    .foregroundStyle(Color.sticksGreen)
                + Text(" · \(displayName)")
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksMuted)
            )
            .lineLimit(1)
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        sectionBlock("PROFILE") {
            panelCard {
                avatarRow
                hairline

                editableRow(
                    label: "DISPLAY NAME",
                    value: displayName,
                    disabled: viewModel.profile == nil || viewModel.isSaving
                ) {
                    nameText = viewModel.profile?.displayName ?? ""
                    showsNameAlert = true
                }

                hairline
                readOnlyRow(label: "USERNAME", value: "@\(username)", mono: true)
            }
        }
    }

    private var avatarRow: some View {
        HStack(spacing: 14) {
            SettingsAvatar(
                userId: user.id,
                name: displayName,
                avatarUrl: viewModel.profile?.avatarUrl,
                size: 56
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(SticksFont.sans(16, weight: .bold))
                    .foregroundStyle(Color.sticksInk)
                    .lineLimit(1)

                Text("PHOTO EDITS ON THE WEB")
                    .font(SticksFont.mono(8.5))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksFaint)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Handicap card

    private var handicapCard: some View {
        sectionBlock("HANDICAP") {
            panelCard {
                indexRow
                hairline

                editableRow(
                    label: "GOAL",
                    value: goalValueText,
                    valueColor: viewModel.profile?.targetIndex != nil ? .sticksInk : .sticksFaint,
                    disabled: viewModel.profile == nil || viewModel.isSaving
                ) {
                    goalText = viewModel.profile?.targetIndex
                        .map { String(format: "%.1f", $0) } ?? ""
                    showsGoalAlert = true
                }

                hairline

                editableRow(
                    label: "GHIN",
                    value: ghinValueText,
                    valueColor: viewModel.profile?.ghin != nil ? .sticksInk : .sticksFaint,
                    disabled: viewModel.profile == nil || viewModel.isSaving
                ) {
                    ghinText = viewModel.profile?.ghin ?? ""
                    showsGhinAlert = true
                }
            }
        }
    }

    private var indexRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("STICKS INDEX")
                .font(SticksFont.mono(10))
                .kerning(1)
                .foregroundStyle(Color.sticksFaint)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                if let index = viewModel.profile?.computedIndex {
                    Text(String(format: "%+.1f", index))
                        .font(SticksFont.display(24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.sticksGreen)
                } else {
                    Text("pending")
                        .font(SticksFont.displayItalic(18))
                        .foregroundStyle(Color.sticksMuted)
                }

                if let profile = viewModel.profile, profile.totalRounds > 0 {
                    Text("FROM \(profile.indexFromRounds) OF \(profile.totalRounds) ROUNDS")
                        .font(SticksFont.mono(9))
                        .kerning(0.6)
                        .foregroundStyle(Color.sticksFaint)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var goalValueText: String {
        guard let target = viewModel.profile?.targetIndex else { return "Not set" }
        return String(format: "TARGET %.1f", target)
    }

    private var ghinValueText: String {
        guard let ghin = viewModel.profile?.ghin, !ghin.isEmpty else { return "Not set" }
        return "#\(ghin)"
    }

    // MARK: - Account card

    private var accountCard: some View {
        sectionBlock("ACCOUNT") {
            panelCard {
                readOnlyRow(label: "VERSION", value: Self.versionText)
                hairline

                Button {
                    showsSignOutConfirm = true
                } label: {
                    Text("SIGN OUT")
                        .font(SticksFont.mono(12))
                        .kerning(1.2)
                        .foregroundStyle(Color.sticksError)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(.rect)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }

    // MARK: - Save actions

    private func saveDisplayName() {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40 else {
            saveError = "Display names are 40 characters max."
            return
        }
        Task {
            if let error = await viewModel.saveDisplayName(trimmed, session: session) {
                saveError = error
            }
        }
    }

    private func saveGhin() {
        let trimmed = ghinText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let isDigits = trimmed.allSatisfy(\.isNumber)
            guard isDigits, (6 ... 10).contains(trimmed.count) else {
                saveError = "GHIN numbers are 6–10 digits."
                return
            }
        }
        Task {
            if let error = await viewModel.saveGhin(trimmed, session: session) {
                saveError = error
            }
        }
    }

    private func saveGoal() {
        let normalized = goalText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized) else { return }
        postGoal(value)
    }

    private func postGoal(_ value: Double?) {
        Task {
            if let error = await viewModel.setTargetIndex(value, session: session) {
                saveError = error
            }
        }
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

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private func readOnlyRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(SticksFont.mono(10))
                .kerning(1)
                .foregroundStyle(Color.sticksFaint)
            Spacer()
            Text(value)
                .font(mono ? SticksFont.mono(13) : SticksFont.sans(15, weight: .medium))
                .foregroundStyle(mono ? Color.sticksFaint : Color.sticksInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func editableRow(
        label: String,
        value: String,
        valueColor: Color = .sticksInk,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksFaint)

                Spacer()

                Text(value)
                    .font(SticksFont.sans(15, weight: .medium))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)

                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.sticksHairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func loadErrorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.sticksMuted)

            Text(message)
                .font(SticksFont.sans(13))
                .foregroundStyle(Color.sticksInk)

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.load(session: session) }
            } label: {
                Text("RETRY")
                    .font(SticksFont.mono(10))
                    .kerning(1)
                    .foregroundStyle(Color.sticksGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    private static var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Avatar

/// Avatar — photo from avatarUrl, else initials on the user's stable
/// identity color (same FNV-1a hash as everywhere else).
private struct SettingsAvatar: View {
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
                .font(SticksFont.label(size * 0.36, weight: .bold))
                .foregroundStyle(Color.sticksCream)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

#Preview {
    SettingsView(
        user: User(id: "1", username: "tj", displayName: "Tj"),
        session: SessionStore()
    )
}
