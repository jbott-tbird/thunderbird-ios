// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import EmailAddress
import Foundation
import SwiftData

/// A message queued for delivery, persisted so it survives relaunch and can be retried after a
/// failure or while offline. The composer enqueues these; ``Outbox`` drains the queue over SMTP.
@Model
final class OutgoingEmail {
    /// Lifecycle of a queued message.
    enum Status: String, Codable {
        case queued    // Waiting for a send attempt
        case sending   // A send is in flight
        case failed    // The last attempt failed (auto-retried while attempts remain, else manual)
    }

    @Attribute(.unique) var id: UUID
    var accountID: UUID

    var sender: [EmailAddress]
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var bcc: [EmailAddress]
    var subject: String
    var html: String
    var plainText: String

    var createdAt: Date
    private var statusRaw: String
    var attemptCount: Int
    var lastError: String?
    /// Earliest time the next automatic retry should run (back-off), if failed but still retriable.
    var nextAttemptAt: Date?

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    init(
        accountID: UUID,
        sender: [EmailAddress],
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String,
        html: String,
        plainText: String,
        createdAt: Date = .now,
        id: UUID = UUID()
    ) {
        self.id = id
        self.accountID = accountID
        self.sender = sender
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.html = html
        self.plainText = plainText
        self.createdAt = createdAt
        self.statusRaw = Status.queued.rawValue
        self.attemptCount = 0
        self.lastError = nil
        self.nextAttemptAt = nil
    }

    /// A short, human-readable recipient summary for list rows.
    var recipientSummary: String {
        let names = to.map { $0.label ?? $0.value }
        return names.isEmpty ? String(localized: "No recipients") : names.joined(separator: ", ")
    }
}
