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
//

import ActivityKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        RoundActivityService.shared.sweepStragglersAtLaunch()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Tear the round down first — disables background location so the
        // system indicator clears — then block briefly on the activity end.
        RoundSessionService.shared.endRound()
        RoundSessionService.shared.location.stop()
        RoundActivityService.shared.endAllBeforeTermination()
    }
}
