// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// OAuth2 credential: a short-lived access token plus an optional refresh token and expiry.
public struct Token: Codable, Equatable, Sendable, ExpressibleByStringLiteral {
    public var accessToken: String
    public var refreshToken: String?
    public var expiry: Date?
    /// Token endpoint to POST a refresh against; stored so the token can refresh itself.
    public var tokenURI: String?
    /// OAuth client ID to refresh as (not secret for native clients).
    public var clientID: String?

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiry: Date? = nil,
        tokenURI: String? = nil,
        clientID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiry = expiry
        self.tokenURI = tokenURI
        self.clientID = clientID
    }

    /// True when this token has everything needed to refresh itself.
    public var isRefreshable: Bool {
        refreshToken != nil && tokenURI != nil && clientID != nil
    }

    /// Convenience for an access-token-only credential (no refresh token or expiry).
    public static func bearer(_ accessToken: String) -> Token {
        Token(accessToken: accessToken)
    }

    // MARK: ExpressibleByStringLiteral
    public init(stringLiteral value: String) {
        self.init(accessToken: value)
    }

    /// The access token value — used as the SASL XOAUTH2 credential and the `Bearer` header.
    public var value: String { accessToken }

    /// True when an expiry is known and is at or within `leeway` of now. Tokens with no known
    /// expiry are treated as non-expiring (legacy credentials are never proactively refreshed).
    public func isExpired(leeway: TimeInterval = 60) -> Bool {
        guard let expiry else { return false }
        return expiry.timeIntervalSinceNow <= leeway
    }
}

extension Token {
    /// Serialized form for keychain storage (JSON). Falls back to the bare access token if encoding fails.
    var serialized: String {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else {
            return accessToken
        }
        return string
    }

    /// Reconstruct from the serialized keychain form; `nil` if the string is not serialized JSON
    /// (e.g. a legacy bare access token).
    init?(serialized: String) {
        guard let data = serialized.data(using: .utf8),
            let token = try? JSONDecoder().decode(Token.self, from: data)
        else {
            return nil
        }
        self = token
    }
}
