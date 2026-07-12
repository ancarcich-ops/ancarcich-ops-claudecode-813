//
//  ContentView.swift
//  Sticks
//
//  Root router: validates the stored token on launch, then shows
//  login or the signed-in experience. On cold launch the branded
//  splash overlays everything for ≥2.5s or until the token check
//  resolves (whichever is longer), then fades out over 240ms.
//

import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var session

    @State private var splashHoldElapsed = false
    @State private var splashVisible = true

    var body: some View {
        ZStack {
            Group {
                switch session.phase {
                case .checking:
                    checkingView
                case .signedOut:
                    LoginView(session: session)
                        .transition(.opacity)
                case .signedIn(let user):
                    MainTabView(user: user, session: session)
                        .transition(.opacity)
                case .unreachable(let message):
                    unreachableView(message)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: session.phase)

            if splashVisible {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            await session.bootstrap()
        }
        .task {
            // Minimum splash hold — the fade waits for BOTH this and the
            // token check, whichever finishes last.
            try? await Task.sleep(for: .seconds(2.5))
            splashHoldElapsed = true
            dismissSplashIfReady()
        }
        .onChange(of: session.phase) { _, _ in
            dismissSplashIfReady()
        }
        // Slice 51: one-time post-login offer to enable Face ID sign-in.
        .alert(
            "Use \(BiometricService.displayName) next time?",
            isPresented: Binding(
                get: { session.offersBiometricEnrollment },
                set: { if !$0 { session.declineBiometricEnrollment() } }
            )
        ) {
            Button("Enable") { session.acceptBiometricEnrollment() }
            Button("Not now", role: .cancel) { session.declineBiometricEnrollment() }
        } message: {
            Text("Skip the password — sign in to Sticks with \(BiometricService.displayName). You can turn this off any time in Settings.")
        }
    }

    private func dismissSplashIfReady() {
        guard splashVisible, splashHoldElapsed, session.phase != .checking else { return }
        withAnimation(.easeOut(duration: 0.24)) {
            splashVisible = false
        }
    }

    /// Post-splash re-check state (e.g. Try Again from unreachable).
    private var checkingView: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()
            ProgressView()
                .tint(Color.sticksGreen)
        }
    }

    private func unreachableView(_ message: String) -> some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.sticksMuted)

                Text(message)
                    .font(SticksFont.sans(16))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await session.bootstrap() }
                } label: {
                    Text("Try Again")
                        .font(SticksFont.sans(16, weight: .semibold))
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
                        .font(SticksFont.sans(14, weight: .medium))
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
