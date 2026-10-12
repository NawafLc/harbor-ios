import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 60)

                VStack(spacing: 12) {
                    Image(systemName: "sailboat.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.accent)
                    Text("Harbor")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("Sign in with the Stremio account you use in Harbor on your PC. Your addons, library and Continue Watching come with you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(signIn)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: signIn) {
                        HStack {
                            if busy { ProgressView().tint(.black) }
                            Text(busy ? "Signing in…" : "Sign in")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                    }
                    .disabled(busy || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
                }
                .padding(.horizontal, 24)

                Text("Your password is only sent to Stremio (api.strem.io).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
    }

    private func signIn() {
        guard !busy, !email.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                try await app.login(email: email, password: password)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
