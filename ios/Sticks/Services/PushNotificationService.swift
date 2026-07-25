//
//  PushNotificationService.swift
//  Sticks
//
//  Slice 71: remote push. Owns the APNs lifecycle end-to-end:
//  - permission state + the one-time auto-prompt after the welcome flow
//  - device-token registration and upload to POST /me/push-token
//  - sign-out unregistration (a signed-out device must never buzz)
//  - per-category prefs (local + mirrored to /me/push-prefs)
//  - notification tap routing — taps become PushDeepLinks that
//    MainTabView consumes (cold launches park the link until the
//    signed-in root mounts).
//
//  Payload contract (see docs/push-notifications-backend-handoff.md):
//  { aps: {...}, type: "round_start" | "score_highlight" | "front_nine"
//    | "round_final" | "follow_request" | "follow_accept",
//    matchId?: string, userId?: string }
//

import Foundation
import Observation
import UIKit
import UserNotifications

/// Where a tapped notification should land in the app.
enum PushDeepLink: Equatable {
    case match(id: String)
    case people
}

/// The Sendable slice of a push payload — extracted on the delegate's
/// nonisolated context before hopping to the main actor.
nonisolated struct PushPayload: Sendable {
    let type: String?
    let matchId: String?

    init(userInfo: [AnyHashable: Any]) {
        type = userInfo["type"] as? String
        let id = userInfo["matchId"] as? String
        matchId = (id?.isEmpty == false) ? id : nil
    }
}

extension Notification.Name {
    /// Posted when a notification tap parked a deep link; MainTabView
    /// consumes it (or picks it up in its launch task on cold start).
    static let sticksPushDeepLink = Notification.Name("sticksPushDeepLink")
}

@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()

    enum AuthState: Equatable {
        case unknown
        case notDetermined
        case denied
        case authorized
    }

    private(set) var authState: AuthState = .unknown
    private(set) var prefs: PushPrefs
    /// A tap's destination waiting for the signed-in root to consume it.
    private(set) var pendingDeepLink: PushDeepLink?

    private static let prefsKey = "sticks.pushPrefs.v1"
    private static let promptedKey = "sticks.pushPrompted.v1"
    private static let deviceTokenKey = "sticks.pushDeviceToken.v1"

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        if let data = UserDefaults.standard.data(forKey: Self.prefsKey),
           let saved = try? JSONDecoder().decode(PushPrefs.self, from: data) {
            prefs = saved
        } else {
            prefs = PushPrefs()
        }
    }

    /// "sandbox" for debug builds (Xcode-installed), "production" for
    /// TestFlight/App Store — tells the server which APNs host to use.
    private static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    // MARK: - Permission lifecycle

    func refreshAuthState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            authState = .notDetermined
        case .denied:
            authState = .denied
        case .authorized, .provisional, .ephemeral:
            authState = .authorized
        @unknown default:
            authState = .unknown
        }
    }

    /// Called when the signed-in root appears (post-welcome). Prompts
    /// once per install if undecided; re-registers silently when
    /// already authorized (tokens rotate, so every launch re-uploads).
    /// Also clears any stale app badge.
    func syncOnSignedInLaunch() async {
        await refreshAuthState()
        switch authState {
        case .notDetermined where !UserDefaults.standard.bool(forKey: Self.promptedKey):
            UserDefaults.standard.set(true, forKey: Self.promptedKey)
            await requestAuthorization()
        case .authorized:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
        await loadServerPrefs()
    }

    /// System permission prompt; on grant, kicks off APNs registration.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            granted = false
        }
        await refreshAuthState()
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    // MARK: - Device token

    /// APNs handed us a token — hex-encode, remember it for sign-out
    /// cleanup, and upload it to the server.
    func handleDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: Self.deviceTokenKey)
        Task { await uploadToken(hex) }
    }

    func handleRegistrationError(_ error: Error) {
        print("[Push] APNs registration failed: \(error.localizedDescription)")
    }

    private func uploadToken(_ hex: String) async {
        guard let authToken = KeychainService.loadToken() else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        do {
            try await api.registerPushToken(
                deviceToken: hex,
                environment: Self.apnsEnvironment,
                appVersion: version,
                token: authToken
            )
        } catch {
            // Soft failure (offline, or the endpoint isn't live yet) —
            // re-tried automatically on the next signed-in launch.
            let message = (error as? APIError)?.message ?? error.localizedDescription
            print("[Push] Token upload failed: \(message)")
        }
    }

    /// Fire-and-forget server-side removal at sign-out, using the auth
    /// token captured BEFORE the Keychain clears it.
    func unregisterForSignOut(authToken: String) {
        guard let hex = UserDefaults.standard.string(forKey: Self.deviceTokenKey) else { return }
        let client = api
        Task.detached {
            try? await client.unregisterPushToken(deviceToken: hex, token: authToken)
        }
    }

    // MARK: - Preferences

    /// Flips one category: saved locally right away, mirrored to the
    /// server best-effort (the server gates fanout on its copy).
    func setPref(_ keyPath: WritableKeyPath<PushPrefs, Bool>, to value: Bool) {
        prefs[keyPath: keyPath] = value
        saveLocalPrefs()
        Task { await mirrorPrefsToServer() }
    }

    private func saveLocalPrefs() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.prefsKey)
        }
    }

    private func mirrorPrefsToServer() async {
        guard let authToken = KeychainService.loadToken() else { return }
        do {
            try await api.setPushPrefs(prefs, token: authToken)
        } catch {
            let message = (error as? APIError)?.message ?? error.localizedDescription
            print("[Push] Prefs mirror failed: \(message)")
        }
    }

    /// Adopts the server's prefs when available (another device may
    /// have changed them). A 404 just means the endpoint isn't live
    /// yet — local prefs stand.
    func loadServerPrefs() async {
        guard let authToken = KeychainService.loadToken() else { return }
        guard let serverPrefs = try? await api.pushPrefs(token: authToken) else { return }
        if serverPrefs != prefs {
            prefs = serverPrefs
            saveLocalPrefs()
        }
    }

    // MARK: - Incoming notifications

    /// A push arrived while the app is foreground — nudge the affected
    /// screens to refresh so the banner and the UI agree.
    func handleForegroundPayload(_ payload: PushPayload) {
        if payload.matchId != nil {
            NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
        }
    }

    /// The user tapped a notification: park the destination and signal.
    /// MainTabView consumes immediately when mounted; cold launches
    /// pick the parked link up in its launch task.
    func handleTap(_ payload: PushPayload) {
        guard let link = Self.deepLink(for: payload) else { return }
        pendingDeepLink = link
        NotificationCenter.default.post(name: .sticksPushDeepLink, object: nil)
    }

    func consumePendingDeepLink() -> PushDeepLink? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    private static func deepLink(for payload: PushPayload) -> PushDeepLink? {
        if let matchId = payload.matchId {
            return .match(id: matchId)
        }
        if payload.type == "follow_request" || payload.type == "follow_accept" {
            return .people
        }
        return nil
    }
}
