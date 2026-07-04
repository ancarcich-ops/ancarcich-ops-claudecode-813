//
//  LoginView.swift
//  Sticks
//
//  Dark-on-cream sign-in screen matching the Sticks web app.
//

import SwiftUI

struct LoginView: View {
    let session: SessionStore

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case identifier
        case password
    }

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    var body: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    wordmark
                        .padding(.top, 72)
                        .padding(.bottom, 56)

                    VStack(spacing: 14) {
                        inputField(
                            "Username or email",
                            text: $identifier,
                            field: .identifier,
                            contentType: .username,
                            submitLabel: .next
                        ) {
                            focusedField = .password
                        }

                        secureField

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.sticksError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                                .transition(.opacity)
                        }

                        signInButton
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 28)

                    Text("MATCHES ARE CREATED ON THE WEB APP")
                        .font(SticksFont.label(11))
                        .kerning(1.2)
                        .foregroundStyle(Color.sticksMuted)
                        .padding(.top, 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onTapGesture { focusedField = nil }
    }

    private var wordmark: some View {
        VStack(spacing: 14) {
            Image("SticksMark")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .clipShape(.rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.sticksHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
                .accessibilityHidden(true)

            Text("Sticks")
                .font(SticksFont.display(56))
                .foregroundStyle(Color.sticksInk)

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
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        TextField(placeholder, text: text)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .focused($focusedField, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .sticksFieldStyle(isFocused: focusedField == field)
    }

    private var secureField: some View {
        SecureField("Password", text: $password)
            .textContentType(.password)
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit {
                if canSubmit { submit() }
            }
            .sticksFieldStyle(isFocused: focusedField == .password)
    }

    private var signInButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Sign In")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
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

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespaces)
        let currentPassword = password

        Task {
            defer { isSubmitting = false }
            do {
                try await session.signIn(identifier: trimmedIdentifier, password: currentPassword)
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

private struct SticksFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 17))
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
    func sticksFieldStyle(isFocused: Bool) -> some View {
        modifier(SticksFieldModifier(isFocused: isFocused))
    }
}

#Preview {
    LoginView(session: SessionStore())
}
