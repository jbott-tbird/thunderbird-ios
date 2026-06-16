//
//  EmailCell.swift
//  Thunderbird
//
//  Created by Ashley Soucar on 10/17/25.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import EmailAddress

struct EmailCellView: View {
    let email: Email
    @Environment(FeatureFlags.self) private var flags: FeatureFlags
    let senderText: String
    let headerText: String
    let bodyText: String
    let dateSent: Date

    // For alignment, bool check likely not final
    let unread: Bool
    let newEmail: Bool
    let pinned: Bool
    let hasAttachment: Bool
    let isThread: Bool

    init(email: Email) {
        let sender: EmailAddress? = email.from.first
        self.senderText = sender?.label ?? sender?.value ?? ""
        self.headerText = email.subject
        self.bodyText = email.bodyText ?? ""  // Body preview is populated when the message is opened (Milestone E)
        self.dateSent = email.date
        self.unread = email.isUnread
        self.newEmail = false  // No IMAP equivalent; reserved for future "recent" handling
        self.hasAttachment = email.hasAttachments
        self.isThread = email.isThread
        self.pinned = email.isFlagged
        self.email = email
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if pinned {
                    Image("icon.pin")
                        .font(.system(size: 8))
                }

                Text(senderText)
                    .lineLimit(1)
                    .font(.headline)
                    .fontWeight(unread ? .semibold : .regular)

                Spacer()

                Text(
                    SmartDateFormatter()
                        .dateFormatter(date: dateSent, isSmartDate: !flags.flagForKey(key: Flag.fullDate.rawValue))
                )
                .lineLimit(1)
                .font(.footnote)
                .truncationMode(.tail)
                .foregroundColor(.muted)

            }
            .padding(.leading, pinned ? 0 : 20)

            HStack {
                if newEmail {
                    Image(systemName: "circle")
                        .foregroundStyle(.accent)
                        .font(.system(size: 8))
                } else if unread {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.accent)
                        .font(.system(size: 8))
                }

                Text(headerText)
                    .lineLimit(1)
                    .font(.subheadline)
                    .fontWeight(unread ? .semibold : .regular)

                Spacer()

                if hasAttachment {
                    Image(systemName: "paperclip")
                        .foregroundColor(.muted)
                }

                if isThread {
                    Text("99+")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .foregroundColor(.muted)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(lineWidth: 1)
                                .foregroundColor(.muted)
                        )
                }
            }
            .padding(.leading, newEmail || unread ? 0 : 20)

            Text(bodyText)
                .lineLimit(1)
                .foregroundColor(.muted)
                .font(.footnote)
                .padding(.leading, 20)
        }
    }
}

#Preview("Email Cell") {
    @Previewable @State var flags: FeatureFlags = FeatureFlags(distribution: .current)

    let email = Email(
        subject: "This is the subject line of the email",
        from: [EmailAddress("sender1@test.com", label: "Sender1")],
        to: [EmailAddress("rheaThun@thundermail.com", label: "Rhea Thunderbird")],
        isUnread: true,
        isFlagged: true,
        bodyText: "This is some nice long preview text for the email body.",
        hasAttachments: true
    )

    EmailCellView(email: email).environment(flags)
}
