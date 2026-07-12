//
//  BiometricService.swift
//  Sticks
//
//  Slice 51: thin LocalAuthentication wrapper for Face ID / Touch ID
//  sign-in. Availability checks, per-device naming, and a single
//  async prompt that hands back the authenticated LAContext so the
//  Keychain read doesn't prompt twice.
//

import Foundation
import LocalAuthentication

enum BiometricService {
    enum BiometricError: Error {
        /// User cancelled or chose to type the password — never surfaced
        /// as an error, the form is the fallback.
        case cancelled
        case unavailable
        case failed(String)
    }

    /// Whether biometrics can be evaluated right now (hardware present,
    /// enrolled, not locked out).
    static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// "Face ID" or "Touch ID" per device.
    static var displayName: String {
        biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    /// SF Symbol matching the device's biometry.
    static var iconName: String {
        biometryType == .touchID ? "touchid" : "faceid"
    }

    private static var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Runs the biometric prompt and returns the authenticated context on
    /// success, for use with `KeychainService.loadBiometricToken(context:)`.
    static func authenticate(reason: String) async throws -> LAContext {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &availabilityError) else {
            throw BiometricError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            guard success else {
                throw BiometricError.failed("Couldn't verify you. Use your password instead.")
            }
            return context
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel, .userFallback:
                throw BiometricError.cancelled
            default:
                throw BiometricError.failed("Couldn't verify you. Use your password instead.")
            }
        }
    }
}
