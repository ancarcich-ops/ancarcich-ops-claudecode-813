//
//  EditParsSheet.swift
//  Sticks
//
//  Slice 29: creator-only par editing — one stepper per hole (3–6),
//  pre-filled from the match's pars, with a running total. Save posts
//  the full array and the detail re-fetches so the scorecard, net
//  games and side games recompute. Legit at ANY status.
//

import SwiftUI
import UIKit

struct EditParsSheet: View {
    let detail: MatchDetail
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var pars: [Int]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(detail: MatchDetail, viewModel: MatchDetailViewModel, session: SessionStore) {
        self.detail = detail
        self.viewModel = viewModel
        self.session = session
        _pars = State(initialValue: (0 ..< detail.holes).map { detail.par(at: $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0 ..< detail.holes, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.sticksHairline.opacity(0.6))
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                        holeRow(index)
                    }
                }
                .background(Color.sticksCard)
                .clipShape(.rect(cornerRadius: SticksMetrics.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: SticksMetrics.cardRadius)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            footer
        }
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Edit pars")
                    .font(SticksFont.display(26, weight: .bold))
                    .foregroundStyle(Color.sticksInk)

                Spacer()

                Text("PAR \(pars.reduce(0, +))")
                    .font(SticksFont.mono(14))
                    .kerning(1.1)
                    .foregroundStyle(Color.sticksGreen)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: pars)
            }

            Text("3–6 per hole. Net games and side games recompute from the new pars.")
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func holeRow(_ index: Int) -> some View {
        HStack(spacing: 10) {
            Text("HOLE \(detail.holeNumber(at: index))")
                .font(SticksFont.mono(11))
                .kerning(0.8)
                .foregroundStyle(Color.sticksMuted)
                .frame(width: 76, alignment: .leading)

            Spacer(minLength: 0)

            Text("\(pars[index])")
                .font(SticksFont.display(20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.sticksInk)
                .frame(width: 28)

            Stepper("Par for hole \(detail.holeNumber(at: index))", value: $pars[index], in: 3 ... 6)
                .labelsHidden()
                .tint(Color.sticksGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(SticksFont.sans(12.5))
                    .foregroundStyle(Color.sticksError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                save()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text("Save pars")
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
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// POST /matches/:id/pars → quiet detail refresh → dismiss. 400/403
    /// server messages show inline verbatim.
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await viewModel.setPars(pars, session: session)
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
