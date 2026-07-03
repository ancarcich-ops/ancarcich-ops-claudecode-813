//
//  KeychainService.swift
//  Sticks
//
//  Minimal Keychain wrapper for the long-lived Sticks API token.
//

import Foundation
import Security

nonisolated enum KeychainService {
    private static let service = "app.rork.sticks"
    private static let account = "api-token"

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
}
