// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Account
import EmailAddress
import Foundation
import IMAP
import Testing

struct EmailDataTests {
    @Test func mapsEnvelopeFields() {
        let accountID: UUID = UUID()
        let date: Date = Date(timeIntervalSince1970: 1_700_000_000)
        let message: Message = Message(
            envelope: Envelope(
                subject: "Hello",
                date: InternetMessageDate(date),
                from: [EmailAddress("alice@example.com", label: "Alice")],
                to: [EmailAddress("bob@example.com")]
            ),
            flags: [.flagged],  // No \Seen → unread
            uid: UID(rawValue: 42)
        )
        let email: EmailData = EmailData(accountID: accountID, mailbox: "INBOX", uidValidity: 7, message: message)
        #expect(email.uid == 42)
        #expect(email.subject == "Hello")
        #expect(email.from == [EmailAddress("alice@example.com")])
        #expect(email.to == [EmailAddress("bob@example.com")])
        #expect(email.date == date)
        #expect(email.isUnread)
        #expect(email.isFlagged)
        #expect(email.id == "\(accountID.uuidString)/INBOX/7/42")
    }

    @Test func seenFlagClearsUnread() {
        let message: Message = Message(envelope: Envelope(subject: "x"), flags: [.seen], uid: UID(rawValue: 1))
        let email: EmailData = EmailData(accountID: UUID(), mailbox: "INBOX", uidValidity: 1, message: message)
        #expect(!email.isUnread)
        #expect(!email.isFlagged)
    }

    @Test func fallsBackToInternalDateWithoutEnvelopeDate() {
        let internalDate: Date = Date(timeIntervalSince1970: 1_600_000_000)
        let message: Message = Message(envelope: Envelope(subject: "x"), internalDate: internalDate, uid: UID(rawValue: 5))
        let email: EmailData = EmailData(accountID: UUID(), mailbox: "INBOX", uidValidity: 1, message: message)
        #expect(email.date == internalDate)
    }
}
