//
//  JoinTournamentView.swift
//  Sticks
//
//  Slice 55: the "join by code" sheet — an uppercase code field plus
//  an optional handicap, POSTing /tournaments/join. A bad code's 404
//  message shows inline, verbatim.
//

import SwiftUI
import UIKit

struct JoinTournamentView: View {
    let viewModel: TournamentsViewModel
    let session: SessionStore
    /// Called with the joined tournament's id after a successful POST.
    let onJoined: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var handicapText = ""
    @FocusState private var isCodeFocused: Bool

    private var canJoin: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isJoining
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sticksBg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("GOT AN INVITE?")
                            .font(SticksFont.mono(10.5))
                            .kerning(1.47)
                            .foregroundStyle(Color.sticksGreen)

                        codeSection
                        handicapSection

                        if let error = viewModel.joinError {
                            Text(error)
                                .font(SticksFont.sans(13))
                                .foregroundStyle(Color.sticksError)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Join a tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(SticksFont.sans(15))
                        .foregroundStyle(Color.sticksMuted)
                }
            }
            .toolbarBackground(Color.sticksBg, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { joinBar }
            .tint(Color.sticksGreen)
            .onAppear { isCodeFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("INVITE CODE")

            TextField(
                "",
                text: $code,
                prompt: Text("ABC123")
                    .font(SticksFont.mono(17))
                    .foregroundStyle(Color.sticksFaint)
            )
            .font(SticksFont.mono(17))
            .kerning(3)
            .foregroundStyle(Color.sticksInk)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($isCodeFocused)
            .submitLabel(.join)
            .onSubmit { join() }
            .onChange(of: code) { _, newValue in
                let cleaned = newValue.uppercased().filter { !$0.isWhitespace }
                if cleaned != newValue { code = cleaned }
                if viewModel.joinError != nil { viewModel.clearJoinError() }
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isCodeFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: 1)
            )
        }
    }

    private var handicapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("YOUR HANDICAP · OPTIONAL")

            TextField(
                "",
                text: $handicapText,
                prompt: Text("e.g. 11.6")
                    .font(SticksFont.sans(15))
                    .foregroundStyle(Color.sticksFaint)
            )
            .font(SticksFont.sans(15))
            .foregroundStyle(Color.sticksInk)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.sticksPanel2)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.sticksHairline, lineWidth: 1)
            )

            Text("Used as your handicap at the start of the event. Leave blank to use your latest.")
                .font(SticksFont.sans(12.5))
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(SticksFont.mono(10))
            .kerning(1.2)
            .foregroundStyle(Color.sticksFaint)
    }

    // MARK: - Join bar

    private var joinBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.sticksHairline)
                .frame(height: 1)

            Button {
                join()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isJoining {
                        ProgressView()
                            .tint(Color.sticksCream)
                            .scaleEffect(0.85)
                    }
                    Text(viewModel.isJoining ? "JOINING…" : "JOIN TOURNAMENT")
                        .font(SticksFont.sans(15, weight: .bold))
                        .kerning(0.4)
                }
                .foregroundStyle(Color.sticksCream)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.sticksGreen)
                .clipShape(.rect(cornerRadius: 13))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canJoin)
            .opacity(canJoin ? 1 : 0.55)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.sticksBg)
    }

    private func join() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !viewModel.isJoining else { return }
        let handicap = CreateMatchViewModel.parseHandicap(handicapText)
        Task {
            let id = await viewModel.join(code: trimmed, handicap: handicap, session: session)
            if let id {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onJoined(id)
            }
        }
    }
}
