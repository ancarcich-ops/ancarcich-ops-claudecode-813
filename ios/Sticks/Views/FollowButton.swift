//
//  FollowButton.swift
//  Sticks
//
//  Slice 68: the reusable follow control — driven by a followState
//  ("none" / "pending" / "accepted") and updated OPTIMISTICALLY:
//  Follow → pending (or straight to accepted when the target
//  auto-accepts), Requested/Following → none via unfollow. On a server
//  error the prior state is restored.
//

import SwiftUI
import UIKit

struct FollowButton: View {
    let targetUserId: String
    /// Server-known state: "none" | "pending" | "accepted".
    let initialState: String
    let session: SessionStore
    /// Fired after an optimistic change is applied (with the new state)
    /// so list rows can keep their own copies in sync.
    var onStateChange: ((String) -> Void)? = nil

    @State private var state: String = "none"
    @State private var isSeeded = false
    @State private var isWorking = false

    var body: some View {
        Button(action: tap) {
            Text(label)
                .font(SticksFont.mono(10))
                .kerning(1.1)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(state == "none" ? Color.sticksGreen : Color.sticksBg)
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .stroke(state == "none" ? Color.clear : Color.sticksHairline, lineWidth: 1)
                )
                .contentShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isWorking)
        .opacity(isWorking ? 0.6 : 1)
        .onAppear {
            if !isSeeded {
                state = initialState
                isSeeded = true
            }
        }
        // A refresh replacing the row with server truth wins over any
        // stale optimistic state.
        .onChange(of: initialState) { _, newValue in
            state = newValue
        }
        .accessibilityLabel(accessibilityText)
    }

    private var label: String {
        switch state {
        case "pending": return "REQUESTED"
        case "accepted": return "FOLLOWING"
        default: return "FOLLOW"
        }
    }

    private var labelColor: Color {
        switch state {
        case "pending": return .sticksMuted
        case "accepted": return .sticksGreen
        default: return .sticksCream
        }
    }

    private var accessibilityText: String {
        switch state {
        case "pending": return "Follow requested. Tap to cancel."
        case "accepted": return "Following. Tap to unfollow."
        default: return "Follow"
        }
    }

    /// none → request (optimistically pending, or accepted when the
    /// server auto-accepts); pending/accepted → unfollow (→ none).
    private func tap() {
        guard !isWorking, let token = session.token else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let prior = state
        let action = prior == "none" ? "request" : "unfollow"
        state = prior == "none" ? "pending" : "none"
        onStateChange?(state)
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                let response = try await APIClient.shared.followAction(
                    action,
                    userId: targetUserId,
                    token: token
                )
                if action == "request", response.state == "accepted" {
                    state = "accepted"
                    onStateChange?(state)
                }
            } catch let error as APIError where error.isUnauthorized {
                session.signOut()
            } catch {
                state = prior
                onStateChange?(prior)
            }
        }
    }
}
