//
//  GroupsViewModel.swift
//  Sticks
//
//  Loads GET /groups and drives the create / join-with-code flows.
//  Created and joined groups are inserted locally so the list updates
//  immediately without a refetch.
//

import Foundation
import Observation

@Observable
final class GroupsViewModel {
    enum Phase: Equatable {
        /// First load with nothing cached yet.
        case loading
        /// Groups loaded (possibly empty).
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var groups: [SticksGroup] = []

    private(set) var isCreating = false
    private(set) var isJoining = false
    /// Server error from the last failed join (shown verbatim).
    private(set) var joinError: String?
    /// Error from the last failed create.
    private(set) var createError: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fetches groups. A 401 signs the user out; other failures only
    /// surface as a full-screen error when there's nothing to show yet.
    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if groups.isEmpty, phase != .loaded { phase = .loading }
        do {
            let response = try await api.groups(token: token)
            groups = response.groups
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if groups.isEmpty { phase = .failed(error.message) }
        } catch {
            if groups.isEmpty {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }

    /// Creates a group and inserts its card. Returns true on success.
    func create(name: String, session: SessionStore) async -> Bool {
        guard let token = session.token else {
            session.signOut()
            return false
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        do {
            let response = try await api.createGroup(name: name, token: token)
            insert(response.group)
            return true
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return false
        } catch let error as APIError {
            createError = error.message
            return false
        } catch {
            createError = "Can't reach Sticks. Check your connection and try again."
            return false
        }
    }

    /// Joins via invite code and inserts the card. Returns true on
    /// success; on failure `joinError` carries the server's message.
    func join(code: String, session: SessionStore) async -> Bool {
        guard let token = session.token else {
            session.signOut()
            return false
        }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let response = try await api.joinGroup(code: code, token: token)
            insert(response.group)
            return true
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return false
        } catch let error as APIError {
            joinError = error.message
            return false
        } catch {
            joinError = "Can't reach Sticks. Check your connection and try again."
            return false
        }
    }

    func clearJoinError() {
        joinError = nil
    }

    /// Adds (or replaces) a group at the top of the list.
    private func insert(_ group: SticksGroup) {
        groups.removeAll { $0.id == group.id }
        groups.insert(group, at: 0)
        phase = .loaded
    }
}
