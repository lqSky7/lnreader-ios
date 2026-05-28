import SwiftUI

struct AuthView: View {
    @Environment(SyncManager.self) private var syncManager
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AuthMode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var identifier = ""
    @State private var password = ""
    @State private var resetToken = ""
    @State private var backendURL = ""

    var body: some View {
        @Bindable var syncManager = syncManager

        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            
                            Picker("Mode", selection: $mode) {
                                ForEach(AuthMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.vertical, 4)
                            
                            formFields
                            
                            if let error = syncManager.lastError {
                                Label(error, systemImage: "exclamationmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            } else if let message = syncManager.lastMessage {
                                Label(message, systemImage: "checkmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 110) // Space for floating button
                    }
                    
                    // Floating Action Button
                    VStack {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack(spacing: 12) {
                                if syncManager.isWorking {
                                    ProgressView()
                                }
                                Text(mode.actionTitle)
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                        }
                        .disabled(syncManager.isWorking || !canSubmit)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .opacity(canSubmit ? 1.0 : 0.5)
                        .animation(.smooth, value: canSubmit)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 24)
                    }
                    .background(
                        LinearGradient(
                            colors: [.clear, Color(.systemBackground).opacity(0.8), Color(.systemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea()
                    )
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                backendURL = syncManager.backendURL
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Sync your reader")
                .font(.title2.weight(.bold))

            Text("Use one account for profile, sources, and non-local library entries.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var formFields: some View {
        VStack(spacing: 0) {
            if mode == .register {
                customField(placeholder: "Username", text: $username, icon: "person")
                Divider().padding(.horizontal, 16)
            }
            
            if mode == .login {
                customField(placeholder: "Email or username", text: $identifier, icon: "envelope")
                Divider().padding(.horizontal, 16)
            } else if mode == .register || mode == .forgot {
                customField(placeholder: "Email", text: $email, icon: "envelope", keyboardType: .emailAddress)
                Divider().padding(.horizontal, 16)
            }
            
            if mode == .reset {
                customField(placeholder: "Reset token", text: $resetToken, icon: "key")
                Divider().padding(.horizontal, 16)
            }
            
            if mode != .forgot {
                customSecureField(placeholder: "Password", text: $password, icon: "lock")
                Divider().padding(.horizontal, 16)
            }
            
            customField(placeholder: "Backend URL", text: $backendURL, icon: "link", keyboardType: .URL)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
    
    @ViewBuilder
    private func customField(placeholder: String, text: Binding<String>, icon: String, keyboardType: UIKeyboardType = .default) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.secondary.opacity(0.5)))
                .font(.system(size: 18, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func customSecureField(placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.secondary.opacity(0.5)))
                .font(.system(size: 18, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
    }

    private var canSubmit: Bool {
        switch mode {
        case .login:
            !identifier.isEmpty && password.count >= 8 && !backendURL.isEmpty
        case .register:
            username.count >= 3 && email.contains("@") && password.count >= 8 && !backendURL.isEmpty
        case .forgot:
            email.contains("@") && !backendURL.isEmpty
        case .reset:
            !resetToken.isEmpty && password.count >= 8 && !backendURL.isEmpty
        }
    }

    private func submit() async {
        syncManager.updateBackendURL(backendURL)
        switch mode {
        case .login:
            await syncManager.signIn(identifier: identifier, password: password)
        case .register:
            await syncManager.register(username: username, email: email, password: password)
        case .forgot:
            await syncManager.requestPasswordReset(email: email)
        case .reset:
            await syncManager.resetPassword(token: resetToken, newPassword: password)
        }

        if syncManager.currentUser != nil {
            dismiss()
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case register
    case forgot
    case reset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login: "Login"
        case .register: "Register"
        case .forgot: "Forgot"
        case .reset: "Reset"
        }
    }

    var actionTitle: String {
        switch self {
        case .login: "Login"
        case .register: "Create Account"
        case .forgot: "Send Reset Link"
        case .reset: "Reset Password"
        }
    }
}
