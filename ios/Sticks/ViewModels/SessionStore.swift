//
//  SessionStore.swift
//  Sticks
//
//  Owns the auth lifecycle: token storage, launch validation via /me,
//  sign in, and sign out. A 401 anywhere means signed out.
//

import Foundation
import LocalAuthentication
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

    /// Slice 51: set after a password sign-in when the device supports
    /// biometrics and Face ID sign-in isn't enabled yet — drives the
    /// one-time "Use Face ID next time?" offer.
    var offersBiometricEnrollment = false

    private static let biometricOfferedKey = "sticks.biometricOffered.v1"

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var token: String? { KeychainService.loadToken() }

    /// The signed-in user, when any.
    var user: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

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
        offerBiometricEnrollmentIfNeeded()
    }

    /// Creates an account and signs in — same token-storage path as
    /// `signIn`, so the new user lands on Home immediately.
    /// Throws `APIError` with the server's message on failure.
    func signUp(username: String, email: String, password: String, displayName: String?) async throws {
        let response = try await api.signup(
            username: username,
            email: email,
            password: password,
            displayName: displayName
        )
        KeychainService.saveToken(response.token)
        phase = .signedIn(response.user)
    }

    /// Clears the token and returns to login. Also the handler for any 401.
    /// Ends any active round session — the Live Activity, watch snapshot,
    /// and background location must never outlive the signed-in user.
    /// The biometric-protected token deliberately SURVIVES sign-out so
    /// Face ID sign-in still works next launch.
    func signOut() {
        RoundSessionService.shared.endRound()
        KeychainService.deleteToken()
        phase = .signedOut
    }

    // MARK: - Face ID / Touch ID sign-in (slice 51)

    /// Whether a biometric-protected token exists on this device.
    var isBiometricSignInEnabled: Bool {
        KeychainService.hasBiometricToken
    }

    /// Biometric prompt → read the protected token → validate via /me →
    /// signed in on the same path as a password login. A rejected token
    /// clears the biometric item so the stale button disappears.
    /// Throws `BiometricService.BiometricError.cancelled` on user cancel
    /// (callers ignore it) or `APIError` with a user-facing message.
    func signInWithBiometrics() async throws {
        let context = try await BiometricService.authenticate(reason: "Sign in to Sticks")

        guard let token = KeychainService.loadBiometricToken(context: context) else {
            KeychainService.deleteBiometricToken()
            throw APIError(
                message: "\(BiometricService.displayName) sign-in needs a fresh password sign-in.",
                statusCode: 0
            )
        }

        do {
            let response = try await api.me(token: token)
            KeychainService.saveToken(token)
            phase = .signedIn(response.user)
        } catch let error as APIError where error.isUnauthorized {
            KeychainService.deleteBiometricToken()
            throw APIError(
                message: "Your saved sign-in expired. Sign in with your password.",
                statusCode: 401
            )
        }
    }

    /// Stores the current session token behind biometrics (Settings toggle
    /// or the post-login offer). Adding never prompts — only reads do.
    @discardableResult
    func enableBiometricSignIn() -> Bool {
        guard let token = KeychainService.loadToken() else { return false }
        return KeychainService.saveBiometricToken(token)
    }

    /// Removes the biometric item (Settings → Face ID sign-in off).
    func disableBiometricSignIn() {
        KeychainService.deleteBiometricToken()
    }

    /// Offer once per install; the Settings toggle covers later changes
    /// of heart, so a decline is never nagged about again.
    private func offerBiometricEnrollmentIfNeeded() {
        guard BiometricService.isAvailable,
              !KeychainService.hasBiometricToken,
              !UserDefaults.standard.bool(forKey: Self.biometricOfferedKey)
        else { return }
        offersBiometricEnrollment = true
    }

    /// Accepts the post-login offer — saves the token behind Face ID.
    func acceptBiometricEnrollment() {
        UserDefaults.standard.set(true, forKey: Self.biometricOfferedKey)
        offersBiometricEnrollment = false
        enableBiometricSignIn()
    }

    /// Declines the post-login offer — never offered again on this install.
    func declineBiometricEnrollment() {
        UserDefaults.standard.set(true, forKey: Self.biometricOfferedKey)
        offersBiometricEnrollment = false
    }
}
