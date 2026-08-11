import SwiftUI

struct LoginView: View {
    let appModel: AppModel

    @Environment(\.colorScheme) private var scheme
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.top, Theme.Space.roomy + 4)

            VStack(spacing: 4) {
                Text("Sign in to Dreo")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Use the email and password from your Dreo account.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Space.roomy)
            .padding(.horizontal, Theme.Space.loose + 2)

            VStack(spacing: Theme.Space.tight + 2) {
                field(icon: "envelope", placeholder: "Email", text: $email, isSecure: false)
                field(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
            }
            .padding(.top, Theme.Space.roomy)
            .padding(.horizontal, Theme.Space.loose + 2)

            if let errorMessage = appModel.errorMessage {
                InlineErrorBanner(message: errorMessage)
                    .padding(.horizontal, Theme.Space.loose + 2)
                    .padding(.top, Theme.Space.snug)
            }

            Spacer(minLength: Theme.Space.roomy)

            VStack(spacing: Theme.Space.tight) {
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    } else {
                        Text("Sign In")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.loose + 2)
            .padding(.bottom, Theme.Space.snug)
        }
        .frame(width: Theme.Metric.popoverWidth + 16)
        .background(background)
    }

    /// Lighter gradient than the welcome screen, but still atmospheric: a
    /// hint of the accent at the top that fades out so the form fields
    /// remain the focal point.
    private var background: some View {
        LinearGradient(
            colors: [
                Theme.accent.opacity(0.16),
                Theme.accent.opacity(0.06),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    /// A smaller hero than the welcome screen: a single disc with the
    /// accent glyph. Fully static - the form is the focal point.
    private var hero: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.30), lineWidth: 1)
                .frame(width: 96, height: 96)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.32), Theme.accent.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.accent)
        }
        .frame(height: 96)
    }

    @ViewBuilder
    private func field(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                .fill(Theme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.controlRadius, style: .continuous)
                .stroke(Theme.hairline(scheme), lineWidth: 1)
        )
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            await appModel.login(email: email, password: password)
            isSubmitting = false
        }
    }
}
