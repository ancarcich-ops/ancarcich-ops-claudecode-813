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
    func matches(token: String) async throws -> MatchesResponse {
        let request = makeRequest(path: "matches", method: "GET", token: token)
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

    /// POST /matches/:id/tee — crowdfix the tee position from live GPS.
    func postTee(matchId: String, hole: Int, lat: Double, lng: Double, accuracyYd: Int, token: String) async throws -> TeeResponse {
        var request = makeRequest(path: "matches/\(matchId)/tee", method: "POST", token: token)
        request.httpBody = try encoder.encode(TeeRequest(hole: hole, lat: lat, lng: lng, accuracyYd: accuracyYd))
        return try await perform(request)
    }

    // MARK: - Plumbing

    private func makeRequest(path: String, method: String, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
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
