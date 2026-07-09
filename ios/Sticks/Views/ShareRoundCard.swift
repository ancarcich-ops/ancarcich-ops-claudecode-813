//
//  ShareRoundCard.swift
//  Sticks
//
//  Slice 29: "Share my round" — visible to any seated player. Lists the
//  caller's live share links (copy / share sheet / stop) and creates
//  new ones via a small form: include-my-scores toggle, an optional
//  ETA-home destination address, and a heads-up buffer in minutes.
//

import SwiftUI
import UIKit

struct ShareRoundCard: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @State private var showsCreate = false
    @State private var errorMessage: String?
    @State private var stoppingShareId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHARE MY ROUND")
                .font(SticksFont.label(11, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(Color.sticksFaint)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text("A live link anyone can open — no account needed. Stop it any time.")
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksMuted)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                ForEach(viewModel.shares) { share in
                    Rectangle()
                        .fill(Color.sticksHairline.opacity(0.6))
                        .frame(height: 1)
                        .padding(.leading, 14)
                    shareRow(share)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksError)
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                }

                createButton
            }
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )
        }
        .padding(.top, 6)
        .task {
            await viewModel.loadShares(session: session)
        }
        .sheet(isPresented: $showsCreate) {
            CreateShareSheet(viewModel: viewModel, session: session)
        }
    }

    // MARK: - Rows

    private func shareRow(_ share: RoundShare) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(share.url)
                .font(SticksFont.mono(11.5))
                .foregroundStyle(Color.sticksInk)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(detailLine(share))
                .font(SticksFont.mono(10))
                .kerning(0.5)
                .foregroundStyle(Color.sticksFaint)
                .lineLimit(1)

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = share.url
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    chipLabel(icon: "doc.on.doc", label: "Copy")
                }
                .buttonStyle(.plain)

                if let url = URL(string: share.url) {
                    ShareLink(item: url) {
                        chipLabel(icon: "square.and.arrow.up", label: "Share")
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 8)

                Button {
                    stopShare(share)
                } label: {
                    if stoppingShareId == share.id {
                        ProgressView()
                            .tint(Color.sticksError)
                            .frame(width: 60, height: 30)
                    } else {
                        chipLabel(icon: "stop.fill", label: "Stop", tint: .sticksError)
                    }
                }
                .buttonStyle(.plain)
                .disabled(stoppingShareId != nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func detailLine(_ share: RoundShare) -> String {
        var parts = [share.includeScores ? "SCORES ON" : "SCORES OFF"]
        if let address = share.destAddress, !address.isEmpty {
            parts.append("ETA → \(address.uppercased())")
        }
        if share.bufferMin > 0 {
            parts.append("\(share.bufferMin) MIN HEADS-UP")
        }
        return parts.joined(separator: " · ")
    }

    private func chipLabel(icon: String, label: String, tint: Color = .sticksGreen) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(SticksFont.mono(11))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(tint.opacity(0.08))
        .clipShape(.capsule)
        .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 1))
        .contentShape(.capsule)
    }

    private var createButton: some View {
        Button {
            showsCreate = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(viewModel.shares.isEmpty ? "Create link" : "Create another link")
                    .font(SticksFont.sans(14, weight: .semibold))
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.sticksGreen)
            .clipShape(.rect(cornerRadius: 11))
            .padding(12)
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// DELETE /shares/:id → refreshed list. Errors show inline verbatim.
    private func stopShare(_ share: RoundShare) {
        stoppingShareId = share.id
        errorMessage = nil
        Task {
            defer { stoppingShareId = nil }
            do {
                try await viewModel.deleteShare(id: share.id, session: session)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}

// MARK: - Create form

/// Small create-link form: include-scores toggle (default ON), optional
/// destination address for ETA-home, and a 0–180 min heads-up buffer.
private struct CreateShareSheet: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var includeScores = true
    @State private var address = ""
    @State private var bufferText = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create live link")
                .font(SticksFont.display(24, weight: .bold))
                .foregroundStyle(Color.sticksInk)

            Toggle(isOn: $includeScores) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include my scores")
                        .font(SticksFont.sans(15, weight: .semibold))
                        .foregroundStyle(Color.sticksInk)
                    Text("Viewers see your scorecard as you play")
                        .font(SticksFont.sans(12))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
            .tint(Color.sticksGreen)

            field(
                label: "ADDRESS YOU'RE HEADED TO (OPTIONAL)",
                hint: "Shows viewers a live ETA home after the round"
            ) {
                TextField("123 Clubhouse Ln", text: $address)
                    .textInputAutocapitalization(.words)
            }

            field(
                label: "HEADS-UP BUFFER (MIN)",
                hint: "0–180 minutes added before the heads-up goes out"
            ) {
                TextField("0", text: $bufferText)
                    .keyboardType(.numberPad)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
            }

            Spacer(minLength: 0)

            Button {
                submit()
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text("Create link")
                            .font(SticksFont.sans(16, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isSubmitting)
        }
        .padding(20)
        .presentationDetents([.height(478)])
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    private func field<Content: View>(
        label: String,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SticksFont.mono(10))
                .kerning(0.8)
                .foregroundStyle(Color.sticksFaint)

            content()
                .font(SticksFont.sans(15))
                .foregroundStyle(Color.sticksInk)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Color.sticksPanel2)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )

            Text(hint)
                .font(SticksFont.sans(11.5))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    /// Validates the buffer (0–180), then POST /matches/:id/shares →
    /// refreshed list → dismiss. Server errors show inline verbatim.
    private func submit() {
        guard !isSubmitting else { return }
        let trimmedBuffer = bufferText.trimmingCharacters(in: .whitespaces)
        let buffer = trimmedBuffer.isEmpty ? 0 : Int(trimmedBuffer)
        guard let buffer, (0 ... 180).contains(buffer) else {
            errorMessage = "Heads-up buffer must be 0–180 minutes."
            return
        }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        errorMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                try await viewModel.createShare(
                    includeScores: includeScores,
                    destAddress: trimmedAddress.isEmpty ? nil : trimmedAddress,
                    bufferMin: buffer,
                    session: session
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch let error as APIError {
                errorMessage = error.message
            } catch {
                errorMessage = "Can't reach Sticks. Check your connection and try again."
            }
        }
    }
}
