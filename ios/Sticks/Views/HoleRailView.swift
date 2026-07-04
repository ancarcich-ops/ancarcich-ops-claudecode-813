//
//  HoleRailView.swift
//  Sticks
//
//  Horizontal hole chips (1–18) with par and the player's score, used to
//  switch holes on the on-course GPS screen. Auto-scrolls to the current
//  hole. Sits on a dark scrim over the satellite map, sharing its row
//  with the fixed back button — chips scroll behind it and fade out at
//  the leading edge.
//

import SwiftUI

struct HoleRailView: View {
    let detail: MatchDetail
    /// The caller's scores keyed by absolute hole number.
    let scores: [Int: Int]
    @Binding var selectedIndex: Int

    /// Space reserved at the leading edge so the first chip rests fully
    /// visible to the right of the fixed back button at scroll zero
    /// (12pt inset + 44pt button + 12pt gap).
    private let leadingInset: CGFloat = 68

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
            .contentMargins(.leading, leadingInset)
            .contentMargins(.trailing, 16)
            .mask(leadingFadeMask)
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

    /// Soft fade at the leading edge so chips slide under the back button
    /// gracefully instead of clipping hard against it.
    private var leadingFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: leadingInset)
            Rectangle().fill(.black)
        }
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
            VStack(spacing: 2) {
                Text("\(hole)")
                    .font(SticksFont.display(17))
                Text("PAR \(par)")
                    .font(SticksFont.label(8))
                    .kerning(0.5)
                    .opacity(0.75)
                scoreBadge(score: score, par: par)
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

    /// The player's score as a tiny score-state badge (web palette): the
    /// fill encodes the par-relation, the number disambiguates. The par
    /// state's ink text is swapped for cream so it reads on the dark rail.
    @ViewBuilder
    private func scoreBadge(score: Int?, par: Int) -> some View {
        if let score {
            let style = ScoreStyle.forScore(score, par: par)
            Text("\(score)")
                .font(SticksFont.mono(10, weight: .bold))
                .foregroundStyle(style.text == Color.sticksInk ? Color.sticksCream : style.text)
                .frame(minWidth: 18)
                .frame(height: 14)
                .padding(.horizontal, 2)
                .background(style.fill)
                .clipShape(.rect(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            style.ring ?? (style.border == .clear ? .white.opacity(0.25) : style.border),
                            lineWidth: style.ring != nil ? 1.2 : 0.8
                        )
                )
        } else {
            Text("·")
                .font(SticksFont.label(11, weight: .bold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: 14)
        }
    }
}
