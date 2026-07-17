//
//  GroupMembersViewModel.swift
//  Sticks
//
//  Slice 64: loads GET /groups/:id/members — the group roster.
//  Refreshes keep the previous roster on transient failures; 403
//  (not a member) and 404 surface the server's message verbatim.
//

import Foundation
import Observation

@Observable
final class GroupMembersViewModel {
    enum Phase: Equatable {
        /// First load with nothing to show yet.
        case loading
        /// Roster loaded.
        case loaded
        /// First load failed with a user-facing message (403/404 included).
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var members: [GroupMemberRow] = []
    private var hasLoaded = false

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    func load(groupId: String, session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if !hasLoaded { phase = .loading }
        do {
            let response = try await api.groupMembers(groupId: groupId, token: token)
            members = response.members
            hasLoaded = true
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if !hasLoaded { phase = .failed(error.message) }
        } catch {
            if !hasLoaded {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }
}
