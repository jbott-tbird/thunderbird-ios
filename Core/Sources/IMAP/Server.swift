// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

/// ``IMAPClient`` connects to `Server`.
public struct Server: CustomStringConvertible, Equatable, Sendable {
    /// How `login` authenticates: a password (`LOGIN`) or an OAuth2 bearer token (`AUTHENTICATE XOAUTH2`).
    public enum Authentication: Sendable {
        case password
        case oAuth2
    }

    public let connectionSecurity: ConnectionSecurity
    public let hostname: String
    public let username: String?
    public let password: String?
    public let port: Int
    public let authentication: Authentication

    /// `Server` can be configured with or without basic auth credentials.
    ///
    /// User name and password can be provided at `login`, or another mechanism can be used to `authenticate`.
    /// For `.oAuth2`, the OAuth2 access token is passed as `password`.
    public init(
        _ connectionSecurity: ConnectionSecurity = .tls,
        hostname: String,
        username: String? = nil,
        password: String? = nil,
        port: Int = 993,
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
