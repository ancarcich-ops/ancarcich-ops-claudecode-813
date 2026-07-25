//
//  AppDelegate.swift
//  Sticks
//
//  Live Activity lifecycle backstops that SwiftUI's scene phases can't
//  cover:
//  - LAUNCH: any activity alive at cold launch is a straggler from a
//    force-quit or system kill (no round session can exist yet) — sweep
//    them so the lock screen never shows a dead round.
//  - TERMINATION: while a round is active the app keeps running in the
//    background for location, so swiping it away DOES call
//    `applicationWillTerminate`. Use the short window iOS grants to end
//    the round session and dismiss the Live Activity before the process
//    dies.
//  - Slice 71: remote push — APNs token registration callbacks plus
//    the UNUserNotificationCenter delegate (foreground banners and tap
//    routing). The delegate is set HERE, at launch, so a cold-start
//    notification tap is never missed.
//

import ActivityKit
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        RoundActivityService.shared.sweepStragglersAtLaunch()
        return true
    }

    // MARK: - APNs registration (slice 71)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationService.shared.handleDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationService.shared.handleRegistrationError(error)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Tear the round down first — disables background location so the
        // system indicator clears — then block briefly on the activity end.
        RoundSessionService.shared.endRound()
        RoundSessionService.shared.location.stop()
        RoundActivityService.shared.endAllBeforeTermination()
    }
}

// MARK: - Notification delegate (slice 71)

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Foreground arrivals still show a banner — and the affected
    /// screens get a refresh nudge so the banner and UI agree.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        await MainActor.run {
            PushNotificationService.shared.handleForegroundPayload(payload)
        }
        return [.banner, .list, .sound]
    }

    /// A tap (foreground, background, or cold launch) — park the deep
    /// link; MainTabView consumes it once the signed-in root is up.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            PushNotificationService.shared.handleTap(payload)
        }
    }
}
