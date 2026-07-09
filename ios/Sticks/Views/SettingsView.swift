//
//  SettingsView.swift
//  Sticks
//
//  Slice 26: the Settings tab matches the web /settings page — a profile
//  photo card (PhotosPicker upload, downscaled JPEG ≤ 4 MB, remove),
//  an editable profile card (display name, @username), a handicap card
//  (computed Sticks index, index goal, GHIN), and the account card
//  (version + sign out with a confirm). Every successful save re-fetches
//  /me/profile so all dependent lines stay consistent.
//

import PhotosUI
import SwiftUI
import UIKit

struct SettingsView: View {
    let user: User
    let session: SessionStore
    @Binding var tabSelection: SticksTab

    @State private var viewModel = SettingsViewModel()
    @State private var showsCreate = false

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

    // Profile photo picking
    @State private var photoItem: PhotosPickerItem?

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

                        profilePhotoCard
                        profileCard
                        handicapCard
                        accountCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.load(session: session)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeaderBar(
                    title: "Settings",
                    user: user,
                    session: session,
                    showsCreate: $showsCreate
                )
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
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            photoItem = nil
            uploadPickedPhoto(newItem)
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

    /// The "Settings" title now lives in the shared tab header — this
    /// keeps just the identity line at the top of the scroll.
    private var header: some View {
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

    // MARK: - Profile photo card

    private var profilePhotoCard: some View {
        sectionBlock("PROFILE PHOTO") {
            panelCard {
                VStack(spacing: 14) {
                    ZStack {
                        SettingsAvatar(
                            userId: user.id,
                            name: displayName,
                            avatarUrl: viewModel.profile?.avatarUrl,
                            size: 72
                        )
                        .opacity(viewModel.isUploadingAvatar ? 0.35 : 1)

                        if viewModel.isUploadingAvatar {
                            ProgressView()
                                .tint(Color.sticksGreen)
                        }
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(
                            selection: $photoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            photoButtonLabel("CHANGE PHOTO", color: .sticksGreen)
                        }
                        .disabled(viewModel.profile == nil || viewModel.isUploadingAvatar)

                        if viewModel.profile?.avatarUrl != nil {
                            Button {
                                Task { await viewModel.removeAvatar(session: session) }
                            } label: {
                                photoButtonLabel("REMOVE", color: .sticksError)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(viewModel.isUploadingAvatar)
                        }
                    }
                    .opacity(viewModel.profile == nil ? 0.5 : 1)

                    if let error = viewModel.avatarError {
                        Text(error)
                            .font(SticksFont.sans(12))
                            .foregroundStyle(Color.sticksError)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
    }

    private func photoButtonLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(SticksFont.mono(10))
            .kerning(1.1)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color.sticksBg)
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
            .contentShape(.capsule)
    }

    // MARK: - Profile card

    private var profileCard: some View {
        sectionBlock("PROFILE") {
            panelCard {
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

    // MARK: - Photo upload

    /// Loads the picked photo, downscales to ≤1024px on the long edge,
    /// compresses to JPEG under 4 MB, and POSTs the raw bytes.
    private func uploadPickedPhoto(_ item: PhotosPickerItem) {
        Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                viewModel.avatarError = "Couldn't read that photo. Try a different one."
                return
            }

            guard let jpeg = Self.avatarJPEGData(from: image) else {
                viewModel.avatarError = "Couldn't prepare that photo for upload. Try a different one."
                return
            }

            await viewModel.uploadAvatar(jpeg, session: session)
        }
    }

    /// Downscales to a 1024px long edge and steps compression down until
    /// the JPEG fits the server's 4 MB cap.
    private static func avatarJPEGData(from image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        let maxBytes = 4 * 1024 * 1024

        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > 0 ? min(1, maxDimension / longEdge) : 1
        let targetSize = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        var quality: CGFloat = 0.85
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.15
        }
        if let data = resized.jpegData(compressionQuality: 0.25), data.count <= maxBytes {
            return data
        }
        return nil
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
        session: SessionStore(),
        tabSelection: .constant(.settings)
    )
}
