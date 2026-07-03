//
//  SessionStore.swift
//  Sticks
//
//  Owns the auth lifecycle: token storage, launch validation via /me,
//  sign in, and sign out. A 401 anywhere means signed out.
//

import Foundation
import Observation

@Observable
final class SessionStore {
    enum Phase: Equatable {
        /// Validating a stored token on launch.
        case checking
        /// No valid token — show login.
        case signedOut
        /// Token validated; user is signed in.
        case signedIn(User)
        /// Have a token but couldn't reach the server (offline, etc.).
        case unreachable(String)
    }

    private(set) var phase: Phase = .checking

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var token: String? { KeychainService.loadToken() }

    /// Called on launch: validate any stored token with GET /me.
    func bootstrap() async {
        guard let token = KeychainService.loadToken() else {
            phase = .signedOut
            return
        }
        phase = .checking
        do {
            let response = try await api.me(token: token)
            phase = .signedIn(response.user)
        } catch let error as APIError where error.isUnauthorized {
            KeychainService.deleteToken()
            phase = .signedOut
        } catch let error as APIError {
            phase = .unreachable(error.message)
        } catch {
            phase = .unreachable("Can't reach Sticks. Check your connection and try again.")
        }
    }

    /// Signs in and stores the long-lived token in the Keychain.
    /// Throws `APIError` with a user-facing message on failure.
    func signIn(identifier: String, password: String) async throws {
        let response = try await api.login(identifier: identifier, password: password)
        KeychainService.saveToken(response.token)
        phase = .signedIn(response.user)
    }

    /// Clears the token and returns to login. Also the handler for any 401.
    func signOut() {
        KeychainService.deleteToken()
        phase = .signedOut
    }
}
