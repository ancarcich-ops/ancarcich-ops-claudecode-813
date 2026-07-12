//
//  KeychainService.swift
//  Sticks
//
//  Minimal Keychain wrapper for the long-lived Sticks API token.
//  Slice 51 adds a second, biometric-protected item (Face ID sign-in)
//  that survives normal sign-out.
//

import Foundation
import LocalAuthentication
import Security

nonisolated enum KeychainService {
    private static let service = "app.rork.sticks"
    private static let account = "api-token"
    private static let biometricAccount = "biometric-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Saves (or replaces) the API token.
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save token, status: \(status)")
        }
        return status == errSecSuccess
    }

    /// Reads the stored API token, if any.
    static func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Removes the stored API token.
    static func deleteToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    // MARK: - Biometric-protected token (slice 51)

    private static var biometricBaseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: biometricAccount,
        ]
    }

    /// Saves the token behind Face ID / Touch ID. Reading it back requires
    /// a successful biometric evaluation; re-enrolling biometrics
    /// invalidates the item (`.biometryCurrentSet`).
    @discardableResult
    static func saveBiometricToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) else { return false }

        deleteBiometricToken()

        var query = biometricBaseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessControl as String] = access

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save biometric token, status: \(status)")
        }
        return status == errSecSuccess
    }

    /// Whether a biometric token item exists — checked WITHOUT triggering
    /// the Face ID prompt (interaction disallowed; "needs auth" counts
    /// as existing).
    static var hasBiometricToken: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query = biometricBaseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Reads the biometric-protected token using an ALREADY-authenticated
    /// `LAContext`, so the user isn't prompted a second time.
    static func loadBiometricToken(context: LAContext) -> String? {
        var query = biometricBaseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    /// Removes the biometric token (Settings toggle off, or a rejected /me).
    static func deleteBiometricToken() {
        SecItemDelete(biometricBaseQuery as CFDictionary)
    }
}
