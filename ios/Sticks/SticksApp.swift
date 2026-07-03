//
//  SticksApp.swift
//  Sticks
//

import SwiftUI

@main
struct SticksApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .preferredColorScheme(.light)
        }
    }
}
