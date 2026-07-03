//
//  MatchDetailPlaceholderView.swift
//  Sticks
//
//  Slice 2 stub so tapping a match navigates somewhere.
//  Replaced by the full scorecard screen in slice 3.
//

import SwiftUI

struct MatchDetailPlaceholderView: View {
    let match: MatchSummary

    var body: some View {
        ZStack {
            Color.sticksCream.ignoresSafeArea()

            VStack(spacing: 10) {
                Text(match.courseName)
                    .font(SticksFont.display(30))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(match.scheduledAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sticksMuted)

                Text("SCORECARD ARRIVES IN SLICE 3")
                    .font(SticksFont.label(11))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.top, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.sticksCream, for: .navigationBar)
    }
}
