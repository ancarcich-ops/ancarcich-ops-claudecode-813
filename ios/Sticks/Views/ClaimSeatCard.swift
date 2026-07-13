//
//  ClaimSeatCard.swift
//  Sticks
//
//  Slice 61: "Claim your seat." Rounds often add players by name, so a
//  seat can have no linked account (userId == nil). When the server says
//  the caller can claim (canClaimSeat), this card offers one "I'm {name}"
//  pill per unlinked seat. A successful claim re-fetches the detail —
//  canClaimSeat flips false, the card disappears, and scoring/your-round
//  treatment turns on.
//

import SwiftUI
import UIKit

struct ClaimSeatCard: View {
    let detail: MatchDetail
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    /// Seats added by name that no account holds yet.
    private var unlinkedSeats: [MatchDetailPlayer] {
        detail.players
            .filter { $0.userId == nil }
            .sorted { ($0.seat ?? Int.max) < ($1.seat ?? Int.max) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
                    .frame(width: 34, height: 34)
                    .background(Color.sticksGreen.opacity(0.1))
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Played in this round?")
                        .font(SticksFont.sans(16, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                    Text("Claim your spot so it counts toward your stats.")
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // One pill per unlinked seat, wrapping as needed.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(unlinkedSeats) { seat in
                    seatPill(seat)
                }
            }

            if let message = viewModel.claimError {
                Text(message)
                    .font(SticksFont.sans(12, weight: .medium))
                    .foregroundStyle(Color.sticksError)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                .stroke(Color.sticksGreen.opacity(0.35), lineWidth: 1)
        )
    }

    private func seatPill(_ seat: MatchDetailPlayer) -> some View {
        let isClaimingThis = viewModel.claimingSeatId == seat.id
        let isBusy = viewModel.claimingSeatId != nil
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await viewModel.claimSeat(matchPlayerId: seat.id, session: session)
                if viewModel.claimError == nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isClaimingThis {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.sticksCream)
                } else {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("I'm \(seat.displayName)")
                    .font(SticksFont.sans(14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.sticksCream)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Color.sticksGreen.opacity(isBusy && !isClaimingThis ? 0.5 : 1))
            .clipShape(.capsule)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isBusy)
        .accessibilityLabel("Claim the seat named \(seat.displayName)")
    }
}
