// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

/// ``SMTPClient`` connects to `Server`.
public struct Server: CustomStringConvertible, Equatable, Sendable {
    /// How the client authenticates: a password (`AUTH LOGIN`) or an OAuth2 bearer token
    /// (`AUTH XOAUTH2`). Mirrors `IMAP.Server.Authentication`.
    public enum Authentication: Sendable {
        case password
        case oAuth2
    }

    public let connectionSecurity: ConnectionSecurity
    public let hostname: String
    public let username: String
    /// Password for `.password` auth, or the OAuth2 bearer access token for `.oAuth2` auth.
    public let password: String
    public let port: Int
    public let authentication: Authentication

    public init(
        _ connectionSecurity: ConnectionSecurity = .startTLS,
        hostname: String,
        username: String,
        password: String,
        port: Int = 587,
        authentication: Authentication = .password
    ) {
        self.connectionSecurity = connectionSecurity
        self.hostname = hostname
        self.username = username
        self.password = password
        self.port = port
        self.authentication = authentication
    }

    // MARK: CustomStringConvertible
    public var description: String { "\(hostname):\(port)" }
}
