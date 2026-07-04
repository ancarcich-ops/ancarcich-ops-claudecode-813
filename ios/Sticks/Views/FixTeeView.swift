//
//  FixTeeView.swift
//  Sticks
//
//  Slice 6: FIX TEE crowdfix confirm card. Confirm-first — nothing is
//  written on a single tap. The card shows LIVE GPS accuracy and the
//  here→green distance next to the scorecard yardage so the user can
//  sanity-check before confirming. POST /matches/:id/tee includes
//  accuracyYd; an `ok: false` verdict shows the server's reason verbatim
//  with a Try Again button.
//

import SwiftUI
import CoreLocation

struct FixTeeView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore
    let locationService: LocationService
    let hole: Int
    let geo: HoleGeo?

    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case confirm
        case submitting
        case rejected(String)
        case success
    }

    @State private var phase: Phase = .confirm
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            header

            switch phase {
            case .confirm, .submitting:
                confirmCard
            case .rejected(let reason):
                rejectedCard(reason)
            case .success:
                successCard
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(400)])
        .presentationBackground(Color.sticksBg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("FIX TEE · HOLE \(hole)")
                .font(SticksFont.label(11))
                .kerning(1.8)
                .foregroundStyle(Color.sticksMuted)

            Text("Stand on the tee box you play from")
                .font(SticksFont.display(24))
                .foregroundStyle(Color.sticksInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Confirm state

    /// GPS accuracy and here→green read LIVE from the location service —
    /// they keep updating while the card is open.
    private var confirmCard: some View {
        let accuracy = locationService.horizontalAccuracyYards
        let hereToGreen = hereToGreenYards
        let cardYardage = geo?.distanceYds

        return VStack(spacing: 16) {
            HStack(spacing: 10) {
                statBox(
                    label: "GPS ACCURACY",
                    value: accuracy.map { "±\(Int($0.rounded()))" } ?? "—",
                    unit: accuracy != nil ? "YDS" : nil,
                    tint: accuracyTint(accuracy)
                )
                statBox(
                    label: "HERE → GREEN",
                    value: hereToGreen.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: hereToGreen != nil ? "YDS" : nil,
                    tint: Color.sticksInk
                )
                statBox(
                    label: "SCORECARD",
                    value: cardYardage.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: cardYardage != nil ? "YDS" : nil,
                    tint: Color.sticksMuted
                )
            }

            if let errorMessage {
                inlineError(errorMessage)
            } else if !accuracyIsGoodEnough(accuracy) {
                Text("Waiting for GPS accuracy of ±35 yds or better…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.sticksMuted)
            }

            Button {
                submit()
            } label: {
                Group {
                    if phase == .submitting {
                        ProgressView().tint(Color.sticksCream)
                    } else {
                        Text("CONFIRM TEE LOCATION")
                            .font(SticksFont.label(14, weight: .bold))
                            .kerning(2)
                    }
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canConfirm ? Color.sticksGreen : Color.sticksMuted.opacity(0.5))
                .clipShape(.rect(cornerRadius: 13))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canConfirm || phase == .submitting)

            Button("Cancel") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Color.sticksMuted)
                .disabled(phase == .submitting)
        }
    }

    private func statBox(label: String, value: String, unit: String?, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(SticksFont.label(8.5))
                .kerning(0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.sticksMuted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(SticksFont.display(24))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(SticksFont.label(8, weight: .bold))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color.sticksCard)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sticksHairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.25), value: value)
    }

    // MARK: - Rejected state

    /// Server said no — the reason renders VERBATIM, with a retry path.
    private func rejectedCard(_ reason: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.sticksError)
                Text(reason)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.sticksInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksError.opacity(0.35), lineWidth: 1)
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { phase = .confirm }
            } label: {
                Text("TRY AGAIN")
                    .font(SticksFont.label(14, weight: .bold))
                    .kerning(2)
                    .foregroundStyle(Color.sticksCream)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.sticksGreen)
                    .clipShape(.rect(cornerRadius: 13))
            }
            .buttonStyle(PressableButtonStyle())

            Button("Cancel") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    // MARK: - Success state

    private var successCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.sticksGreen)
            Text("Tee updated")
                .font(SticksFont.display(22))
                .foregroundStyle(Color.sticksInk)
            Text("Thanks — hole \(hole) now uses your position.")
                .font(.system(size: 14))
                .foregroundStyle(Color.sticksMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.sticksError)
    }

    // MARK: - Logic

    private var hereToGreenYards: Double? {
        guard let here = locationService.coordinate,
              let green = geo?.greenCoordinate else { return nil }
        return GolfGeo.yards(from: here, to: green)
    }

    private func accuracyIsGoodEnough(_ accuracy: Double?) -> Bool {
        guard let accuracy else { return false }
        return accuracy <= GolfGeo.maxTeeFixAccuracyYards
    }

    private func accuracyTint(_ accuracy: Double?) -> Color {
        accuracyIsGoodEnough(accuracy) ? Color.sticksGreen : Color.sticksError
    }

    private var canConfirm: Bool {
        locationService.coordinate != nil && accuracyIsGoodEnough(locationService.horizontalAccuracyYards)
    }

    /// Confirm-first write: only runs from the explicit confirm button.
    /// Captures the fix at the moment of confirmation.
    private func submit() {
        guard phase != .submitting,
              let here = locationService.coordinate,
              let accuracy = locationService.horizontalAccuracyYards else { return }
        phase = .submitting
        errorMessage = nil

        Task {
            do {
                let verdict = try await viewModel.submitTee(
                    hole: hole,
                    lat: here.latitude,
                    lng: here.longitude,
                    accuracyYd: Int(accuracy.rounded()),
                    session: session
                )
                if verdict.ok {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeInOut(duration: 0.25)) { phase = .success }
                    try? await Task.sleep(for: .seconds(1.4))
                    dismiss()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    let reason = verdict.reason ?? "The server rejected this tee position."
                    withAnimation(.easeInOut(duration: 0.25)) { phase = .rejected(reason) }
                }
            } catch let error as APIError {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                phase = .confirm
                errorMessage = error.message
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                phase = .confirm
                errorMessage = "Couldn't reach the server. Try again."
            }
        }
    }
}
