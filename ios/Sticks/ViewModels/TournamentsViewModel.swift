//
//  TournamentsViewModel.swift
//  Sticks
//
//  Slice 55: state for the tournaments list — GET /tournaments plus
//  the create (POST /tournaments) and join-by-code (POST
//  /tournaments/join) flows. Server errors surface verbatim.
//

import Foundation
import Observation

@Observable
final class TournamentsViewModel {
    enum Phase: Equatable {
        /// First load with nothing cached yet.
        case loading
        /// Tournaments loaded (possibly empty).
        case loaded
        /// First load failed with a user-facing message.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var tournaments: [TournamentSummary] = []

    private(set) var isCreating = false
    private(set) var createError: String?
    private(set) var isJoining = false
    private(set) var joinError: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fetches the caller's tournaments. A 401 signs the user out;
    /// other failures only go full-screen when there's nothing to show.
    func load(session: SessionStore) async {
        guard let token = session.token else {
            session.signOut()
            return
        }
        if tournaments.isEmpty, phase != .loaded { phase = .loading }
        do {
            let response = try await api.tournaments(token: token)
            tournaments = response.tournaments
            phase = .loaded
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
        } catch let error as APIError {
            if tournaments.isEmpty { phase = .failed(error.message) }
        } catch {
            if tournaments.isEmpty {
                phase = .failed("Can't reach Sticks. Check your connection and try again.")
            }
        }
    }

    /// POST /tournaments. Returns the new tournament's id on success;
    /// on failure `createError` carries the server's message.
    func create(
        name: String,
        scoringMode: String,
        roundsPlanned: Int,
        scheduledStartAt: Date?,
        notes: String?,
        session: SessionStore
    ) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }
        let body = CreateTournamentRequest(
            name: name,
            scoringMode: scoringMode,
            roundsPlanned: roundsPlanned,
            scheduledStartAt: scheduledStartAt.map { ISO8601DateFormatter().string(from: $0) },
            notes: notes?.isEmpty == false ? notes : nil
        )
        do {
            let response = try await api.createTournament(body, token: token)
            await load(session: session)
            return response.tournament.id
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            createError = error.message
            return nil
        } catch {
            createError = "Can't reach Sticks. Check your connection and try again."
            return nil
        }
    }

    func clearCreateError() {
        createError = nil
    }

    /// POST /tournaments/join. Returns the tournament's id on success;
    /// a 404 (bad code) message lands in `joinError` verbatim.
    func join(code: String, handicap: Double?, session: SessionStore) async -> String? {
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let response = try await api.joinTournament(code: code, handicap: handicap, token: token)
            await load(session: session)
            return response.tournament.id
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            joinError = error.message
            return nil
        } catch {
            joinError = "Can't reach Sticks. Check your connection and try again."
            return nil
        }
    }

    func clearJoinError() {
        joinError = nil
    }
}
