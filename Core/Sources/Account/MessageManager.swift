// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A change to the monitored INBOX, surfaced by ``MessageManager/monitorInbox()``.
public enum InboxUpdate: Sendable {
    /// New messages arrived (newest first), already fetched at the envelope level — upsert directly.
    case added([EmailData])

    /// Messages were removed (or the count otherwise dropped) server-side; the caller should resync
    /// (e.g. a full ``MessageManager/fetchInbox(count:)`` refresh).
    case needsReconcile
}

/// Fetch and send messages for a given `Account`.
///
/// A lightweight, `Sendable` service over an immutable `Account` — its methods can be called from
/// any actor (e.g. a `@MainActor` view model awaiting an off-actor IMAP/SMTP operation).
public final class MessageManager: Sendable {
    public let account: Account

    public init(account: Account) {
        self.account = account
    }

    /// Fetch a page of INBOX messages as `Sendable` ``EmailData`` snapshots, newest first.
    ///
    /// Connects (authenticating via XOAUTH2 for OAuth2 accounts), selects INBOX, and fetches `count`
    /// envelope-level messages by sequence number. By default it returns the newest `count`; pass
    /// `olderThan` (the number of newest messages already loaded) to page further back for "load
    /// more". Returns an empty array for non-IMAP accounts, an empty/absent INBOX, or once paging has
    /// run past the oldest message.
    public func fetchInbox(count: Int = 50, olderThan loaded: Int = 0) async throws -> [EmailData] {
        guard account.emailProtocol == .imap else { return [] }
        let client: IMAPClient = try await account.imapClient
        let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
        guard let inbox: IMAP.Mailbox = mailboxes.first(where: {
            $0.0.path.name.description.uppercased() == "INBOX"
        })?.0 else {
            return []
        }
        let mailboxName: String = inbox.path.name.description
        let status: IMAP.Mailbox.Status = try await client.select(mailbox: inbox)
        let total: Int = status.messageCount ?? 0
        let uidValidity: Int = Int(status.uidValidityValue ?? 0)
        let upper: Int = total - loaded  // Highest sequence number in this page (skipping `loaded` newest)
        guard upper > 0 else { return [] }
        let set = SequenceSet(max(1, upper - count + 1)...upper)
        let messages: MessageSet = try await client.fetch(set, attributes: .standard)
        return messages
            .sorted { $0.key > $1.key }  // Newest (highest sequence number) first
            .map { EmailData(accountID: account.id, mailbox: mailboxName, uidValidity: uidValidity, message: $0.value) }
    }

    /// Add or remove the `\Seen` flag on a message server-side (local→server reconciliation).
    public func markSeen(mailbox: String, uid: Int, _ seen: Bool) async throws {
        try await store(mailbox: mailbox, uid: uid, flag: .seen, enabled: seen)
    }

    /// Add or remove the `\Flagged` flag on a message server-side (local→server reconciliation).
    public func markFlagged(mailbox: String, uid: Int, _ flagged: Bool) async throws {
        try await store(mailbox: mailbox, uid: uid, flag: .flagged, enabled: flagged)
    }

    /// Select `mailbox` and add/remove `flag` on the message with `uid`.
    private func store(mailbox: String, uid: Int, flag: Flag, enabled: Bool) async throws {
        guard account.emailProtocol == .imap else { return }
        let client: IMAPClient = try await account.imapClient
        try await select(mailbox, on: client)
        try await client.store(uid: UID(rawValue: UInt32(uid)), flag: flag, enabled: enabled)
    }

    /// Fetch and extract the full body (HTML/plain text + attachment metadata) of a message by UID,
    /// optionally marking it `\Seen`.
    ///
    /// Selects `mailbox`, fetches the complete message for `uid`, and walks its MIME tree.
    public func fetchBody(mailbox: String, uid: Int, markSeen: Bool = true) async throws -> MessageBody {
        guard account.emailProtocol == .imap else {
            return MessageBody(html: nil, plainText: nil, attachments: [])
        }
        let client: IMAPClient = try await account.imapClient
        try await select(mailbox, on: client)
        let imapUID = UID(rawValue: UInt32(uid))
        let message: Message = try await client.fetch(uid: imapUID, attributes: .complete)
        if markSeen {
            try? await client.markSeen(uid: imapUID)
        }
        return MessageBody(message)
    }

    /// Fetch and transfer-decode a single attachment's bytes, on demand, by its MIME body section.
    ///
    /// Fetches only `BODY[<section>]` (not the whole message) for `uid`, then decodes the raw bytes
    /// using `encoding` (the part's transfer encoding, typically `base64`). `section` and `encoding`
    /// come from a ``MessageBody/Attachment`` produced by ``fetchBody(mailbox:uid:markSeen:)``.
    public func fetchAttachment(mailbox: String, uid: Int, section: [Int], encoding: String?) async throws -> Data {
        guard account.emailProtocol == .imap else {
            throw IMAPError.commandFailed("Attachments require an IMAP account")
        }
        let client: IMAPClient = try await account.imapClient
        try await select(mailbox, on: client)
        let imapUID = UID(rawValue: UInt32(uid))
        guard let raw: Data = try await client.fetch(uid: imapUID, section: section) else {
            throw IMAPError.commandFailed("Attachment section \(section) not found")
        }
        return raw.transferDecoded(ContentTransferEncoding(rawValue: encoding ?? ""))
    }

    /// List mailboxes and select `mailbox` by name on `client`, throwing if it isn't found.
    private func select(_ mailbox: String, on client: IMAPClient) async throws {
        let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
        guard let target: IMAP.Mailbox = mailboxes.first(where: { $0.0.path.name.description == mailbox })?.0 else {
            throw IMAPError.commandFailed("Mailbox \(mailbox) not found")
        }
        try await client.select(mailbox: target)
    }

    /// Watch INBOX for changes in real time using IMAP IDLE, on a dedicated connection.
    ///
    /// Yields an ``InboxUpdate`` each time the server pushes a change (or the idle window lapses and
    /// a poll finds one). Newly-arrived messages are fetched at the envelope level — the same shape
    /// as ``fetchInbox(count:)`` — so the caller can upsert them directly; removals/decreases surface
    /// as ``InboxUpdate/needsReconcile`` for the caller to resync.
    ///
    /// The IDLE loop runs detached, off the main actor. The stream finishes when the caller stops
    /// iterating (cancelling the loop) or throws if IDLE is unsupported or the connection can't be
    /// (re)established — callers should fall back to manual refresh in that case.
    public func monitorInbox() -> AsyncThrowingStream<InboxUpdate, Error> {
        let account: Account = self.account
        return AsyncThrowingStream { continuation in
            let task: Task = Task.detached {
                do {
                    try await Self.runInboxMonitor(account: account, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// How long a single IDLE waits before waking to refresh the connection (RFC 2177 advises a
    /// re-IDLE well under ~30 min so the server doesn't drop it).
    private static let maxIdleSeconds: Int = 25 * 60

    /// Which arm of an IDLE cycle completed first.
    private enum IdleOutcome: Sendable, Equatable {
        case changed       // server pushed an EXISTS/RECENT update
        case reconcile     // server pushed an EXPUNGE
        case bye           // server closed the connection
        case streamEnded   // idle stream ended without a verdict
        case windowElapsed // idle window lapsed; poll for changes
    }

    /// Drive the IDLE loop on a dedicated connection until the surrounding `Task` is cancelled.
    private static func runInboxMonitor(
        account: Account,
        continuation: AsyncThrowingStream<InboxUpdate, Error>.Continuation
    ) async throws {
        guard account.emailProtocol == .imap else { return }
        var connection: IMAPClient?
        var inbox: IMAP.Mailbox?
        var mailboxName: String = "INBOX"
        var uidValidity: Int = 0
        var known: Int = 0

        // Connect (if needed), require IDLE, and select INBOX, capturing the baseline message count.
        func ensureSelected() async throws {
            if connection?.isConnected != true {
                let client: IMAPClient = try await account.newIMAPClient()
                try client.isSupported(.idle)  // capabilityNotSupported propagates to the caller
                let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
                guard let box: IMAP.Mailbox = mailboxes.first(where: {
                    $0.0.path.name.description.uppercased() == "INBOX"
                })?.0 else {
                    throw IMAPError.commandFailed("INBOX not found")
                }
                let status: IMAP.Mailbox.Status = try await client.select(mailbox: box)
                connection = client
                inbox = box
                mailboxName = box.path.name.description
                uidValidity = Int(status.uidValidityValue ?? 0)
                known = status.messageCount ?? 0
            }
        }

        defer { try? connection?.disconnect() }

        while !Task.isCancelled {
            try await ensureSelected()
            guard let client: IMAPClient = connection, let box: IMAP.Mailbox = inbox else { break }

            // Idle until the server pushes a change or the window lapses, whichever comes first.
            let events: AsyncStream<IdleEvent> = try await client.idle()
            let outcome: IdleOutcome = await withTaskGroup(of: IdleOutcome.self) { group in
                group.addTask {  // Reader — captures only the Sendable event stream
                    for await event in events {
                        switch event {
                        case .status: return .changed
                        case .expunge: return .reconcile
                        case .bye: return .bye
                        case .fetch: continue
                        }
                    }
                    return .streamEnded
                }
                group.addTask {  // Idle window — captures nothing
                    try? await Task.sleep(for: .seconds(maxIdleSeconds))
                    return .windowElapsed
                }
                let first: IdleOutcome = await group.next() ?? .streamEnded
                group.cancelAll()
                return first
            }
            if client.isIdling { try? await client.done() }
            if Task.isCancelled { break }

            switch outcome {
            case .bye, .streamEnded:
                try? client.disconnect()
                connection = nil  // ensureSelected() rebuilds and re-baselines next iteration
            case .changed, .reconcile, .windowElapsed:
                // Re-select to read the authoritative current count (EXISTS pushes can be partial).
                let status: IMAP.Mailbox.Status = try await client.select(mailbox: box)
                let current: Int = status.messageCount ?? known
                if current > known {
                    let set = SequenceSet(known + 1 ... current)
                    let messages: MessageSet = try await client.fetch(set, attributes: .standard)
                    let added: [EmailData] = messages
                        .sorted { $0.key > $1.key }
                        .map { EmailData(accountID: account.id, mailbox: mailboxName, uidValidity: uidValidity, message: $0.value) }
                    if !added.isEmpty { continuation.yield(.added(added)) }
                    known = current
                } else if current < known || outcome == .reconcile {
                    continuation.yield(.needsReconcile)
                    known = current
                }
            }
        }
    }

    /// Send a composed message through the account's outgoing (SMTP) server.
    ///
    /// Refreshes the outgoing OAuth token if it is near expiry, then connects and sends over SMTP
    /// `XOAUTH2` (or `AUTH LOGIN` for password accounts). A non-expired token that the server still
    /// rejects triggers one forced refresh + retry, mirroring ``Account/imapClient``.
    public func send(_ email: SMTP.Email) async throws {
        guard account.emailProtocol == .imap, let outgoingServer = account.outgoingServer else {
            throw SMTPError.serverProtocolMismatch
        }
        try await account.refreshOutgoingTokenIfNeeded()
        do {
            try await SMTPClient(try SMTP.Server(account.outgoingServer ?? outgoingServer)).send(email)
        } catch SMTPError.authenticationFailed {
            guard try await account.refreshOutgoingTokenIfNeeded(force: true) else {
                throw SMTPError.authenticationFailed
            }
            try await SMTPClient(try SMTP.Server(account.outgoingServer ?? outgoingServer)).send(email)
        }
    }

    /// Diagnostic: print the subjects of the most recent `count` INBOX messages (temporary, until
    /// the inbox list view is wired in Milestone D).
    public func printTopSubjects(_ count: Int = 10) async {
        do {
            let emails: [EmailData] = try await fetchInbox(count: count)
            print("OAuth: top \(emails.count) INBOX subjects ↓")
            for email in emails {
                print("  • \(email.subject.isEmpty ? "(no subject)" : email.subject)")
            }
        } catch {
            print("OAuth fetch error: \(error)")
        }
    }
}
