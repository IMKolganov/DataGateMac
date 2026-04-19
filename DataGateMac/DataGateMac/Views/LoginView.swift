//
//  LoginView.swift
//  DataGateMac
//
//  Shown when not authorized. After successful login, authState.completeLogin() → main.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var authState: AuthStateStore
    @State private var isSigningIn = false
    @State private var statusText = L10n.tr("login_status_not_signed_in", "Not signed in.")
    @State private var errorMessage: String?
    @State private var canceller: OAuthCanceller?
    @State private var signInStartedAt: Date?
    @State private var elapsedSeconds = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
            Text(L10n.tr("login_title", "DataGate"))
                .font(.title)
                .fontWeight(.semibold)
            Text(L10n.tr("login_subtitle", "Sign in to continue"))
                .foregroundStyle(.secondary)

            if let msg = errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Text(statusText)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            if isSigningIn, let start = signInStartedAt {
                Text(String(format: L10n.tr("login_elapsed_fmt", "Elapsed: %d s"), locale: L10n.activeLocaleForFormatting(), elapsedSeconds))
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .task(id: start) {
                        while isSigningIn {
                            elapsedSeconds = Int(Date().timeIntervalSince(start))
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
            }

            HStack(spacing: 12) {
                Button(L10n.tr("login_sign_google", "Sign in with Google")) {
                    Task { await signInWithGoogle() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSigningIn)

                if isSigningIn {
                    Button(L10n.tr("login_cancel", "Cancel")) {
                        canceller?.cancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

            VStack(alignment: .trailing, spacing: 4) {
                Text(L10n.tr("settings_language", "Language"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AppLanguagePicker()
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in
            refreshStaticLocalizedStrings()
        }
    }

    private func refreshStaticLocalizedStrings() {
        if !isSigningIn, errorMessage == nil {
            statusText = L10n.tr("login_status_not_signed_in", "Not signed in.")
        }
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        errorMessage = nil
        statusText = L10n.tr("login_status_opening_browser", "Opening browser…")
        signInStartedAt = Date()
        elapsedSeconds = 0
        let oauthCanceller = OAuthCanceller()
        canceller = oauthCanceller

        do {
            let config = try AppConfig.load()
            let service = GoogleAuthService(config: config)
            statusText = L10n.tr("login_status_starting", "Starting sign-in…")

            let response = try await service.signInAndLogin(
                canceller: oauthCanceller,
                onProgress: { progress in
                    Task { @MainActor in
                        statusText = progress
                    }
                }
            )
            authState.completeLogin(response)
            statusText = L10n.tr("login_status_signed_in", "Signed in.")
        } catch {
            if case GoogleAuthService.AuthError.cancelled? = error as? GoogleAuthService.AuthError {
                statusText = L10n.tr("login_status_cancelled", "Sign-in cancelled.")
            } else {
                errorMessage = error.localizedDescription
                statusText = L10n.tr("login_status_failed", "Sign-in failed.")
            }
        }

        canceller = nil
        isSigningIn = false
        signInStartedAt = nil
    }
}
