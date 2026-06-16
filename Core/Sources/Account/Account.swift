// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@_exported import Autoconfiguration
@_exported import EmailAddress
@_exported import IMAP
@_exported import JMAP
@_exported import MIME
@_exported import SMTP
import Foundation

public struct Account: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum EmailProtocol: String, CaseIterable, CustomStringConvertible, Identifiable {
        case imap = "IMAP/SMTP"
        case jmap = "JMAP"

        // MARK: CustomStringConvertible
        public var description: String { rawValue }

        // MARK: Identifiable
        public var id: String { rawValue }
    }

    public var name: String
    public var deletePolicy: DeletePolicy
    public var identities: [EmailAddress]
    public var servers: [Server]

    public var incomingServer: Server? { server(.jmap) ?? server(.imap) ?? nil }
    public var outgoingServer: Server? { server(.jmap) ?? server(.smtp) ?? nil }

    public var emailProtocol: EmailProtocol {
        servers.map { $0.serverProtocol }.contains(.jmap) ? .jmap : .imap
    }

    public func server(_ serverProtocol: ServerProtocol) -> Server? {
        servers.filter { $0.serverProtocol == serverProtocol }.first
    }

    /// Configure an `Account` using ``Autoconfiguration.EmailProvider``.
    public init(_ emailAddress: String, provider: EmailProvider? = nil) {
        self.init(EmailAddress(emailAddress), provider: provider)
    }

    /// Configure an `Account` using ``Autoconfiguration.EmailProvider``.
    public init(_ emailAddress: EmailAddress, provider: EmailProvider? = nil) {
        self.init(
            name: emailAddress.value,
            identities: [
                emailAddress
            ],
            servers: (provider?.servers ?? []).compactMap { Server($0) }
        )
    }

    /// Configure an `Account` using memberwise initializer.
    public init(
        name: String,
        deletePolicy: DeletePolicy = .never,
        identities: [EmailAddress] = [],
        servers: [Server] = [],
        id: UUID = UUID()
    ) {
        self.name = name
        self.deletePolicy = deletePolicy
        self.identities = identities
        self.servers = servers
        self.id = id
    }

    // MARK: Identifiable
    public let id: UUID
}

extension Account {

    /// Autoconfigure a new `Account`.
    public static func autoconfig(_ emailAddress: String, isJMAPAvailable: Bool = false) async throws -> Self {
        do {
            if isJMAPAvailable, try emailAddress.host == "fastmail.com" {
                return Account(
                    name: emailAddress,
                    identities: [
                        EmailAddress(emailAddress)
                    ],
                    servers: [
                        Server(
                            .jmap,
                            connectionSecurity: .tls,
                            authenticationType: .password,
                            username: emailAddress,
                            hostname: "api.fastmail.com"
                        )
                    ]
                )
            } else {
                let config: ClientConfig = try await URLSession.shared.autoconfig(emailAddress).config
                return Account(emailAddress, provider: config.emailProvider)
            }
        } catch {
            throw AccountError.autoconfig(error)
        }
    }
}

extension Account {
    /// Refresh the incoming server's OAuth access token if it has expired, updating the keychain.
    ///
    /// No-op for password accounts, non-expiring/legacy tokens, or tokens missing refresh data.
    func refreshTokenIfNeeded() async throws {
        try await refreshToken(force: false)
    }

    /// Refresh the incoming server's OAuth access token, updating the keychain and dropping any
    /// cached client (which holds the stale token). When `force` is false, refreshes only if the
    /// token is at/near expiry. Returns `true` if a refresh was performed.
    @discardableResult
    func refreshToken(force: Bool) async throws -> Bool {
        try await refreshToken(for: incomingServer, force: force)
    }

    /// Refresh the outgoing (SMTP) server's OAuth access token before sending.
    ///
    /// SMTP stores its credential in a separate keychain entry from IMAP, so the outgoing token is
    /// refreshed independently of ``refreshToken(force:)``. No-op for password/legacy accounts.
    @discardableResult
    func refreshOutgoingTokenIfNeeded(force: Bool = false) async throws -> Bool {
        try await refreshToken(for: outgoingServer, force: force)
    }

    /// Refresh `server`'s OAuth access token, persisting the result to its keychain entry. When the
    /// refreshed server is the incoming server, also drops the cached IMAP client (which holds the
    /// stale token). Returns `true` if a refresh was performed.
    @discardableResult
    private func refreshToken(for server: Server?, force: Bool) async throws -> Bool {
        guard var server: Server = server,
            case .oauth(let user, let token) = server.authorization,
            force || token.isExpired(), token.isRefreshable,
            let refreshToken: String = token.refreshToken,
            let tokenURI: String = token.tokenURI,
            let clientID: String = token.clientID
        else {
            return false
        }
        let response: OAuth2.TokenResponse = try await URLSession.shared.refreshToken(
            tokenURI: tokenURI, clientID: clientID, refreshToken: refreshToken)
        let refreshed: Token = Token(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,  // Google omits refresh_token on refresh
            expiry: response.expiry(),
            tokenURI: tokenURI,
            clientID: clientID)
        server.authorization = .oauth(user: user, token: refreshed)  // Persists to keychain
        if server.id == incomingServer?.id {
            try? (Self.clients[id] as? IMAPClient)?.disconnect()  // Tear down the stale connection
            Self.clients[id] = nil  // Rebuild with the new token on next access
        }
        return true
    }

    var imapClient: IMAPClient {
        get async throws {
            try await refreshTokenIfNeeded()
            do {
                return try await connectedIMAPClient()
            } catch let error as IMAPError {
                // A non-expired token can still be rejected (revocation, clock skew). Force one
                // refresh and retry; if there's nothing to refresh, surface the original error.
                guard case .authenticationFailed = error, try await refreshToken(force: true) else {
                    throw error
                }
                return try await connectedIMAPClient()
            }
        }
    }

    /// Build a fresh, connected, authenticated IMAP client that is **not** shared in the pool.
    ///
    /// Long-lived work (e.g. IMAP IDLE in ``MessageManager/monitorInbox()``) needs its own
    /// connection: the pooled ``imapClient`` is reused by ordinary fetches, and a client parked in
    /// IDLE can't service them. Refreshes the incoming token first, like ``imapClient``.
    func newIMAPClient() async throws -> IMAPClient {
        try await refreshTokenIfNeeded()
        guard let incomingServer else {
            throw IMAPError.serverProtocolMismatch
        }
        let client: IMAPClient = IMAPClient(try IMAP.Server(incomingServer))
        try await client.connect()
        try await client.login()
        return client
    }

    private func connectedIMAPClient() async throws -> IMAPClient {
        if let client: IMAPClient = Self.clients[id] as? IMAPClient {
            // IMAP Client already exists for account ID; reconnect and return
            if !client.isConnected {
                try await client.connect()
                try await client.login()
            }
            return client
        } else {
            // No client exists for account ID; make a new one, connect and return
            guard let incomingServer else {
                throw IMAPError.serverProtocolMismatch
            }
            let client: IMAPClient = IMAPClient(try IMAP.Server(incomingServer))
            try await client.connect()
            try await client.login()
            Self.clients[id] = client  // Donate to shared pool
            return client
        }
    }

    var jmapClient: JMAPClient {
        get async throws {
            if let client: JMAPClient = Self.clients[id] as? JMAPClient, client.session != nil {
                // JMAP Client already exists for account ID; return
                return client
            } else {
                // No client exists for account ID; start a new session and return
                guard let server: Server = servers.first else {
                    throw JMAPError.serverProtocolMismatch
                }
                let client: JMAPClient = try await .session(try JMAP.Server(server))
                guard client.session != nil else {
                    throw JMAPError.sessionNotFound
                }
                return client
            }
        }
    }

    // Share existing IMAP and JMAP clients associated with account
    nonisolated(unsafe) private static var clients: [UUID: Any] = [:]
}
