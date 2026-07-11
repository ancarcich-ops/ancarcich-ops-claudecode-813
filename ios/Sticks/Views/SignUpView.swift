//
//  SignUpView.swift
//  Sticks
//
//  Slice 44: native account creation. Mirrors LoginView's dark-on-cream
//  style; POST /auth/signup returns the same { token, user } shape as
//  login, so success drops the user straight into the app signed in.
//

import SwiftUI

struct SignUpView: View {
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case username
        case email
        case displayName
        case password
    }

    /// Light client-side gate to save a round-trip — the server's 400
    /// message is still the source of truth once submitted.
    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 8
            && !isSubmitting
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    wordmark
                        .padding(.top, 48)
                        .padding(.bottom, 40)

                    VStack(spacing: 14) {
                        inputField(
                            "Username",
                            text: $username,
                            field: .username,
                            contentType: .username,
                            keyboard: .asciiCapable,
                            submitLabel: .next
                        ) {
                            focusedField = .email
                        }

                        inputField(
                            "Email",
                            text: $email,
                            field: .email,
                            contentType: .emailAddress,
                            keyboard: .emailAddress,
                            submitLabel: .next
                        ) {
                            focusedField = .displayName
                        }

                        inputField(
                            "Display name (optional)",
                            text: $displayName,
                            field: .displayName,
                            contentType: .name,
                            keyboard: .default,
                            submitLabel: .next
                        ) {
                            focusedField = .password
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            secureField

                            Text("At least 8 characters")
                                .font(SticksFont.mono(10))
                                .kerning(0.8)
                                .foregroundStyle(Color.sticksFaint)
                                .padding(.leading, 4)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(SticksFont.sans(14, weight: .medium))
                                .foregroundStyle(Color.sticksError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                                .transition(.opacity)
                        }

                        createButton
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 28)

                    signInFooter
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { focusedField = nil }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var wordmark: some View {
        VStack(spacing: 14) {
            SticksClubsMark()
                .frame(width: 64, height: 64)

            (Text("Sticks").foregroundStyle(Color.sticksInk)
                + Text(".").foregroundStyle(Color.sticksGreen))
                .font(SticksFont.display(44))

            Text("GOLF SCORING · ON-COURSE GPS")
                .font(SticksFont.label(12))
                .kerning(1.8)
                .foregroundStyle(Color.sticksMuted)
        }
    }

    private func inputField(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .textContentType(contentType)
            .textInputAutocapitalization(field == .displayName ? .words : .never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .focused($focusedField, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .sticksSignupFieldStyle(isFocused: focusedField == field)
    }

    private var secureField: some View {
        SecureField("Password", text: $password)
            .textContentType(.newPassword)
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit {
                if canSubmit { submit() }
            }
            .sticksSignupFieldStyle(isFocused: focusedField == .password)
    }

    private var createButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Create account")
                    .font(SticksFont.sans(17, weight: .semibold))
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .tint(Color.sticksCream)
                }
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSubmit || isSubmitting ? Color.sticksGreen : Color.sticksGreen.opacity(0.4))
            .clipShape(.rect(cornerRadius: 14))
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.15), value: isSubmitting)
    }

    private var signInFooter: some View {
        Button {
            dismiss()
        } label: {
            (
                Text("ALREADY HAVE AN ACCOUNT? ")
                    .foregroundStyle(Color.sticksMuted)
                + Text("SIGN IN")
                    .foregroundStyle(Color.sticksGreen)
            )
            .font(SticksFont.label(11))
            .kerning(1.2)
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPassword = password

        Task {
            defer { isSubmitting = false }
            do {
                try await session.signUp(
                    username: trimmedUsername,
                    email: trimmedEmail,
                    password: currentPassword,
                    displayName: trimmedDisplayName.isEmpty ? nil : trimmedDisplayName
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch let error as APIError {
                withAnimation { errorMessage = error.message }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } catch {
                withAnimation { errorMessage = "Something went wrong. Please try again." }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

private struct SticksSignupFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(SticksFont.sans(17))
            .foregroundStyle(Color.sticksInk)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? Color.sticksGreen : Color.sticksHairline, lineWidth: isFocused ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

private extension View {
    func sticksSignupFieldStyle(isFocused: Bool) -> some View {
        modifier(SticksSignupFieldModifier(isFocused: isFocused))
    }
}

#Preview {
    NavigationStack {
        SignUpView(session: SessionStore())
    }
}
