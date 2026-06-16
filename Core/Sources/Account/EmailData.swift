// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import EmailAddress
import Foundation
import IMAP

/// A `Sendable` snapshot of a message, mapped from an IMAP ``IMAP/Message``.
///
/// This is the platform-neutral hand-off between the IMAP fetch (which may run off the main actor)
/// and the app's SwiftData model — the model is built/updated from `EmailData` on its own context.
public struct EmailData: Sendable, Equatable, Identifiable {
    /// Stable identity across syncs: account + mailbox + UID validity + UID.
    public let id: String
    public let accountID: UUID
    public let mailbox: String
    public let uid: Int
    public let uidValidity: Int

    public let subject: String
    public let from: [EmailAddress]
    public let sender: [EmailAddress]
    public let replyTo: [EmailAddress]
    public let to: [EmailAddress]
    public let cc: [EmailAddress]
    public let bcc: [EmailAddress]
    public let date: Date
    public let isUnread: Bool
    public let isFlagged: Bool
    public let threadID: String?
    public let messageID: String?

    /// Build the stable identity string for an account / mailbox / UID-validity / UID tuple.
    public static func id(accountID: UUID, mailbox: String, uidValidity: Int, uid: Int) -> String {
        "\(accountID.uuidString)/\(mailbox)/\(uidValidity)/\(uid)"
    }

    /// Map an IMAP message (envelope-level fetch) into a `Sendable` snapshot.
    ///
    /// - Parameters:
    ///   - accountID: Owning account.
    ///   - mailbox: Mailbox the message was fetched from (e.g. `"INBOX"`).
    ///   - uidValidity: The selected mailbox's `UIDVALIDITY`; pins the UID namespace.
    ///   - message: The fetched IMAP message.
    public init(accountID: UUID, mailbox: String, uidValidity: Int, message: Message) {
        let uid: Int = Int(message.uid?.rawValue ?? 0)
        self.id = Self.id(accountID: accountID, mailbox: mailbox, uidValidity: uidValidity, uid: uid)
        self.accountID = accountID
        self.mailbox = mailbox
        self.uid = uid
        self.uidValidity = uidValidity

        let envelope: Envelope = message.envelope
        self.subject = envelope.subject ?? ""
        self.from = envelope.from.flatMap { $0.addresses }
        self.sender = envelope.sender.flatMap { $0.addresses }
        self.replyTo = envelope.reply.flatMap { $0.addresses }
        self.to = envelope.to.flatMap { $0.addresses }
        self.cc = envelope.cc.flatMap { $0.addresses }
        self.bcc = envelope.bcc.flatMap { $0.addresses }
        self.date = envelope.date?.date ?? message.internalDate ?? Date(timeIntervalSince1970: 0)
        self.isUnread = !message.flags.contains(.seen)
        self.isFlagged = message.flags.contains(.flagged)
        self.threadID = message.threadID ?? message.gmailThreadID.map(String.init)
        self.messageID = envelope.messageID
    }
}
