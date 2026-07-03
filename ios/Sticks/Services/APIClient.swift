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
