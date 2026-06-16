// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CryptoKit
import Foundation

/// Proof Key for Code Exchange ([RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)) pair.
///
/// Native OAuth clients (like Google iOS clients) have no client secret, so PKCE binds the
/// authorization request to the token exchange. Send `challenge` on the authorization URL and the
/// matching `verifier` on the token exchange.
struct PKCE {
    /// High-entropy random string sent on the token exchange.
    let verifier: String
    /// `base64url(SHA256(verifier))` sent on the authorization URL with `code_challenge_method=S256`.
    let challenge: String

    init() {
        var bytes: [UInt8] = .init(repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier: String = Data(bytes).base64URLEncodedString()
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

private extension Data {
    /// Base64URL encoding without padding, per RFC 7636.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
