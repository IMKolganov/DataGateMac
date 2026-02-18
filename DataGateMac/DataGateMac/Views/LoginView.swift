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
    @State private var statusText = "Not signed in."
    @State private var errorMessage: String?
    @State private var canceller: OAuthCanceller?

    var body: some View {
        VStack(spacing: 24) {
            Text("DataGate OpenVPN 3")
                .font(.title)
                .fontWeight(.semibold)
            Text("Sign in to continue")
                .foregroundStyle(.secondary)

            if let msg = errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Text(statusText)
                .foregroundStyle(.secondary)
                .font(.subheadline)

            HStack(spacing: 12) {
                Button("Sign in with Google") {
                    Task { await signInWithGoogle() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSigningIn)

                if isSigningIn {
                    Button("Cancel") {
                        canceller?.cancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        errorMessage = nil
        statusText = "Opening browser..."
        let oauthCanceller = OAuthCanceller()
        canceller = oauthCanceller

        do {
            let config = try AppConfig.load()
            let service = GoogleAuthService(config: config)
            statusText = "Waiting for Google sign-in… Close browser? Tap Cancel."

            let response = try await service.signInAndLogin(canceller: oauthCanceller)
            authState.completeLogin(response)
            statusText = "Signed in."
        } catch {
            if case GoogleAuthService.AuthError.cancelled? = error as? GoogleAuthService.AuthError {
                statusText = "Sign-in cancelled."
            } else {
                errorMessage = error.localizedDescription
                statusText = "Sign-in failed."
            }
        }

        canceller = nil
        isSigningIn = false
    }
}
