// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import AuthenticationServices
import Autoconfiguration
import SwiftUI

struct OAuthButton: View {
    let emailAddress: String

    init(_ emailAddress: String = "", token: Binding<Token?>, error: Binding<Error?>) {
        self.emailAddress = emailAddress
        _token = token
        _error = error
    }

    @Binding private var token: Token?
    @Binding private var error: Error?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var request: OAuth2.Request?
    @State private var isAuthenticating: Bool = false

    private func authenticate() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            error = nil
            guard let request else { return }
            // The web authentication callback has to match the request redirect URI.
            // Google iOS clients use the reversed client ID scheme, while other
            // providers may use the app's bundle scheme.
            guard let callbackScheme = URL(string: request.redirectURI)?.scheme else {
                throw URLError(.badURL)
            }
            // PKCE binds this authorization request to the token exchange (no client secret).
            let pkce = PKCE()
            let callback: URL = try await webAuthenticationSession.authenticate(
                using: request.authURL(hint: emailAddress, codeChallenge: pkce.challenge),
                callback: .customScheme(callbackScheme),
                additionalHeaderFields: [:])

            // Extract the authorization code from the callback URL and exchange it for a real access token.
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw URLError(.badServerResponse)
            }
            let response = try await URLSession.shared.token(request, code: code, codeVerifier: pkce.verifier)
            // Carry the refresh token, expiry, and refresh coordinates so the token can renew itself.
            token = Token(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                expiry: response.expiry(),
                tokenURI: request.tokenURI,
                clientID: request.clientID)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the web sheet; not an error worth surfacing.
            self.error = nil
        } catch {
            self.error = error
        }
    }

    private func configure() async {
        do {
            error = nil
            request = try await OAuth2.request(emailAddress)
        } catch {
            self.error = error
        }
    }

    // MARK: View
    var body: some View {
        Button(action: {
            Task {
                await authenticate()
            }
        }) {
            if isAuthenticating {
                ProgressView()
            } else {
                Text("account_oauth_sign_in_button")
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.accent)
        .disabled(request == nil || isAuthenticating)
        .task {
            await configure()
        }
    }
}

#Preview("OAuth Button") {
    @Previewable @State var token: Token?
    @Previewable @State var error: Error?

    OAuthButton("example@thunderbird.net", token: $token, error: $error)
}
