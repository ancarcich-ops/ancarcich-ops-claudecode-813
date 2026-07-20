//
//  PeopleViewModel.swift
//  Sticks
//
//  Slice 68: drives the People screen — GET /follows for the
//  requests / following / followers sections, GET /users/search for
//  the debounced people search, and POST /follows for accept /
//  decline / unfollow / remove. Actions apply OPTIMISTICALLY and
//  revert (with a user-facing message) on failure.
//

import Foundation
import Observation

@Observable
final class PeopleViewModel {
    enum Phase: Equatable {
        /// First load with nothing to show yet.
        case loading
        /// Lists loaded.
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// People asking to follow me. Every assignment (load, optimistic
    /// accept/decline, revert) syncs the shared header badge — slice 69.
    private(set) var requests: [FollowRequestRow] = [] {
        didSet { FollowBadgeStore.shared.setCount(requests.count) }
    }
    /// People I follow (accepted).
    private(set) var following: [FollowUser] = []
    /// People who follow me (accepted).
    private(set) var followers: [FollowUser] = []

    // Search
    private(set) var searchResults: [UserSearchResult] = []
    private(set) var isSearching = false
    /// True once a search has completed for the current query — gates
    /// the "no one found" empty state so it never flashes early.
    private(set) var hasSearched = false

    /// Action failure surfaced as an alert; the optimistic change is
    /// already reverted when this is set.
    var actionError: String?

    private var loadedOnce = false
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if !loadedOnce { phase = .loading }
        do {
            let response = try await api.getFollows(token: token)
            requests = response.requests
            following = response.following
            followers = response.followers
            loadedOnce = true
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if !loadedOnce { phase = .failed(error.message) }
        } catch {
            if !loadedOnce {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }

    // MARK: - Search

    func search(_ query: String, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await api.searchUsers(q: query, token: token)
            guard !Task.isCancelled else { return }
            searchResults = results
            hasSearched = true
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            hasSearched = true
        }
    }

    func clearSearch() {
        searchResults = []
        hasSearched = false
    }

    // MARK: - Actions (optimistic, revert on failure)

    /// Approves a follow request — the requester moves to Followers.
    func accept(_ row: FollowRequestRow, session: SessionStore) async {
        let priorRequests = requests
        let priorFollowers = followers
        requests.removeAll { $0.user.id == row.user.id }
        followers.insert(row.user, at: 0)

        await post("accept", userId: row.user.id, session: session) {
            self.requests = priorRequests
            self.followers = priorFollowers
        }
    }

    /// Declines a follow request.
    func decline(_ row: FollowRequestRow, session: SessionStore) async {
        let priorRequests = requests
        requests.removeAll { $0.user.id == row.user.id }

        await post("decline", userId: row.user.id, session: session) {
            self.requests = priorRequests
        }
    }

    /// Unfollows someone I follow.
    func unfollow(_ user: FollowUser, session: SessionStore) async {
        let priorFollowing = following
        following.removeAll { $0.id == user.id }

        await post("unfollow", userId: user.id, session: session) {
            self.following = priorFollowing
        }
    }

    /// Removes one of my followers (server-side this is a decline on
    /// an accepted follow).
    func removeFollower(_ user: FollowUser, session: SessionStore) async {
        let priorFollowers = followers
        followers.removeAll { $0.id == user.id }

        await post("decline", userId: user.id, session: session) {
            self.followers = priorFollowers
        }
    }

    private func post(
        _ action: String,
        userId: String,
        session: SessionStore,
        revert: @escaping () -> Void
    ) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        do {
            try await api.followAction(action, userId: userId, token: token)
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            revert()
            actionError = error.message
        } catch {
            revert()
            actionError = "Can't reach Sticks. Check your connection and try again."
        }
    }
}
