// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Account
import Foundation
import IMAP
import MIME
import Testing

struct MessageBodyTests {
    @Test func extractsHTMLPlainTextAndAttachments() throws {
        let plain = Part(data: Data("Hello".utf8), contentTransferEncoding: .ascii, contentType: .text("plain", .utf8))
        let html = Part(data: Data("<p>Hello</p>".utf8), contentTransferEncoding: .ascii, contentType: .text("html", .utf8))
        let attachment = Part(
            data: Data("filedata".utf8),
            contentDisposition: .attachment(.init(filename: "a.txt", size: 8)),
            contentTransferEncoding: .ascii,
            contentType: .application("octet-stream"))
        let body = try MIME.Body(parts: [plain, html, attachment], contentType: .multipart("mixed"))
        let message = Message(body: body, envelope: Envelope(subject: "x"))

        let extracted = MessageBody(message)
        #expect(extracted.html == "<p>Hello</p>")
        #expect(extracted.plainText == "Hello")
        #expect(extracted.hasAttachments)
        #expect(extracted.attachments.first?.filename == "a.txt")
        #expect(extracted.attachments.first?.section == [3])  // 3rd top-level part → BODY[3]
        #expect(extracted.attachments.first?.encoding == "7bit")
        #expect(extracted.displayHTML == "<p>Hello</p>")  // Prefers HTML
    }

    @Test func attachmentSectionAccountsForNestedMultipart() throws {
        let plain = Part(data: Data("Hi".utf8), contentTransferEncoding: .ascii, contentType: .text("plain", .utf8))
        let html = Part(data: Data("<p>Hi</p>".utf8), contentTransferEncoding: .ascii, contentType: .text("html", .utf8))
        let alternative = try Part(parts: [plain, html], contentType: .multipart("alternative"))
        let attachment = Part(
            data: Data("ZmlsZQ==".utf8),
            contentDisposition: .attachment(.init(filename: "b.pdf", size: 4)),
            contentTransferEncoding: .base64,
            contentType: .application("pdf"))
        let body = try MIME.Body(parts: [alternative, attachment], contentType: .multipart("mixed"))

        let extracted = MessageBody(Message(body: body, envelope: Envelope(subject: "x")))
        #expect(extracted.html == "<p>Hi</p>")  // Found inside the nested multipart/alternative
        #expect(extracted.attachments.first?.section == [2])  // 2nd top-level part → BODY[2]
        #expect(extracted.attachments.first?.encoding == "base64")
    }

    @Test func plainTextOnlyFallsBackToWrappedDisplayHTML() throws {
        let plain = Part(data: Data("a < b".utf8), contentTransferEncoding: .ascii, contentType: .text("plain", .utf8))
        let body = try MIME.Body(parts: [plain], contentType: .text("plain", .utf8))
        let extracted = MessageBody(Message(body: body, envelope: Envelope(subject: "x")))
        #expect(extracted.html == nil)
        #expect(extracted.plainText == "a < b")
        #expect(extracted.displayHTML?.contains("a &lt; b") == true)  // Escaped + wrapped
    }
}
