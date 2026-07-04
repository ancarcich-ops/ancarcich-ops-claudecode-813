import SwiftUI

@main
struct SticksWatchApp: App {
    @State private var phoneSession = PhoneSessionService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(phoneSession)
                .task { phoneSession.activate() }
        }
    }
}
