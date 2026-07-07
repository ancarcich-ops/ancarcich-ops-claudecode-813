//
//  SettingsViewModel.swift
//  Sticks
//
//  Slice 21: loads GET /me/profile and posts profile edits (display name,
//  GHIN via POST /me/profile) and the index goal (POST /me/target-index).
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
