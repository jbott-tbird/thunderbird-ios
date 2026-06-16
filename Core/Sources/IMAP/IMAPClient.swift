// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import MIME
import NIO
import NIOIMAP
import NIOSSL
import OSLog

/// Configure `IMAPClient` with a single ``Server``.
public class IMAPClient {
    public let server: Server

    public private(set) var capabilities: Set<Capability> = []
    public var isConnected: Bool { channel != nil && channel!.isActive }
    public var isIdling: Bool { idleHandler != nil }

    public func isSupported(_ capability: Capability) throws {
        guard capabilities.contains(capability) else {
            throw IMAPError.capabilityNotSupported(capability)
        }
    }

    /// Bootstrap NIO channel, connect to the configured ``Server``.
    public func connect() async throws {
        logger?.info("Connecting to \(self.server)…")
        resetInactiveChannel()
        guard channel == nil else {
            logger?.error("\(IMAPError.alreadyConnected)")
            throw IMAPError.alreadyConnected
        }
        do {
            self.channel =
                try await ClientBootstrap
                .bootstrap(server: server, logger: logger, group: group)
                .connect(host: server.hostname, port: server.port)
                .get()
            logger?.info("Connected to \(self.server)")
            try await refreshCapabilities()
        } catch {
            logger?.error("\(error)")
            throw IMAPError(error)
        }
    }

    /// Disconnect NIO channel from configured ``Server``; reset to ready for new connection.
    public func disconnect() throws {
        guard let channel else {
            logger?.error("\(IMAPError.notConnected)")
            throw IMAPError.notConnected
        }
        channel.close(promise: nil)
        self.channel = nil
    }

    /// Log in to connected IMAP server using configured ``Server`` credentials.
    ///
    /// Uses SASL XOAUTH2 when the server is configured for `.oAuth2`, otherwise plain `LOGIN`.
    public func login() async throws {
        switch server.authentication {
        case .oAuth2:
            try await authenticateXOAuth2(username: server.username ?? "", token: server.password ?? "")
        case .password:
            try await login(username: server.username ?? "", password: server.password ?? "")
        }
    }

    /// Authenticate to the connected IMAP ``Server`` using a SASL XOAUTH2 bearer token.
    public func authenticateXOAuth2(username: String, token: String) async throws {
        logger?.info("Authenticating \(username) via XOAUTH2…")
        let capabilities: [Capability] = try await execute(command: AuthenticateCommand(username: username, token: token))
        if !capabilities.isEmpty {
            // IMAP servers can return additional capabilities after authentication
            logger?.info("Merging capabilities…")
            for capability in capabilities {
                self.capabilities.insert(capability)
            }
            logger?.info("Capabilities: \(self.capabilities)")
        }
    }

    /// Log in to connected IMAP ``Server`` using locally specified credentials.
    public func login(username: String, password: String) async throws {
        logger?.info("Logging in \(username)…")
        let capabilities: [Capability] = try await execute(command: LoginCommand(username: username, password: password))
        if !capabilities.isEmpty {
            // IMAP servers can return additional capabilities after login
            logger?.info("Merging capabilities…")
            for capability in capabilities {
                self.capabilities.insert(capability)
            }
            logger?.info("Capabilities: \(self.capabilities)")
        }
    }

    /// Log out from connected IMAP ``Server``; leave active NIO channel connection intact.
    public func logout() async throws {
        logger?.info("Logging out…")
        try await execute(command: VoidCommand(.logout))
    }

    /// Fetch namespaces available to authenticated user.`
    public func namespace() async throws -> [Namespace] {
        logger?.info("Fetching namespace…")
        let namespace: [Namespace] = try await execute(command: NamespaceCommand())
        logger?.info("Namespaces: \(namespace)")
        return namespace
    }

    /// Start idle on connected ``Server``; handle ``IdleEvent`` pushes.
    @discardableResult public func idle() async throws -> AsyncStream<IdleEvent> {
        try isSupported(.idle)
        logger?.info("Idle start…")
        return try await idleStart()
    }

    /// Stop idling on connected ``Server``.
    public func done() async throws {
        logger?.info("Idle done…")
        try await idleDone()
    }

    /// Poll ``Server`` for ``IdleEvent`` when not idling.
    public func noop() async throws -> [IdleEvent] {
        logger?.info("Noop…")
        guard !isIdling else {
            // NIOIMAP automatically (1) keeps idle alive and (2) streams idle events
            // Manual `noop` polling is blocked by NIOIMAP during idle
            throw IMAPError.commandNotSupported("Noop during idle")
        }
        return try await execute(command: NoopCommand())
    }

    /// List all mailboxes on logged-in IMAP ``Server``.
    public func list(wildcard: Character = .wildcard) async throws -> [(Mailbox, Mailbox.Status?)] {
        logger?.info("Listing mailboxes…")
        return try await execute(command: ListCommand(wildcard: wildcard))
    }

    /// Select current working mailbox in read/write mode.
    @discardableResult public func select(mailbox: Mailbox) async throws -> Mailbox.Status {
        logger?.info("Selecting mailbox \(mailbox.path.name)…")
        return try await execute(command: SelectCommand(mailbox.path.name))
    }

    /// Select a working mailbox in read-only mode.
    public func examine(mailbox: Mailbox) async throws -> Mailbox.Status {
        logger?.info("Examining mailbox \(mailbox.path.name)…")
        return try await execute(command: ExamineCommand(mailbox.path.name))
    }

    /// Fetch the current status for a mailbox.
    public func status(mailbox: Mailbox) async throws -> Mailbox.Status {
        logger?.info("Refreshing mailbox \(mailbox.path.name) status…")
        return try await execute(command: StatusCommand(mailbox.path.name, attributes: .standard + .extended(capabilities)))
    }

    /// Mark a message as read by adding the `\Seen` flag, by ``UID``, in the selected mailbox.
    public func markSeen(uid: UID) async throws {
        logger?.info("Marking UID \(uid) as seen…")
        try await execute(command: UIDStoreCommand(UIDSet(uid), data: .flags(.add(silent: true, list: [.seen]))))
    }

    /// Add or remove a single ``Flag`` (e.g. `.seen`, `.flagged`) on a message by ``UID`` in the
    /// selected mailbox — the building block for two-way flag reconciliation.
    public func store(uid: UID, flag: Flag, enabled: Bool) async throws {
        logger?.info("\(enabled ? "Adding" : "Removing") flag \(flag) on UID \(uid)…")
        let data: StoreData = enabled
            ? .flags(.add(silent: true, list: [flag]))
            : .flags(.remove(silent: true, list: [flag]))
        try await execute(command: UIDStoreCommand(UIDSet(uid), data: data))
    }

    /// Expunge messages flagged as deleted in current working mailbox.
    public func expunge() async throws {
        logger?.info("Expunging selected mailbox…")
        try await execute(command: VoidCommand(.expunge))
    }

    /// Unselect current working mailbox; don't expunge messages flagged as deleted.
    public func unselect() async throws {
        logger?.info("Unselecting mailbox…")
        try await execute(command: VoidCommand(.unselect))
    }

    /// Create a new mailbox.
    public func create(mailbox name: MailboxName) async throws {
        logger?.info("Creating \"\(name)\" mailbox…")
        try await execute(command: CreateCommand(name))
    }

    /// Rename an existing mailbox.
    public func rename(mailbox name: MailboxName, to targetName: MailboxName) async throws {
        logger?.info("Renaming \"\(name)\" mailbox to \"\(targetName)\"…")
        try await execute(command: RenameCommand(name, to: targetName))
    }

    /// Delete an existing mailbox.
    public func delete(mailbox name: MailboxName) async throws {
        logger?.info("Deleting \"\(name)\" mailbox…")
        try await execute(command: DeleteCommand(name))
    }

    /// Subscribe to an existing mailbox.
    public func subscribe(mailbox name: MailboxName) async throws {
        logger?.info("Subscribing \"\(name)\" mailbox…")
        try await execute(command: SubscribeCommand(name))
    }

    /// Unsubscribe from an existing mailbox.
    public func unsubscribe(mailbox name: MailboxName) async throws {
        logger?.info("Unsubscribing \"\(name)\" mailbox…")
        try await execute(command: UnsubscribeCommand(name))
    }

    /// Expunge and unselect current working mailbox.
    public func close() async throws {
        logger?.info("Closing selected mailbox…")
        try await execute(command: VoidCommand(.close))
    }

    /// Fetch a set of messages by mailbox ``SequenceNumber``; fetches all headers and omits message body by default.
    public func fetch(_ set: SequenceSet = .all, attributes: [FetchAttribute] = .header) async throws -> MessageSet {
        logger?.info("Fetching messages by mailbox sequence number…")
        return try await execute(command: FetchCommand(set, attributes: attributes.filtered(capabilities)))
    }

    /// Fetch a specific message by ``SequenceNumber``; fetches complete message by default.
    public func fetch(_ number: SequenceNumber, attributes: [FetchAttribute] = .complete) async throws -> Message {
        logger?.info("Fetching message \(number)…")
        let messages: MessageSet = try await fetch(SequenceSet(number), attributes: attributes)
        guard let message: Message = messages.first?.value else {
            throw IMAPError.commandFailed("Message \(number) not found")
        }
        return message
    }

    /// Fetch a set of messages by ``UID``; fetches all headers and omits message body by default.
    public func fetch(uid set: UIDSet, attributes: [FetchAttribute] = .header) async throws -> MessageSet {
        logger?.info("Fetching messages by UID…")
        return try await execute(command: UIDFetchCommand(set, attributes: attributes.filtered(capabilities)))
    }

    /// Fetch the raw, still-transfer-encoded bytes of a single body section by ``UID``
    /// (e.g. `[2]` → `BODY[2]`, `[2, 1]` → `BODY[2.1]`). Returns `nil` if the server omits the
    /// section. Decode the result with `Data.transferDecoded(_:)`.
    public func fetch(uid: UID, section: [Int]) async throws -> Data? {
        logger?.info("Fetching message UID \(uid) body section \(section)…")
        let specifier = SectionSpecifier(part: SectionSpecifier.Part(section))
        let message: Message = try await fetch(uid: uid, attributes: [.bodySection(peek: true, specifier, nil)])
        return message.bodyPart(section)
    }

    /// Fetch a specific message by ``UID``; fetches complete message by default.
    public func fetch(uid: UID, attributes: [FetchAttribute] = .complete) async throws -> Message {
        logger?.info("Fetching message UID \(uid)…")
        let messages: MessageSet = try await fetch(uid: UIDSet(uid), attributes: attributes)
        guard let message: Message = messages.first?.value else {
            throw IMAPError.commandFailed("Message UID \(uid) not found")
        }
        return message
    }

    public init(
        _ server: Server,
        logger: Logger? = Logger(subsystem: "net.thunderbird", category: "IMAP")
    ) {
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.server = server
        self.logger = logger
    }

    // Run IMAP command through NIO `IMAPClientHandler` in channel and handle results
    private func execute<T: IMAPCommand>(command: T) async throws -> T.Result {
        let logger: Logger? = logger  // Copy logger instead of capturing
        logger?.debug("Executing \(command)…")
        guard let channel, channel.isActive else {
            logger?.error("\(IMAPError.notConnected)")
            throw IMAPError.notConnected
        }
        let promise: EventLoopPromise<T.Result> = channel.eventLoop.makePromise(of: T.Result.self)
        let tag: String = UUID().uuidString(1)  // Hold onto specific auto-generated tag
        let handler: T.Handler = T.Handler(tag: tag, promise: promise)
        let seconds: Int64 = max(command.timeout, 1)
        let task: Scheduled = group.next().scheduleTask(in: .seconds(seconds)) {
            let error: IMAPError = .timedOut(seconds: seconds)
            logger?.error("\(error)")
            promise.fail(error)
        }
        defer {
            channel.pipeline.removeHandler(handler, promise: nil)
            task.cancel()
        }
        do {
            try await channel.pipeline.addHandler(handler).get()
            let message: IMAPClientHandler.Message = IMAPClientHandler.OutboundIn.part(.tagged(command.tagged(tag)))
            try await channel.writeAndFlush(message).get()
            let result: T.Result = try await promise.futureResult.get()
            logger?.debug("\(command.description.capitalized(.sentence)) succeeded")
            if let clientBug = handler.clientBug {
                logger?.debug("CLIENTBUG: \(clientBug)")
            }
            return result
        } catch {
            promise.fail(error)
            logger?.error("\(error)")
            throw IMAPError.commandFailed(command.description)
        }
    }

    // Start idle through NIO `IMAPClientHandler` and stream results from special, long-running handler
    private func idleStart() async throws -> AsyncStream<IdleEvent> {
        let logger: Logger? = logger  // Copy logger instead of capturing
        logger?.debug("Executing idle start…")
        guard !isIdling else {
            throw IMAPError.commandFailed("Idle already started")
        }
        guard let channel, channel.isActive else {
            logger?.error("\(IMAPError.notConnected)")
            throw IMAPError.notConnected
        }
        var continuation: AsyncStream<IdleEvent>.Continuation?
        let idleEvents: AsyncStream<IdleEvent> = AsyncStream { continuation = $0 }
        let promise: EventLoopPromise<Void> = channel.eventLoop.makePromise(of: Void.self)
        let tag: String = UUID().uuidString(1)  // Hold onto specific auto-generated tag
        idleHandler = IdleHandler(tag: tag, promise: promise, continuation: continuation)
        let seconds: Int64 = .timeout
        let task: Scheduled = group.next().scheduleTask(in: .seconds(seconds)) {
            let error: IMAPError = .timedOut(seconds: seconds)
            logger?.error("\(error)")
            promise.fail(error)
        }
        defer { task.cancel() }
        do {
            try await channel.pipeline.addHandler(idleHandler!).get()
            let command: TaggedCommand = TaggedCommand(tag: tag, command: .idleStart)
            let message: IMAPClientHandler.Message = IMAPClientHandler.OutboundIn.part(.tagged(command))
            try await channel.writeAndFlush(message).get()
            return idleEvents
        } catch {
            promise.fail(error)
            logger?.error("\(error)")
            idleHandler = nil
            throw IMAPError.commandFailed("Idle start failed")
        }
    }

    // End idle and clean up
    private func idleDone() async throws {
        guard let channel, channel.isActive else {
            logger?.error("\(IMAPError.notConnected)")
            throw IMAPError.notConnected
        }
        guard let idleHandler else { return }
        try? await channel.writeAndFlush(IMAPClientHandler.OutboundIn.part(.idleDone)).get()
        logger?.info("Idle done")
        defer {
            channel.pipeline.removeHandler(idleHandler, promise: nil)
            self.idleHandler = nil
        }
        try await idleHandler.promise.futureResult.get()
    }

    private func refreshCapabilities() async throws {
        logger?.info("Refreshing capabilities…")
        capabilities = Set(try await execute(command: CapabilityCommand()))
        logger?.info("Capabilities: \(self.capabilities)")
    }

    private func resetInactiveChannel() {
        guard let channel, !channel.isActive else { return }
        self.channel = nil
        logger?.info("Channel reset; ready to connect")
    }

    private var idleHandler: IdleHandler?
    private var channel: Channel?
    private var count: Int = 0
    private let group: EventLoopGroup
    private let logger: Logger?
}

extension Character {
    public static let delimiter: Self = "."
    public static let wildcard: Self = "*"

    static let prefix: Self = "a"
}

private extension ClientBootstrap {
    static func bootstrap(
        server: Server,
        logger: Logger? = nil,
        group: EventLoopGroup
    ) -> Self {
        Self(group: group).channelInitializer { channel in
            try! channel.pipeline.syncOperations.addHandlers(
                [
                    LoggingHandler(logger),
                    TLSClientHandler(serverHostname: server.hostname),
                    IMAPClientHandler(parserOptions: .max)
                ]
            )
            return channel.eventLoop.makeSucceededFuture(())
        }
    }
}

private extension NIOSSLContext {
    static var ssl: Self { try! Self(configuration: .makeClientConfiguration()) }
}

private func TLSClientHandler(serverHostname: String? = nil) -> NIOSSLClientHandler {
    try! NIOSSLClientHandler(context: .ssl, serverHostname: serverHostname)
}

private extension ResponseParser.Options {
    static var max: Self {
        Self(
            bufferLimit: 1024 * 1024,
            messageAttributeLimit: .max,
            bodySizeLimit: .max,
            literalSizeLimit: IMAPDefaults.literalSizeLimit
        )
    }
}
