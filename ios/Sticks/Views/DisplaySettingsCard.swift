//
//  DisplaySettingsCard.swift
//  Sticks
//
//  Slice 96: the Settings tab's DISPLAY section — "Show reactions".
//  An ACCOUNT setting (GET/POST /me/display-prefs), not a device
//  local: turning it off here also quiets the website for the same
//  login. Copy matches the website's toggle caption verbatim.
//
//  Deliberately separate from the NOTIFICATIONS card below it — that
//  one's reactions toggle decides whether the phone buzzes; this one
//  decides what's on screen.
//

import SwiftUI

struct DisplaySettingsCard: View {
    let session: SessionStore

    private var prefs = DisplayPrefsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DISPLAY")
                .font(SticksFont.mono(10))
                .kerning(1.2)
                .foregroundStyle(Color.sticksFaint)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("SHOW REACTIONS")
                            .font(SticksFont.mono(12))
                            .kerning(1.2)
                            .foregroundStyle(Color.sticksInk)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { prefs.showReactions },
                            set: { newValue in
                                Task { await prefs.setShowReactions(newValue, session: session) }
                            }
                        ))
                        .labelsHidden()
                        .tint(Color.sticksGreen)
                    }

                    Text("Reaction rows on round pages and feed cards. Turning this off hides them everywhere — it does not stop anyone reacting to your rounds, and it does not change your notifications.")
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
        .task {
            // The account's value may have changed on the website since
            // this device last synced. The store throttles repeats.
            await prefs.refresh(session: session)
        }
    }
}
