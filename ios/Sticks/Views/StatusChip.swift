//
//  StatusChip.swift
//  Sticks
//
//  Match status pill — LIVE (filled green), UPCOMING (outlined),
//  FINAL (muted). Shared by the match list and match detail screens.
//

import SwiftUI

struct StatusChip: View {
    let status: MatchStatus

    var body: some View {
        Text(label)
            .font(SticksFont.label(10, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background)
            .clipShape(.capsule)
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
    }

    private var label: String {
        switch status {
        case .inProgress: "LIVE"
        case .upcoming: "UPCOMING"
        case .completed: "FINAL"
        }
    }

    private var foreground: Color {
        switch status {
        case .inProgress: .sticksCream
        case .upcoming: .sticksGreen
        case .completed: .sticksMuted
        }
    }

    private var background: Color {
        status == .inProgress ? .sticksGreen : .clear
    }

    private var border: Color {
        switch status {
        case .inProgress: .clear
        case .upcoming: .sticksGreen
        case .completed: .sticksHairline
        }
    }
}
