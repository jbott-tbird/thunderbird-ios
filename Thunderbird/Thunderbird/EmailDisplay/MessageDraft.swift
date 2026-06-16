// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import EmailAddress
import Foundation

/// Prefilled content for the composer. A blank draft is a new message; the `reply`, `replyAll`, and
/// `forward` factories derive a draft from an existing ``Email`` (Phase 4).
///
/// Fields hold comma-separated addresses and an HTML body so they map directly onto `ComposeView`'s
/// editable state.
struct MessageDraft: Identifiable {
    let id = UUID()
    var to: String = ""
    var cc: String = ""
    var bcc: String = ""
    var subject: String = ""
    var html: String = ""
}

extension MessageDraft {
    /// Reply to the message's author: To is the reply-to (or From) addresses, subject gets a `Re:`
    /// prefix, and the original is quoted beneath an attribution line.
    static func reply(to email: Email) -> MessageDraft {
        MessageDraft(
            to: addresses(replyTargets(of: email)),
            subject: prefixedSubject(email.subject, with: "Re:"),
            html: quotedBody(of: email)
        )
    }

    /// Reply to everyone: To is the reply-to (or From) addresses; Cc is the original To + Cc, minus
    /// the account's own identities and anyone already in To.
    static func replyAll(to email: Email, identities: [EmailAddress]) -> MessageDraft {
        let targets: [EmailAddress] = replyTargets(of: email)
        let excluded: Set<String> = Set((identities + targets).map { $0.value.lowercased() })
        let others: [EmailAddress] = deduplicated(email.to + email.cc)
            .filter { !excluded.contains($0.value.lowercased()) }
        return MessageDraft(
            to: addresses(targets),
            cc: addresses(others),
            subject: prefixedSubject(email.subject, with: "Re:"),
            html: quotedBody(of: email)
        )
    }

    /// Forward the message: no recipients, subject gets a `Fwd:` prefix, and the original is quoted
    /// beneath a forwarded-message header.
    static func forward(_ email: Email) -> MessageDraft {
        MessageDraft(
            subject: prefixedSubject(email.subject, with: "Fwd:"),
            html: forwardedBody(of: email)
        )
    }

    // MARK: Helpers

    /// The addresses a reply is sent to: Reply-To when present, otherwise From.
    private static func replyTargets(of email: Email) -> [EmailAddress] {
        email.replyTo.isEmpty ? email.from : email.replyTo
    }

    private static func addresses(_ list: [EmailAddress]) -> String {
        list.map { $0.value }.joined(separator: ", ")
    }

    /// Remove duplicate addresses (case-insensitive), preserving first-seen order.
    private static func deduplicated(_ list: [EmailAddress]) -> [EmailAddress] {
        var seen: Set<String> = []
        return list.filter { seen.insert($0.value.lowercased()).inserted }
    }

    /// Add `prefix` unless the (case-insensitive) subject already starts with it.
    private static func prefixedSubject(_ subject: String, with prefix: String) -> String {
        let trimmed: String = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.lowercased().hasPrefix(prefix.lowercased()) else { return trimmed }
        return "\(prefix) \(trimmed)"
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Blank lines for the reply, then the original quoted in a cite blockquote.
    private static func quotedBody(of email: Email) -> String {
        let author: String = email.from.first?.value ?? ""
        let attribution: String = "On \(formatted(email.date)), \(author) wrote:"
        return """
            <br><br><div>\(attribution)</div>\
            <blockquote type="cite" style="margin:0 0 0 0.8ex; border-left:2px solid #ccc; padding-left:1ex;">\
            \(email.bodyText ?? "")</blockquote>
            """
    }

    /// Blank lines, a forwarded-message header, then the original body.
    private static func forwardedBody(of email: Email) -> String {
        """
        <br><br>---------- Forwarded message ----------<br>
        From: \(addresses(email.from))<br>
        Date: \(formatted(email.date))<br>
        Subject: \(email.subject)<br>
        To: \(addresses(email.to))<br><br>
        \(email.bodyText ?? "")
        """
    }
}
