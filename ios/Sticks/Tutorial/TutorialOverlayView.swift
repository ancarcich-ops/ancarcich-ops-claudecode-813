//
//  TutorialOverlayView.swift
//  Sticks
//
//  The coach-mark overlay: a warm ink dim over the whole screen with a
//  rounded spotlight cut around the current target, a green ring that
//  pulses twice when a step lands, and the step card (badge, title,
//  N/M, copy, Skip / Back / Next) with a small arrow aimed at the
//  target. Steps without a target show the card centered over a full
//  dim. Everything animates between steps; nothing loops forever.
//

import SwiftUI
import UIKit

struct TutorialOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var cardSize: CGSize = CGSize(width: 340, height: 170)

    private var center: TutorialCenter { .shared }

    private let cardGap: CGFloat = 16
    private let arrowHeight: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo)

            ZStack(alignment: .topLeading) {
                SpotlightShape(rect: layout.spot, cornerRadius: layout.spotRadius)
                    .fill(Color.sticksInk.opacity(0.64), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    // Swallow taps outside the card — the tour is modal.
                    .onTapGesture {}
                    .accessibilityHidden(true)

                if layout.hasTarget {
                    SpotlightRing(rect: layout.spot, cornerRadius: layout.spotRadius, stepID: center.currentStep?.id ?? "")
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let step = center.currentStep {
                    card(step, arrowX: layout.arrowX, arrowOnTop: layout.cardBelow, hasTarget: layout.hasTarget)
                        .frame(width: layout.cardWidth)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
                        .offset(x: layout.cardOrigin.x, y: layout.cardOrigin.y)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.42, bounce: 0.16), value: center.stepIndex)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: layout.spot)
        }
        .ignoresSafeArea()
        .opacity(appeared && !center.isClosing ? 1 : 0)
        .animation(.easeOut(duration: 0.24), value: appeared)
        .animation(.easeOut(duration: 0.24), value: center.isClosing)
        .onAppear { appeared = true }
        .onChange(of: center.stepIndex) { _, _ in
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    // MARK: - Layout

    private struct Layout {
        var spot: CGRect
        var spotRadius: CGFloat
        var hasTarget: Bool
        var cardWidth: CGFloat
        var cardOrigin: CGPoint
        var cardBelow: Bool
        var arrowX: CGFloat
    }

    private func layout(in geo: GeometryProxy) -> Layout {
        let size = geo.size
        let origin = geo.frame(in: .global).origin
        let insets = geo.safeAreaInsets
        let cardWidth = min(size.width - 32, 420)
        let cardX = (size.width - cardWidth) / 2

        guard let target = center.currentStep?.target,
              var spot = center.frames[target]
        else {
            // Centered card, full dim; the cut-out collapses to a point.
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            return Layout(
                spot: CGRect(origin: mid, size: .zero),
                spotRadius: 0,
                hasTarget: false,
                cardWidth: cardWidth,
                cardOrigin: CGPoint(x: cardX, y: (size.height - cardSize.height) / 2),
                cardBelow: false,
                arrowX: cardWidth / 2
            )
        }

        spot = spot.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -6, dy: -6)
        // Keep the cut-out on screen, and cap tall targets (a long card
        // list) to their top part so the step card still fits.
        spot = spot.intersection(CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 0))
        if spot.isNull { spot = CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0) }
        let maxSpotHeight = size.height * 0.36
        if spot.height > maxSpotHeight {
            spot.size.height = maxSpotHeight
        }
        let radius = min(16, spot.height / 2)

        let roomAbove = spot.minY - insets.top
        let roomBelow = size.height - insets.bottom - spot.maxY
        let below = roomBelow >= roomAbove
        var cardY = below
            ? spot.maxY + cardGap
            : spot.minY - cardGap - cardSize.height
        cardY = min(max(cardY, insets.top + 8), size.height - insets.bottom - cardSize.height - 8)

        let arrowX = min(max(spot.midX - cardX, 28), cardWidth - 28)

        return Layout(
            spot: spot,
            spotRadius: radius,
            hasTarget: true,
            cardWidth: cardWidth,
            cardOrigin: CGPoint(x: cardX, y: cardY),
            cardBelow: below,
            arrowX: arrowX
        )
    }

    // MARK: - Card

    private func card(_ step: TutorialStep, arrowX: CGFloat, arrowOnTop: Bool, hasTarget: Bool) -> some View {
        let isFirst = center.stepIndex == 0
        let isLast = center.stepIndex == center.steps.count - 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    Circle().fill(Color.sticksGreen.opacity(0.12))
                    Image(systemName: step.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sticksGreen)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                Text(step.title)
                    .font(SticksFont.display(20))
                    .foregroundStyle(Color.sticksInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Text("\(center.stepIndex + 1)/\(center.steps.count)")
                    .font(SticksFont.mono(11))
                    .kerning(0.8)
                    .foregroundStyle(Color.sticksFaint)
                    .monospacedDigit()
                    .accessibilityLabel("Step \(center.stepIndex + 1) of \(center.steps.count)")
            }

            Text(step.body)
                .font(SticksFont.sans(14.5))
                .foregroundStyle(Color.sticksMuted)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)

            progressBar

            HStack(spacing: 8) {
                if !isLast {
                    Button("Skip") { center.skip() }
                        .font(SticksFont.mono(11.5))
                        .kerning(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.sticksMuted)
                        .frame(minWidth: 44, minHeight: 40, alignment: .leading)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skip tour")
                }

                Spacer(minLength: 0)

                if !isFirst {
                    Button { center.back() } label: {
                        Text("Back")
                            .font(SticksFont.sans(14.5, weight: .semibold))
                            .foregroundStyle(Color.sticksInk)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Color.sticksPanel2)
                            .clipShape(.capsule)
                            .overlay(Capsule().stroke(Color.sticksHairline, lineWidth: 1))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                Button { center.next() } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? "Got it" : "Next")
                            .font(SticksFont.sans(14.5, weight: .bold))
                        if !isLast {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.sticksCream)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Color.sticksGreen)
                    .clipShape(.capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(isLast ? "Got it, finish tour" : "Next step")
            }
        }
        .id(step.id)
        .transition(.opacity)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            CardWithArrow(
                arrowX: arrowX,
                arrowOnTop: arrowOnTop,
                showsArrow: hasTarget,
                arrowHeight: arrowHeight
            )
            .fill(Color.sticksCard)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .overlay {
                CardWithArrow(
                    arrowX: arrowX,
                    arrowOnTop: arrowOnTop,
                    showsArrow: hasTarget,
                    arrowHeight: arrowHeight
                )
                .stroke(Color.sticksHairline, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A thin segmented bar under the copy — one segment per step.
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< center.steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= center.stepIndex ? Color.sticksGreen : Color.sticksHairline)
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

/// Full-screen rect minus a rounded cut-out; animates between targets.
private struct SpotlightShape: Shape {
    var rect: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(
                AnimatablePair(rect.origin.x, rect.origin.y),
                AnimatablePair(rect.size.width, AnimatablePair(rect.size.height, cornerRadius))
            )
        }
        set {
            rect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second.first
            )
            cornerRadius = newValue.second.second.second
        }
    }

    func path(in bounds: CGRect) -> Path {
        var path = Path(bounds)
        if rect.width > 0, rect.height > 0 {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}

/// The card's rounded body with a small arrow on the edge facing the
/// target.
private struct CardWithArrow: Shape {
    var arrowX: CGFloat
    var arrowOnTop: Bool
    var showsArrow: Bool
    var arrowHeight: CGFloat

    var animatableData: CGFloat {
        get { arrowX }
        set { arrowX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 18, style: .continuous)
        guard showsArrow else { return path }
        let half: CGFloat = 9
        var arrow = Path()
        if arrowOnTop {
            arrow.move(to: CGPoint(x: arrowX - half, y: rect.minY + 0.5))
            arrow.addLine(to: CGPoint(x: arrowX, y: rect.minY - arrowHeight))
            arrow.addLine(to: CGPoint(x: arrowX + half, y: rect.minY + 0.5))
        } else {
            arrow.move(to: CGPoint(x: arrowX - half, y: rect.maxY - 0.5))
            arrow.addLine(to: CGPoint(x: arrowX, y: rect.maxY + arrowHeight))
            arrow.addLine(to: CGPoint(x: arrowX + half, y: rect.maxY - 0.5))
        }
        arrow.closeSubpath()
        path.addPath(arrow)
        return path
    }
}

/// Green outline on the cut-out plus a halo that pulses twice when a
/// step lands, then rests.
private struct SpotlightRing: View {
    let rect: CGRect
    let cornerRadius: CGFloat
    let stepID: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.sticksGreen, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                .stroke(Color.sticksGreen.opacity(pulse ? 0 : 0.55), lineWidth: 3)
                .frame(width: rect.width + 8, height: rect.height + 8)
                .scaleEffect(pulse ? 1.08 : 1)
                .offset(x: rect.minX - 4, y: rect.minY - 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: stepID) {
            guard !reduceMotion else { return }
            for _ in 0 ..< 2 {
                pulse = false
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.easeOut(duration: 0.9)) { pulse = true }
                try? await Task.sleep(for: .milliseconds(950))
            }
        }
    }
}
