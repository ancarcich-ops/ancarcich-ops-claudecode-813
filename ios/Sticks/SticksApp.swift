//
//  SticksApp.swift
//  Sticks
//

import SwiftUI

@main
struct SticksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .preferredColorScheme(.light)
        }
        // Auto-open the watch companion whenever this app comes forward.
        // Warm foregrounds hit the launch directly; on cold launch the
        // session isn't activated yet, so activate() kicks it off and the
        // activation callback fires the launch instead.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WatchSessionService.shared.activate()
            WatchAppLaunchService.shared.launchCompanionAppIfPossible()
        }
    }
}
