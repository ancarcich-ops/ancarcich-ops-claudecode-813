//
//  APIClient.swift
//  Sticks
//
//  Thin client for the Sticks mobile API.
//  Base URL: https://sticks-golf.vercel.app/api/mobile
//  Errors come back as { "error": string } with 400/401/403/404.
//

import Foundation

/// API error carrying the server-provided message and HTTP status.
nonisolated struct APIError: Error, LocalizedError, Equatable {
    let message: String
    let statusCode: Int

    var errorDescription: String? { message }
    var isUnauthorized: Bool { statusCode == 401 }
}

nonisolated struct LoginRequest: Codable {
    let identifier: String
    let password: String
}

nonisolated struct LoginResponse: Codable {
    let token: String
    let user: User
}

nonisolated struct MeResponse: Codable {
    let user: User
}

nonisolated private struct ServerErrorBody: Codable {
    let error: String
}

/// Body for POST /matches/:id/score. `strokes: null` clears the hole, so
/// nil MUST encode as an explicit JSON null (synthesized Codable would
/// drop the key entirely).
nonisolated struct ScoreRequest: Encodable {
    let matchPlayerId: String
    let hole: Int
    let strokes: Int?

    private enum CodingKeys: String, CodingKey {
        case matchPlayerId, hole, strokes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matchPlayerId, forKey: .matchPlayerId)
        try container.encode(hole, forKey: .hole)
        try container.encode(strokes, forKey: .strokes)
    }
}

nonisolated struct OkResponse: Decodable {
    let ok: Bool
}

/// Body for POST /me/target-index. `targetIndex: null` clears the goal,
/// so nil MUST encode as an explicit JSON null.
nonisolated struct TargetIndexRequest: Encodable {
    let targetIndex: Double?

    private enum CodingKeys: String, CodingKey {
        case targetIndex
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetIndex, forKey: .targetIndex)
    }
}

nonisolated struct TargetIndexResponse: Decodable {
    let ok: Bool
    let targetIndex: Double?
}

/// Body for POST /me/profile — only sent keys change server-side, so
/// nil fields must be OMITTED entirely (an empty string clears a field).
nonisolated struct UpdateProfileRequest: Encodable {
    let displayName: String?
    let ghinNumber: String?

    private enum CodingKeys: String, CodingKey {
        case displayName, ghinNumber
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let displayName {
            try container.encode(displayName, forKey: .displayName)
        }
        if let ghinNumber {
            try container.encode(ghinNumber, forKey: .ghinNumber)
        }
    }
}

/// Response for POST/DELETE /me/avatar — the new avatar URL (nil after
/// a delete).
nonisolated struct AvatarResponse: Decodable {
    let avatarUrl: String?
}

/// Body for POST /matches/:id/pars — one par per hole, 3–6 each.
nonisolated struct ParsRequest: Encodable {
    let pars: [Int]
}

nonisolated struct ParsResponse: Decodable {
    let ok: Bool
    let pars: [Int]
}

/// Body for POST /matches/:id/side-games — the FULL desired set of
/// side-game kinds (the server reconciles adds and removes).
nonisolated struct SideGamesRequest: Encodable {
    let kinds: [String]
}

nonisolated struct SideGamesResponse: Decodable {
    let ok: Bool
    let kinds: [String]
}

nonisolated struct SharesResponse: Decodable {
    let shares: [RoundShare]
}

nonisolated struct ShareResponse: Decodable {
    let share: RoundShare
}

/// Body for POST /matches/:id/shares. A nil destAddress is omitted
/// entirely (synthesized Encodable drops nil keys — intended here).
nonisolated struct CreateShareRequest: Encodable {
    let includeScores: Bool
    let destAddress: String?
    let bufferMin: Int
}

/// Body for POST /groups.
nonisolated struct CreateGroupRequest: Encodable {
    let name: String
}

/// Body for POST /groups/join.
nonisolated struct JoinGroupRequest: Encodable {
    let code: String
}

/// Body for POST /matches/:id/tee (FIX TEE crowdfix).
nonisolated struct TeeRequest: Encodable {
    let hole: Int
    let lat: Double
    let lng: Double
    let accuracyYd: Int
}

/// Response for POST /matches/:id/tee. The server returns 200 with
/// `ok: false` + a human-readable `reason` when it rejects the fix
/// (accuracy worse than ±35y or a position inconsistent with the
/// scorecard distance). `reason` is shown to the user verbatim.
nonisolated struct TeeResponse: Decodable {
    let ok: Bool
    let reason: String?
}

nonisolated struct APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://sticks-golf.vercel.app/api/mobile")!
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = APIClient.parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date format: \(raw)"
                )
            }
            return date
        }
    }

    /// Parses ISO-8601 timestamps with or without fractional seconds.
    private static func parseISO8601(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    // MARK: - Endpoints

    /// POST /auth/login
    func login(identifier: String, password: String) async throws -> LoginResponse {
        var request = makeRequest(path: "auth/login", method: "POST")
        request.httpBody = try encoder.encode(LoginRequest(identifier: identifier, password: password))
        return try await perform(request)
    }

    /// GET /me — validates the stored token on launch.
    func me(token: String) async throws -> MeResponse {
        let request = makeRequest(path: "me", method: "GET", token: token)
        return try await perform(request)
    }

    /// GET /matches — the caller's matches, most recent first (max 50).
    /// `group` scopes the feed server-side (cross-group visibility):
    /// nil/absent → the default feed (public + your groups + rounds
    /// involving your groups' members), "public" → ungrouped rounds
    /// only, a group id → rounds posted to that group OR involving any
    /// of its members. The client can't replicate this filter locally.
    func matches(group: String? = nil, token: String) async throws -> MatchesResponse {
        let items = group.map { [URLQueryItem(name: "group", value: $0)] } ?? []
        let request = makeRequest(path: "matches", method: "GET", queryItems: items, token: token)
        return try await perform(request)
    }

    /// GET /matches/:id — full match detail with scorecard, geo, hazards.
    func matchDetail(id: String, token: String) async throws -> MatchDetailResponse {
        let request = makeRequest(path: "matches/\(id)", method: "GET", token: token)
        return try await perform(request)
    }

    /// POST /matches/:id/score — saves (or clears, with nil) a hole score.
    func postScore(matchId: String, matchPlayerId: String, hole: Int, strokes: Int?, token: String) async throws {
        var request = makeRequest(path: "matches/\(matchId)/score", method: "POST", token: token)
        request.httpBody = try encoder.encode(
            ScoreRequest(matchPlayerId: matchPlayerId, hole: hole, strokes: strokes)
        )
        let _: OkResponse = try await perform(request)
    }

    /// POST /matches/:id/complete — marks the round finished. No body;
    /// idempotent, so re-posting on an already-completed match is safe.
    func postComplete(matchId: String, token: String) async throws {
        let request = makeRequest(path: "matches/\(matchId)/complete", method: "POST", token: token)
        let _: OkResponse = try await perform(request)
    }

    /// POST /matches/:id/reopen — reverts a COMPLETED round so scoring
    /// can resume (IN_PROGRESS, or UPCOMING if no scores). Creator-only;
    /// a 403 carries a server message shown verbatim.
    func postReopen(matchId: String, token: String) async throws {
        let request = makeRequest(path: "matches/\(matchId)/reopen", method: "POST", token: token)
        let _: OkResponse = try await perform(request)
    }

    /// POST /matches/:id/pars — creator-only par overrides (3–6 per
    /// hole, any status). 400/403 carry server messages shown verbatim.
    func setPars(matchId: String, pars: [Int], token: String) async throws -> [Int] {
        var request = makeRequest(path: "matches/\(matchId)/pars", method: "POST", token: token)
        request.httpBody = try encoder.encode(ParsRequest(pars: pars))
        let response: ParsResponse = try await perform(request)
        return response.pars
    }

    /// POST /matches/:id/side-games — replaces the match's side games
    /// with the full desired set of kinds. Creator-only; 400/403 carry
    /// server messages shown verbatim.
    func setSideGames(matchId: String, kinds: [String], token: String) async throws -> [String] {
        var request = makeRequest(path: "matches/\(matchId)/side-games", method: "POST", token: token)
        request.httpBody = try encoder.encode(SideGamesRequest(kinds: kinds))
        let response: SideGamesResponse = try await perform(request)
        return response.kinds
    }

    /// GET /matches/:id/shares — the caller's live share links for a round.
    func listShares(matchId: String, token: String) async throws -> [RoundShare] {
        let request = makeRequest(path: "matches/\(matchId)/shares", method: "GET", token: token)
        let response: SharesResponse = try await perform(request)
        return response.shares
    }

    /// POST /matches/:id/shares — creates a live share link.
    func createShare(
        matchId: String,
        includeScores: Bool,
        destAddress: String?,
        bufferMin: Int,
        token: String
    ) async throws -> RoundShare {
        var request = makeRequest(path: "matches/\(matchId)/shares", method: "POST", token: token)
        request.httpBody = try encoder.encode(
            CreateShareRequest(includeScores: includeScores, destAddress: destAddress, bufferMin: bufferMin)
        )
        let response: ShareResponse = try await perform(request)
        return response.share
    }

    /// DELETE /shares/:id — stops (revokes) a live share link.
    func deleteShare(shareId: String, token: String) async throws {
        let request = makeRequest(path: "shares/\(shareId)", method: "DELETE", token: token)
        let _: OkResponse = try await perform(request)
    }

    /// POST /matches/:id/tee — crowdfix the tee position from live GPS.
    func postTee(matchId: String, hole: Int, lat: Double, lng: Double, accuracyYd: Int, token: String) async throws -> TeeResponse {
        var request = makeRequest(path: "matches/\(matchId)/tee", method: "POST", token: token)
        request.httpBody = try encoder.encode(TeeRequest(hole: hole, lat: lat, lng: lng, accuracyYd: accuracyYd))
        return try await perform(request)
    }

    /// GET /groups — the caller's groups.
    func groups(token: String) async throws -> GroupsResponse {
        let request = makeRequest(path: "groups", method: "GET", token: token)
        return try await perform(request)
    }

    /// POST /groups — creates a group and returns it (with invite code).
    func createGroup(name: String, token: String) async throws -> GroupResponse {
        var request = makeRequest(path: "groups", method: "POST", token: token)
        request.httpBody = try encoder.encode(CreateGroupRequest(name: name))
        return try await perform(request)
    }

    /// POST /groups/join — joins via invite code. A 404 carries the
    /// server's error message, shown to the user verbatim.
    func joinGroup(code: String, token: String) async throws -> GroupResponse {
        var request = makeRequest(path: "groups/join", method: "POST", token: token)
        request.httpBody = try encoder.encode(JoinGroupRequest(code: code))
        return try await perform(request)
    }

    /// GET /stats — the caller's personal stats + handicap baselines.
    /// 404 means nothing is logged yet (shown as an empty state).
    func stats(token: String) async throws -> StatsResponse {
        let request = makeRequest(path: "stats", method: "GET", token: token)
        return try await perform(request)
    }

    /// GET /me/profile — the caller's editable profile.
    func profile(token: String) async throws -> ProfileResponse {
        let request = makeRequest(path: "me/profile", method: "GET", token: token)
        return try await perform(request)
    }

    /// POST /me/profile — updates only the keys provided (nil = untouched,
    /// empty string = cleared). 400s carry server messages shown verbatim.
    func updateProfile(displayName: String? = nil, ghinNumber: String? = nil, token: String) async throws -> ProfileResponse {
        var request = makeRequest(path: "me/profile", method: "POST", token: token)
        request.httpBody = try encoder.encode(
            UpdateProfileRequest(displayName: displayName, ghinNumber: ghinNumber)
        )
        return try await perform(request)
    }

    /// POST /me/avatar — uploads raw JPEG bytes (max 4 MB, downscaled
    /// client-side). 400/503 carry server messages shown verbatim.
    func uploadAvatar(jpegData: Data, token: String) async throws -> AvatarResponse {
        var request = makeRequest(path: "me/avatar", method: "POST", token: token)
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpegData
        request.timeoutInterval = 60
        return try await perform(request)
    }

    /// DELETE /me/avatar — removes the photo; the profile falls back to
    /// the initials bubble.
    func deleteAvatar(token: String) async throws {
        let request = makeRequest(path: "me/avatar", method: "DELETE", token: token)
        let _: AvatarResponse = try await perform(request)
    }

    /// POST /me/target-index — sets (or clears, with nil) the player's
    /// index goal.
    func setTargetIndex(_ targetIndex: Double?, token: String) async throws -> TargetIndexResponse {
        var request = makeRequest(path: "me/target-index", method: "POST", token: token)
        request.httpBody = try encoder.encode(TargetIndexRequest(targetIndex: targetIndex))
        return try await perform(request)
    }

    /// DELETE /matches/:id — removes a round. 403 (non-creator) carries
    /// a server message shown verbatim.
    func deleteMatch(id: String, token: String) async throws {
        let request = makeRequest(path: "matches/\(id)", method: "DELETE", token: token)
        let _: OkResponse = try await perform(request)
    }

    /// DELETE /matches/:id/my-scores — removes only the caller's scores
    /// from a round; other players keep theirs. 403 (not a player)
    /// carries a server message shown verbatim.
    func removeMyScores(matchId: String, token: String) async throws {
        let request = makeRequest(path: "matches/\(matchId)/my-scores", method: "DELETE", token: token)
        let _: OkResponse = try await perform(request)
    }

    /// GET /groups/:id/leaderboard — group standings, champions, course
    /// records and streaks. 403 (not a member) and 404 (unknown group)
    /// carry server messages shown verbatim.
    func groupLeaderboard(groupId: String, token: String) async throws -> GroupLeaderboardResponse {
        let request = makeRequest(path: "groups/\(groupId)/leaderboard", method: "GET", token: token)
        return try await perform(request)
    }

    /// GET /courses?q= — course search by name.
    func searchCourses(query: String, token: String) async throws -> CoursesResponse {
        let request = makeRequest(
            path: "courses",
            method: "GET",
            queryItems: [URLQueryItem(name: "q", value: query)],
            token: token
        )
        return try await perform(request)
    }

    /// GET /courses?lat=&lng= — nearest courses first, with distanceMi.
    func nearbyCourses(lat: Double, lng: Double, token: String) async throws -> CoursesResponse {
        let request = makeRequest(
            path: "courses",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "lat", value: String(lat)),
                URLQueryItem(name: "lng", value: String(lng)),
            ],
            token: token
        )
        return try await perform(request)
    }

    /// GET /courses/tees?name= — the rated tee sets for a course plus
    /// its default tee name. An empty tees array means the course has no
    /// rating yet — the create flow hides the picker entirely.
    func courseTees(name: String, token: String) async throws -> CourseTeesResponse {
        let request = makeRequest(
            path: "courses/tees",
            method: "GET",
            queryItems: [URLQueryItem(name: "name", value: name)],
            token: token
        )
        return try await perform(request)
    }

    /// GET /players/suggest — recent partners (nil query, carries
    /// lastHandicap + myLastHandicap) or a name search (?q=).
    func suggestPlayers(query: String?, token: String) async throws -> PlayerSuggestResponse {
        let items = query.map { [URLQueryItem(name: "q", value: $0)] } ?? []
        let request = makeRequest(path: "players/suggest", method: "GET", queryItems: items, token: token)
        return try await perform(request)
    }

    /// POST /matches — creates a round. 400/403 carry server messages
    /// shown verbatim.
    func createMatch(_ body: CreateMatchRequest, token: String) async throws -> CreateMatchResponse {
        var request = makeRequest(path: "matches", method: "POST", token: token)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    /// PATCH /matches/:id — creator-only edit of an UPCOMING round with
    /// no scores logged; same body shape as POST /matches. 400 (edit
    /// window closed) and 403 carry server messages shown verbatim.
    func updateMatch(id: String, _ body: CreateMatchRequest, token: String) async throws -> CreateMatchResponse {
        var request = makeRequest(path: "matches/\(id)", method: "PATCH", token: token)
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    // MARK: - Plumbing

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        token: String? = nil
    ) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !queryItems.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = queryItems
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError(message: "Can't reach Sticks. Check your connection and try again.", statusCode: -1)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Unexpected response from the server.", statusCode: -1)
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerErrorBody.self, from: data))?.error
                ?? "Something went wrong (\(http.statusCode))."
            throw APIError(message: message, statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[API] Decoding failed for \(request.url?.path ?? "?"): \(error)")
            throw APIError(message: "Couldn't read the server response.", statusCode: http.statusCode)
        }
    }
}
