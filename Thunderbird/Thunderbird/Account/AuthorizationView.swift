// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import AuthenticationServices
import Autoconfiguration
import SwiftUI

struct AuthorizationView: View {
    let username: String
    let authenticationType: AuthenticationType

    init(_ authorization: Binding<Authorization>, error: Binding<Error?>, for username: String, authenticationType: AuthenticationType = .oAuth2, onAuthorized: @escaping () -> Void = {}) {
        self.username = username
        self.authenticationType = authenticationType
        self.onAuthorized = onAuthorized
        _authorization = authorization
        switch authorization.wrappedValue {
        case .basic(_, let password):
            self.password = password
        case .oauth(_, let token):
            self.token = token
        case .none:
            break
        }
        _error = error
    }

    @Binding private var authorization: Authorization
    @Binding private var error: Error?
    @State private var password: String = ""
    @State private var token: Token?

    /// Called once a credential has been established. `authorization` is a keychain-backed computed
    /// property, so writing it does not change any observable state; callers rely on this callback
    /// (not `.onChange(of:authorization)`) to know when to persist the account.
    private let onAuthorized: () -> Void

    // MARK: View
    var body: some View {
        switch authenticationType {
        case .password:
            SecureField("Password", text: $password)
                .onChange(of: password) {
                    authorization = .basic(user: username, password: password)
                    onAuthorized()
                }
        case .oAuth2:
            OAuthButton(username, token: $token, error: $error)
                .onChange(of: token, initial: true) {
                    if let token {
                        authorization = .oauth(user: username, token: token)
                        onAuthorized()
                    } else {
                        authorization = .none
                    }
                }
        case .none:
            EmptyView()
        }
    }
}

#Preview("Authorization View") {
    @Previewable @State var authorization: Authorization = .none
    @Previewable @State var error: Error?

    AuthorizationView($authorization, error: $error, for: "example@thunderbird.net")
        .padding()
}
