//
//  LoginView.swift
//  DataGateMac
//
//  Shown when not authorized. After successful login, authState.completeLogin() → main.
//

import AppKit
import SwiftUI

private struct TotpLoginChallenge {
    let loginChallengeId: String
    let displayName: String
}

struct LoginView: View {
    @ObservedObject var authState: AuthStateStore
    @State private var isSigningIn = false
    @State private var statusText = L10n.tr("login_status_not_signed_in", "Not signed in.")
    @State private var errorMessage: String?
    @State private var canceller: OAuthCanceller?
    @State private var signInStartedAt: Date?
    @State private var elapsedSeconds = 0
    @State private var totpChallenge: TotpLoginChallenge?
    @State private var totpCode = ""
    @State private var isVerifyingTotp = false
    @State private var totpChallengeExpired = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
            Text(L10n.tr("login_title", "DataGate"))
                .font(.title)
                .fontWeight(.semibold)
            Text(totpChallenge == nil
                 ? L10n.tr("login_subtitle", "Sign in to continue")
                 : L10n.tr("login_totp_title", "Two-factor authentication"))
                .foregroundStyle(.secondary)

            if let msg = errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Text(statusText)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if let challenge = totpChallenge {
                totpStep(challenge)
            } else {
                googleSignInStep
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

    @ViewBuilder
    private var googleSignInStep: some View {
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
            Button {
                Task { await signInWithGoogle() }
            } label: {
                Label(L10n.tr("login_sign_google", "Sign in with Google"), systemImage: "person.crop.circle.badge.checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)

            if isSigningIn {
                Button {
                    canceller?.cancel()
                } label: {
                    Label(L10n.tr("login_cancel", "Cancel"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private func totpStep(_ challenge: TotpLoginChallenge) -> some View {
        Text(totpLead(for: challenge.displayName))
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

        TextField(L10n.tr("login_totp_placeholder", "000000"), text: $totpCode)
            .textFieldStyle(.roundedBorder)
            .font(.system(.title2, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 160)
            .disabled(isVerifyingTotp || totpChallengeExpired)
            .onChange(of: totpCode) { _, newValue in
                let normalized = TotpCode.normalize(newValue)
                if normalized != newValue {
                    totpCode = normalized
                }
            }

        HStack(spacing: 12) {
            Button {
                Task { await verifyTotp(challenge) }
            } label: {
                Label(
                    isVerifyingTotp
                        ? L10n.tr("login_totp_verifying", "Verifying…")
                        : L10n.tr("login_totp_verify", "Verify and sign in"),
                    systemImage: "checkmark.shield"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(totpCode.count != 6 || isVerifyingTotp || totpChallengeExpired)

            Button {
                resetTotpChallenge()
            } label: {
                Label(
                    totpChallengeExpired
                        ? L10n.tr("login_totp_again", "Sign in again")
                        : L10n.tr("login_totp_back", "Back to sign in"),
                    systemImage: totpChallengeExpired ? "arrow.counterclockwise" : "chevron.left"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isVerifyingTotp)
        }
    }

    private func totpLead(for displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return L10n.tr("login_totp_lead", "Enter the 6-digit code from your authenticator app to finish signing in.")
        }
        return L10n.trFormat(
            "login_totp_lead_named_fmt",
            "Signed in as %@. Enter the 6-digit code from your authenticator app to finish signing in.",
            name
        )
    }

    private func refreshStaticLocalizedStrings() {
        if totpChallenge != nil {
            return
        }
        if !isSigningIn, errorMessage == nil {
            statusText = L10n.tr("login_status_not_signed_in", "Not signed in.")
        }
    }

    private func resetTotpChallenge() {
        totpChallenge = nil
        totpCode = ""
        isVerifyingTotp = false
        totpChallengeExpired = false
        errorMessage = nil
        statusText = L10n.tr("login_status_not_signed_in", "Not signed in.")
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        errorMessage = nil
        totpChallenge = nil
        totpCode = ""
        totpChallengeExpired = false
        statusText = L10n.tr("login_status_opening_browser", "Opening browser…")
        signInStartedAt = Date()
        elapsedSeconds = 0
        let oauthCanceller = OAuthCanceller()
        canceller = oauthCanceller

        do {
            let config = try AppConfig.load()
            let service = GoogleAuthService(config: config)
            statusText = L10n.tr("login_status_starting", "Starting sign-in…")

            let outcome = try await service.signInAndLogin(
                canceller: oauthCanceller,
                onProgress: { progress in
                    Task { @MainActor in
                        statusText = progress
                    }
                }
            )
            switch outcome {
            case .signedIn(let response):
                authState.completeLogin(response)
                statusText = L10n.tr("login_status_signed_in", "Signed in.")
            case .totpRequired(let challengeId, let displayName):
                totpChallenge = TotpLoginChallenge(loginChallengeId: challengeId, displayName: displayName)
                statusText = L10n.tr("login_totp_status", "Authenticator code required.")
                applyClipboardTotpIfEmpty()
            }
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

    private func verifyTotp(_ challenge: TotpLoginChallenge) async {
        guard totpCode.count == 6, !isVerifyingTotp, !totpChallengeExpired else { return }
        isVerifyingTotp = true
        errorMessage = nil
        statusText = L10n.tr("login_totp_verifying", "Verifying…")
        do {
            let config = try AppConfig.load()
            let service = GoogleAuthService(config: config)
            let response = try await service.verifyTotpLogin(loginChallengeId: challenge.loginChallengeId, code: totpCode)
            authState.completeLogin(response)
            totpChallenge = nil
            totpCode = ""
            statusText = L10n.tr("login_status_signed_in", "Signed in.")
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            if TotpCode.isChallengeExpiredMessage(message) {
                totpChallengeExpired = true
                statusText = L10n.tr("login_totp_expired", "This verification step expired. Sign in again.")
            } else {
                statusText = L10n.tr("login_status_failed", "Sign-in failed.")
            }
        }
        isVerifyingTotp = false
    }

    private func applyClipboardTotpIfEmpty() {
        guard totpCode.isEmpty else { return }
        guard let raw = NSPasteboard.general.string(forType: .string),
              let six = TotpCode.extractSixDigits(raw) else { return }
        totpCode = six
    }
}
