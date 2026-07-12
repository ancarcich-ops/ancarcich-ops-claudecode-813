//
//  LoginView.swift
//  Sticks
//
//  Dark-on-cream sign-in screen matching the Sticks web app.
//  Slice 51: brand tagline, textured backdrop, show/hide password,
//  forgot-password link, and Face ID / Touch ID sign-in.
//

import SwiftUI

struct LoginView: View {
    let session: SessionStore

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting: Bool = false

    @State private var showsPassword: Bool = false
    @State private var showsSignUp: Bool = false

    /// Slice 51: a biometric token exists AND the device can evaluate it.
    @State private var canUseBiometricSignIn: Bool = false
    @State private var isBiometricSubmitting: Bool = false

    @Environment(\.openURL) private var openURL

    @FocusState private var focusedField: Field?

    private static let forgotPasswordURL = URL(string: "https://sticks-golf.vercel.app/forgot-password")

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
        NavigationStack {
            loginContent
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showsSignUp) {
                    SignUpView(session: session)
                }
        }
    }

    private var loginContent: some View {
        ScrollView {
                VStack(spacing: 0) {
                    wordmark
                        .padding(.top, 64)
                        .padding(.bottom, 48)

                    VStack(spacing: 14) {
                        Text("WELCOME BACK")
                            .font(SticksFont.mono(11))
                            .kerning(1.6)
                            .foregroundStyle(Color.sticksMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)

                        inputField(
                            "Username or email",
                            text: $identifier,
                            field: .identifier,
                            contentType: .username,
                            submitLabel: .next
                        ) {
                            focusedField = .password
                        }

                        passwordField

                        if let errorMessage {
                            Text(errorMessage)
                                .font(SticksFont.sans(14, weight: .medium))
                                .foregroundStyle(Color.sticksError)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                                .transition(.opacity)
                        }

                        signInButton
                            .padding(.top, 10)

                        if canUseBiometricSignIn {
                            biometricButton
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 28)

                    forgotPasswordLink
                        .padding(.top, 28)

                    signUpFooter
                        .padding(.top, 18)
                }
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(backdrop)
        .onTapGesture { focusedField = nil }
        .onAppear {
            canUseBiometricSignIn = BiometricService.isAvailable && session.isBiometricSignInEnabled
        }
    }

    // MARK: - Backdrop (slice 51)

    /// Cream with subtle depth — a warmer wash at the top and faint
    /// course-contour rings behind the logo. Quiet, Caddie's Notebook.
    /// Applied via `.background` so the oversized rings can never widen
    /// the layout and push the form off-screen.
    private var backdrop: some View {
        ZStack {
            Color.sticksBg.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 244 / 255, green: 238 / 255, blue: 225 / 255),
                    Color.sticksBg,
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.6)
            )
            .ignoresSafeArea()

            ContourBackdrop()
                .frame(width: 1, height: 1)
                .offset(y: -160)
        }
    }

    /// Slice 43/44: the stale "matches are created on the web" line is
    /// gone — new users get a pointer into the native sign-up screen.
    private var signUpFooter: some View {
        Button {
            focusedField = nil
            showsSignUp = true
        } label: {
            HStack(spacing: 6) {
                (
                    Text("NEW TO STICKS? ")
                        .foregroundStyle(Color.sticksMuted)
                    + Text("CREATE AN ACCOUNT")
                        .foregroundStyle(Color.sticksGreen)
                )
                .font(SticksFont.label(11))
                .kerning(1.2)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sticksGreen)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Slice 51: no native reset flow — opens the web page.
    private var forgotPasswordLink: some View {
        Button {
            focusedField = nil
            if let url = Self.forgotPasswordURL {
                openURL(url)
            }
        } label: {
            Text("FORGOT PASSWORD?")
                .font(SticksFont.label(11))
                .kerning(1.2)
                .foregroundStyle(Color.sticksMuted)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var wordmark: some View {
        VStack(spacing: 14) {
            SticksClubsMark()
                .frame(width: 76, height: 76)

            (Text("Sticks").foregroundStyle(Color.sticksInk)
                + Text(".").foregroundStyle(Color.sticksGreen))
                .font(SticksFont.display(56))

            VStack(spacing: 8) {
                Text("All your games. One app.")
                    .font(SticksFont.displayItalic(22))
                    .foregroundStyle(Color.sticksInk)

                Text("SCORING · GPS · LIVE ODDS · SIDE GAMES")
                    .font(SticksFont.label(10))
                    .kerning(1.6)
                    .foregroundStyle(Color.sticksFaint)
            }
            .multilineTextAlignment(.center)
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

    /// Slice 51: SecureField/TextField pair sharing `password`, with an
    /// eye toggle. Both carry `.password` content type so autofill works.
    private var passwordField: some View {
        HStack(spacing: 4) {
            Group {
                if showsPassword {
                    TextField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textContentType(.password)
            .focused($focusedField, equals: .password)
            .submitLabel(.go)
            .onSubmit {
                if canSubmit { submit() }
            }
            .font(SticksFont.sans(17))
            .foregroundStyle(Color.sticksInk)
            .padding(.leading, 16)

            Button {
                togglePasswordVisibility()
            } label: {
                Image(systemName: showsPassword ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sticksMuted)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityLabel(showsPassword ? "Hide password" : "Show password")
        }
        .sticksFieldChrome(isFocused: focusedField == .password)
    }

    private func togglePasswordVisibility() {
        let wasFocused = focusedField == .password
        showsPassword.toggle()
        if wasFocused {
            // The field view swaps out — restore focus on the next runloop.
            DispatchQueue.main.async {
                focusedField = .password
            }
        }
    }

    private var signInButton: some View {
        Button(action: submit) {
            ZStack {
                Text("Sign In")
                    .font(SticksFont.sans(17, weight: .semibold))
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .tint(Color.sticksCream)
                }
            }
            .foregroundStyle(Color.sticksCream.opacity(canSubmit || isSubmitting ? 1 : 0.75))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSubmit || isSubmitting ? Color.sticksGreen : Color.sticksGreen.opacity(0.55))
            .clipShape(.rect(cornerRadius: 14))
        }
        .disabled(!canSubmit)
        .animation(.easeInOut(duration: 0.15), value: isSubmitting)
        .animation(.easeInOut(duration: 0.15), value: canSubmit)
    }

    /// Slice 51: shown only when a biometric token exists on a
    /// biometrics-capable device.
    private var biometricButton: some View {
        Button(action: biometricSignIn) {
            HStack(spacing: 9) {
                Image(systemName: BiometricService.iconName)
                    .font(.system(size: 18, weight: .medium))

                Text("Sign in with \(BiometricService.displayName)")
                    .font(SticksFont.sans(16, weight: .semibold))
            }
            .foregroundStyle(Color.sticksGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.sticksCard)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.sticksGreen.opacity(0.45), lineWidth: 1.2)
            )
            .opacity(isBiometricSubmitting ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBiometricSubmitting || isSubmitting)
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

    /// Slice 51: prompt → token → /me → signed in. A cancel is silent
    /// (the form is the fallback); a rejected token clears the item and
    /// hides the button.
    private func biometricSignIn() {
        guard !isBiometricSubmitting, !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isBiometricSubmitting = true

        Task {
            defer { isBiometricSubmitting = false }
            do {
                try await session.signInWithBiometrics()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch BiometricService.BiometricError.cancelled {
                // User backed out — fall back to the form, no error.
            } catch let error as APIError {
                withAnimation {
                    errorMessage = error.message
                    canUseBiometricSignIn = BiometricService.isAvailable && session.isBiometricSignInEnabled
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } catch {
                withAnimation { errorMessage = "Something went wrong. Please try again." }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

// MARK: - Backdrop texture

/// Faint concentric course-contour rings — green hairlines at very low
/// opacity, slightly offset so they read organic rather than geometric.
private struct ContourBackdrop: View {
    var body: some View {
        ZStack {
            ForEach(0 ..< 4, id: \.self) { ring in
                Ellipse()
                    .stroke(Color.sticksGreen.opacity(0.05), lineWidth: 1)
                    .frame(
                        width: 190 + CGFloat(ring) * 96,
                        height: 152 + CGFloat(ring) * 78
                    )
                    .offset(
                        x: ring.isMultiple(of: 2) ? 16 : -12,
                        y: CGFloat(ring) * -7
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Field styling

private struct SticksFieldChrome: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
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
    /// Container chrome only — callers handle inner padding/fonts.
    func sticksFieldChrome(isFocused: Bool) -> some View {
        modifier(SticksFieldChrome(isFocused: isFocused))
    }

    /// Full single-field style: font + padding + chrome.
    func sticksFieldStyle(isFocused: Bool) -> some View {
        font(SticksFont.sans(17))
            .foregroundStyle(Color.sticksInk)
            .padding(.horizontal, 16)
            .sticksFieldChrome(isFocused: isFocused)
    }
}

#Preview {
    LoginView(session: SessionStore())
}
