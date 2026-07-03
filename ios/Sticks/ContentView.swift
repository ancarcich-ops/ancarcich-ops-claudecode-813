//
//  ContentView.swift
//  Sticks
//
//  Root router: validates the stored token on launch, then shows
//  login or the signed-in experience.
//

import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .checking:
                launchView
            case .signedOut:
                LoginView(session: session)
                    .transition(.opacity)
            case .signedIn(let user):
                MatchListView(user: user, session: session)
                    .transition(.opacity)
            case .unreachable(let message):
                unreachableView(message)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .task {
            await session.bootstrap()
        }
    }

    private var launchView: some View {
        ZStack {
            Color.sticksCream.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Sticks")
                    .font(SticksFont.display(48))
                    .foregroundStyle(Color.sticksInk)
                ProgressView()
                    .tint(Color.sticksGreen)
            }
        }
    }

    private func unreachableView(_ message: String) -> some View {
        ZStack {
            Color.sticksCream.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.sticksMuted)

                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await session.bootstrap() }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.sticksCream)
                        .padding(.horizontal, 32)
                        .frame(height: 48)
                        .background(Color.sticksGreen)
                        .clipShape(.rect(cornerRadius: 12))
                }

                Button {
                    session.signOut()
                } label: {
                    Text("Sign in with a different account")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
}
