//
//  HoleRailView.swift
//  Sticks
//
//  Horizontal hole chips (1–18) with par and the player's score, used to
//  switch holes on the on-course GPS screen. Auto-scrolls to the current
//  hole. Sits on a dark scrim over the satellite map.
//

import SwiftUI

struct HoleRailView: View {
    let detail: MatchDetail
    /// The caller's scores keyed by absolute hole number.
    let scores: [Int: Int]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0 ..< detail.holes, id: \.self) { index in
                        chip(index: index)
                            .id(index)
                    }
                }
                .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, 16)
            .onAppear {
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private func chip(index: Int) -> some View {
        let hole = detail.holeNumber(at: index)
        let par = detail.par(at: index)
        let score = scores[hole]
        let isSelected = index == selectedIndex

        return Button {
            selectedIndex = index
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 1) {
                Text("\(hole)")
                    .font(SticksFont.display(17))
                Text("PAR \(par)")
                    .font(SticksFont.label(8))
                    .kerning(0.5)
                    .opacity(0.75)
                Text(score.map(String.init) ?? "·")
                    .font(SticksFont.label(11, weight: .bold))
                    .foregroundStyle(scoreColor(score: score, par: par, isSelected: isSelected))
            }
            .foregroundStyle(isSelected ? Color.sticksCream : .white)
            .frame(width: 50, height: 58)
            .background(isSelected ? Color.sticksGreen : Color.black.opacity(0.38))
            .clipShape(.rect(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? Color.sticksCream.opacity(0.5) : .white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func scoreColor(score: Int?, par: Int, isSelected: Bool) -> Color {
        guard let score else { return .white.opacity(0.45) }
        if score < par { return Color(red: 0.62, green: 0.9, blue: 0.68) }
        if score > par { return Color(red: 0.96, green: 0.72, blue: 0.6) }
        return isSelected ? Color.sticksCream : .white
    }
}
