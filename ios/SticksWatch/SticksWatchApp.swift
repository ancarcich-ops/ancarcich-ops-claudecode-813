import SwiftUI
import WatchKit

@main
struct SticksWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    private let phoneSession = PhoneSessionService.shared
    private let workoutKeepAlive = WorkoutKeepAliveService.shared

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
                // A live round on the phone runs a golf workout session on
                // the watch, which keeps Sticks frontmost — wrist-raise
                // returns here instead of the clock face, all round long.
                .onChange(of: phoneSession.snapshot != nil, initial: true) { _, hasRound in
                    if hasRound {
                        workoutKeepAlive.start()
                    } else {
                        workoutKeepAlive.end()
                    }
                }
        }
    }
}
