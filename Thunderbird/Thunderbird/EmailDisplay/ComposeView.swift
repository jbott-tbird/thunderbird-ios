// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import EmailAddress
import InfomaniakRichHTMLEditor
import SwiftUI

/// Compose a new message and hand it to the ``Outbox`` for delivery.
///
/// The body is edited with Infomaniak's `RichHTMLEditor` and sent as `multipart/alternative`
/// (plain-text + `text/html`). Sending is queued (Phase 7): the composer dismisses immediately and
/// the outbox delivers in the background with retry, so a transient failure or being offline doesn't
/// lose the message.
struct ComposeView: View {
    let account: Account

    @Environment(\.dismiss) private var dismiss
    @Environment(Outbox.self) private var outbox

    @State private var to: String
    @State private var cc: String
    @State private var bcc: String
    @State private var subject: String
    @State private var html: String

    @StateObject private var textAttributes = TextAttributes()

    /// Open the composer for `account`, optionally prefilled (e.g. a reply or forward ``MessageDraft``).
    init(account: Account, draft: MessageDraft = MessageDraft()) {
        self.account = account
        _to = State(initialValue: draft.to)
        _cc = State(initialValue: draft.cc)
        _bcc = State(initialValue: draft.bcc)
        _subject = State(initialValue: draft.subject)
        _html = State(initialValue: draft.html)
    }

    /// The address mail is sent from — the account's first configured identity.
    private var sender: EmailAddress? { account.identities.first }

    private var canSend: Bool {
        sender != nil && !recipients(to).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    addressField("To", text: $to)
                    Divider()
                    addressField("Cc", text: $cc)
                    Divider()
                    addressField("Bcc", text: $bcc)
                    Divider()
                    HStack {
                        Text("Subject")
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        TextField("Subject", text: $subject)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
                .padding(.horizontal)

                RichHTMLEditor(html: $html, textAttributes: textAttributes)
                    .editorScrollable(true)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                formatBar
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(!canSend)
                }
            }
        }
    }

    /// A persistent formatting bar; each button reflects and toggles the current selection's style.
    private var formatBar: some View {
        HStack(spacing: 22) {
            formatButton("bold", isActive: textAttributes.hasBold) { textAttributes.bold() }
            formatButton("italic", isActive: textAttributes.hasItalic) { textAttributes.italic() }
            formatButton("underline", isActive: textAttributes.hasUnderline) { textAttributes.underline() }
            formatButton("strikethrough", isActive: textAttributes.hasStrikethrough) { textAttributes.strikethrough() }
            formatButton("list.bullet", isActive: textAttributes.hasUnorderedList) { textAttributes.unorderedList() }
            formatButton("list.number", isActive: textAttributes.hasOrderedList) { textAttributes.orderedList() }
        }
        .font(.body)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func formatButton(_ systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func addressField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField("name@example.com", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
        }
        .padding(.vertical, 10)
    }

    /// Best-effort plain-text rendering of the editor's HTML, used as the `multipart/alternative`
    /// fallback for clients that don't render HTML. Converts block/line tags to newlines and list
    /// items to bullets, strips remaining tags, and decodes the common HTML entities.
    private func plainText(fromHTML html: String) -> String {
        var text = html
        let tagReplacements: [(pattern: String, replacement: String)] = [
            ("(?i)<li[^>]*>", "\n• "),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|li|tr|h[1-6]|ul|ol|blockquote)>", "\n"),
        ]
        for (pattern, replacement) in tagReplacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode `&amp;` last so e.g. "&amp;lt;" doesn't collapse into "<".
        let entities: [(entity: String, character: String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split a comma-separated field into addresses, ignoring blanks.
    private func recipients(_ field: String) -> [EmailAddress] {
        field
            .split(separator: ",")
            .map { EmailAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.value.isEmpty }
    }

    /// Queue the message for delivery and dismiss; the ``Outbox`` sends it in the background.
    private func send() {
        guard let sender else { return }
        outbox.enqueue(
            account: account,
            sender: sender,
            to: recipients(to),
            cc: recipients(cc),
            bcc: recipients(bcc),
            subject: subject,
            html: html,
            plainText: plainText(fromHTML: html))
        dismiss()
    }
}
