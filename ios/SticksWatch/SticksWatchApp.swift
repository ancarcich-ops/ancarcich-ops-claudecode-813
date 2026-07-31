import SwiftUI
import WatchKit

@main
struct SticksWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    private let phoneSession = PhoneSessionService.shared
    private let workoutKeepAlive = WorkoutKeepAliveService.shared
    private let workoutConsent = WorkoutConsentStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(phoneSession)
                .task {
                    // Second line of defense: stretches the frontmost
                    // grace period after wrist-down from ~2 to ~8 minutes
                    // even when no workout session is running (e.g. the
                    // wearer declined HealthKit).
                    WKExtension.shared().isFrontmostTimeoutExtended = true
                    phoneSession.activate()
                }
                // A live round can run a golf workout session on the
                // watch, which records to Health and keeps Sticks
                // frontmost — but only with the wearer's say-so, so this
                // asks (or honors their saved choice) rather than
                // starting on its own.
                .onChange(of: phoneSession.snapshot?.courseName, initial: true) { _, courseName in
                    if let courseName {
                        workoutConsent.roundBecameLive(key: courseName)
                    } else {
                        workoutConsent.roundEnded()
                        workoutKeepAlive.end()
                    }
                }
        }
    }
}
