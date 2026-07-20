//
//  SettingsViewModel.swift
//  Sticks
//
//  Slice 26: loads GET /me/profile and posts profile edits (display name,
//  GHIN via POST /me/profile), the index goal (POST /me/target-index),
//  and the profile photo (POST/DELETE /me/avatar with raw JPEG bytes).
//  Every successful save re-fetches the profile so all dependent lines
//  stay consistent. Refreshes keep the previous profile on transient
//  failures.
//

import Foundation
import Observation

@Observable
final class SettingsViewModel {
    private(set) var profile: UserProfile?
    /// First-load failure message — nil once a profile has ever loaded.
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isUploadingAvatar = false
    /// Inline avatar error — server messages shown verbatim under the
    /// photo card. Cleared on the next avatar action.
    var avatarError: String?

    // Slice 68 — follow settings, seeded from GET /follows.
    private(set) var autoAcceptFollows = false
    /// My searchable phone (last-10 digits) — nil when unset.
    private(set) var followPhone: String?
    /// Pending incoming follow requests — the People row's badge.
    private(set) var followRequestCount = 0
    /// True once GET /follows has succeeded — the controls stay
    /// disabled until the seed values are real.
    private(set) var followsLoaded = false

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if profile == nil { isLoading = true }
        defer { isLoading = false }
        do {
            profile = try await api.profile(token: token).profile
            loadError = nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if profile == nil { loadError = error.message }
        } catch {
            if profile == nil {
                loadError = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }

    /// GET /follows — seeds the auto-accept toggle, phone, and the
    /// People badge. Quiet on transient failures (the section just
    /// stays disabled until a refresh succeeds).
    func loadFollows(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        do {
            let response = try await api.getFollows(token: token)
            autoAcceptFollows = response.autoAcceptFollows
            followPhone = response.phone
            followRequestCount = response.requests.count
            followsLoaded = true
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch {
            // Keep previous values; a pull-to-refresh retries.
        }
    }

    /// POSTs the auto-accept toggle, optimistically. Returns a
    /// user-facing error message (with the flip reverted), or nil.
    func setAutoAccept(_ on: Bool, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        let prior = autoAcceptFollows
        autoAcceptFollows = on
        do {
            try await api.followAction("setAutoAccept", on: on, token: token)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            autoAcceptFollows = prior
            return error.message
        } catch {
            autoAcceptFollows = prior
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// POSTs the searchable phone ("" removes it). Returns a
    /// user-facing error message, or nil on success.
    func setPhone(_ phone: String, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await api.followAction("setPhone", phone: phone, token: token)
            followPhone = response.phone
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// POSTs a display name ("" clears to @username) and re-fetches.
    /// Returns a user-facing error message, or nil on success.
    func saveDisplayName(_ value: String, session: SessionStore) async -> String? {
        await update(displayName: value, ghinNumber: nil, session: session)
    }

    /// POSTs a GHIN number ("" clears) and re-fetches.
    /// Returns a user-facing error message, or nil on success.
    func saveGhin(_ value: String, session: SessionStore) async -> String? {
        await update(displayName: nil, ghinNumber: value, session: session)
    }

    /// POSTs the index goal (nil clears it) and re-fetches the profile.
    /// Returns a user-facing error message, or nil on success.
    func setTargetIndex(_ value: Double?, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await api.setTargetIndex(value, token: token)
            await load(session: session)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// POSTs raw JPEG bytes to /me/avatar and re-fetches on success.
    /// Failures land in `avatarError` (server messages verbatim).
    func uploadAvatar(_ jpegData: Data, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        isUploadingAvatar = true
        avatarError = nil
        defer { isUploadingAvatar = false }
        do {
            _ = try await api.uploadAvatar(jpegData: jpegData, token: token)
            await load(session: session)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            avatarError = error.message
        } catch {
            avatarError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    /// DELETEs /me/avatar — the profile falls back to the initials bubble.
    func removeAvatar(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        isUploadingAvatar = true
        avatarError = nil
        defer { isUploadingAvatar = false }
        do {
            try await api.deleteAvatar(token: token)
            await load(session: session)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            avatarError = error.message
        } catch {
            avatarError = "Can't reach Sticks. Check your connection and try again."
        }
    }

    private func update(displayName: String?, ghinNumber: String?, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            profile = try await api.updateProfile(
                displayName: displayName,
                ghinNumber: ghinNumber,
                token: token
            ).profile
            // Re-fetch so every dependent line stays consistent even if the
            // POST response is ever slimmer than the GET.
            await load(session: session)
            return nil
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return "Can't reach Sticks. Check your connection and try again."
        }
    }
}
