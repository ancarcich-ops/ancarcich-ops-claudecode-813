//
//  WelcomeView.swift
//  Sticks
//
//  Slice 42: the first-launch welcome — a short paged flow mirroring
//  the website's onboarding (brand moment + feature showcase + a
//  "you're set" send-off). Purely presentational, no network. Shown
//  once after first sign-in, gated by sticks.welcomed.v1; Settings can
//  replay it.
//

import SwiftUI
import UIKit

/// How the user left the welcome flow — Home lands on the feed,
/// newRound opens the create wizard.
enum WelcomeOutcome {
    case home
    case newRound
}

struct WelcomeView: View {
    let onFinish: (WelcomeOutcome) -> Void

    @State private var page: Int = 0

    private let pageCount = 2

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage
                    .tag(0)

                readyPage
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: page)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onFinish(.home)
            } label: {
                Text("SKIP")
                    .font(SticksFont.mono(11))
                    .kerning(1.2)
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.sticksCard)
                    .clipShape(.capsule)
                    .overlay(
                        Capsule().stroke(Color.sticksHairline, lineWidth: 1)
                    )
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 18) {
            progressDots

            if page == 0 {
                primaryButton("Continue") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.3)) { page = 1 }
                }
            } else {
                VStack(spacing: 10) {
                    primaryButton("New round") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onFinish(.newRound)
                    }

                    Button {
                        onFinish(.home)
                    } label: {
                        Text("Take me home")
                            .font(SticksFont.sans(15, weight: .medium))
                            .foregroundStyle(Color.sticksMuted)
                            .frame(height: 34)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    private var progressDots: some View {
        HStack(spacing: 7) {
            ForEach(0 ..< pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.sticksGreen : Color.sticksHairline)
                    .frame(width: index == page ? 20 : 7, height: 7)
                    .animation(.spring(duration: 0.3), value: page)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(SticksFont.sans(17, weight: .semibold))
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 14))
                .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Page 1: welcome + feature showcase

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    SticksClubsMark()
                        .frame(width: 52, height: 52)

                    Text("WELCOME TO STICKS")
                        .font(SticksFont.mono(11))
                        .kerning(1.6)
                        .foregroundStyle(Color.sticksGreen)

                    Text("All your games.\nOne app.")
                        .font(SticksFont.display(40))
                        .foregroundStyle(Color.sticksInk)
                        .lineSpacing(2)

                    Text("Score any format, watch the odds move, and settle up before the 19th hole.")
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksMuted)
                        .lineSpacing(3)
                }
                .padding(.top, 8)
                .padding(.bottom, 26)

                VStack(spacing: 10) {
                    featureCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "A live betting market",
                        line: "Win odds blend the model, the crowd, and live scores — tap Place your call to back who wins."
                    )
                    featureCard(
                        icon: "flag.2.crossed",
                        title: "Every game in your group",
                        line: "Skins, Stableford, Nassau, Wolf, BBB, Snake, Sixes, plus team formats."
                    )
                    featureCard(
                        icon: "dial.medium",
                        title: "Course-fair handicaps & stats",
                        line: "A true WHS index with rating & slope per tee — net scoring is fair anywhere."
                    )
                    featureCard(
                        icon: "map",
                        title: "On-course GPS + 3D flyover",
                        line: "Live distances, front/center/back, and a photorealistic tee→green flyover of every hole."
                    )
                    featureCard(
                        icon: "square.and.arrow.up",
                        title: "Share any round",
                        line: "A live link anyone can open — no account needed."
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func featureCard(icon: String, title: String, line: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.sticksGreen.opacity(0.1))

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.sticksGreen)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SticksFont.sans(15, weight: .semibold))
                    .foregroundStyle(Color.sticksInk)

                Text(line)
                    .font(SticksFont.sans(13))
                    .foregroundStyle(Color.sticksMuted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
    }

    // MARK: - Page 2: you're set

    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                SticksClubsMark()
                    .frame(width: 88, height: 88)

                Text("YOU'RE SET")
                    .font(SticksFont.mono(11))
                    .kerning(1.6)
                    .foregroundStyle(Color.sticksGreen)

                Text("Time to open a line.")
                    .font(SticksFont.displayItalic(34))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.center)

                Text("Start a round, invite your group,\nand let the market do the talking.")
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    WelcomeView { _ in }
}
