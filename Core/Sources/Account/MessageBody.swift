// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import IMAP
import MIME

/// A `Sendable`, display-ready body extracted from a fully fetched IMAP ``IMAP/Message``.
///
/// Walks the MIME tree, transfer-decoding `text/html` and `text/plain` parts and collecting
/// attachment metadata.
public struct MessageBody: Sendable, Equatable {
    public struct Attachment: Sendable, Equatable {
        public let filename: String?
        public let contentType: String
        public let byteCount: Int
        /// The MIME body section (e.g. `[2]` → `BODY[2]`), used to fetch this part on demand via
        /// ``MessageManager/fetchAttachment(mailbox:uid:section:encoding:)``.
        public let section: [Int]
        /// The part's transfer encoding (raw value, e.g. `"base64"`), needed to decode fetched bytes.
        public let encoding: String?

        public init(filename: String?, contentType: String, byteCount: Int, section: [Int], encoding: String?) {
            self.filename = filename
            self.contentType = contentType
            self.byteCount = byteCount
            self.section = section
            self.encoding = encoding
        }
    }

    public let html: String?
    public let plainText: String?
    public let attachments: [Attachment]

    public var hasAttachments: Bool { !attachments.isEmpty }

    /// HTML suitable for a web view: the HTML part if present, otherwise the plain-text part
    /// escaped and wrapped so it renders readably. `nil` if neither part exists.
    public var displayHTML: String? {
        if let html { return html }
        guard let plainText else { return nil }
        let escaped: String = plainText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<pre style=\"white-space: pre-wrap; word-wrap: break-word; font: -apple-system-body;\">\(escaped)</pre>"
    }

    public init(html: String?, plainText: String?, attachments: [Attachment]) {
        self.html = html
        self.plainText = plainText
        self.attachments = attachments
    }

    /// Extract the body from a fully fetched message (use `FetchAttribute.complete`).
    public init(_ message: Message) {
        var html: String?
        var plainText: String?
        var attachments: [Attachment] = []
        if let body: MIME.Body = message.body {
            Self.walk(body.parts, section: [], html: &html, plainText: &plainText, attachments: &attachments)
        }
        self.init(html: html, plainText: plainText, attachments: attachments)
    }

    /// Walk the MIME tree, tracking each part's IMAP section number (`section`): the top-level parts
    /// are `[1]`, `[2]`, …; the children of a multipart part `[i]` are `[i, 1]`, `[i, 2]`, …, matching
    /// RFC 3501 `BODY[<section>]` numbering so attachments can be re-fetched on demand.
    private static func walk(_ parts: [Part], section prefix: [Int], html: inout String?, plainText: inout String?, attachments: inout [Attachment]) {
        for (index, part) in parts.enumerated() {
            let section: [Int] = prefix + [index + 1]
            if part.contentType.isMultipart {
                if let nested: [Part] = try? part.parts {
                    walk(nested, section: section, html: &html, plainText: &plainText, attachments: &attachments)
                }
                continue
            }
            if case .attachment(let file) = part.contentDisposition {
                attachments.append(
                    Attachment(
                        filename: file.filename,
                        contentType: part.contentType.description,
                        byteCount: file.size ?? part.data.count,
                        section: section,
                        encoding: part.contentTransferEncoding?.rawValue))
                continue
            }
            switch part.contentType.subtype.lowercased() {
            case "html" where html == nil: html = decodedText(part)
            case "plain" where plainText == nil: plainText = decodedText(part)
            default: break
            }
        }
    }

    /// Transfer-decode a text part to a `String`, honoring its charset (defaulting to UTF-8).
    private static func decodedText(_ part: Part) -> String? {
        let encoding: String.Encoding = stringEncoding(part.contentType.charset?.rawValue)
        switch part.contentTransferEncoding {
        case .base64: return try? String(base64: part.data, encoding: encoding)
        case .quotedPrintable: return try? String(quotedPrintable: part.data, encoding: encoding)
        default: return String(data: part.data, encoding: encoding) ?? String(data: part.data, encoding: .utf8)
        }
    }

    /// Map a MIME charset name to a `String.Encoding` (MIME's own mapper is module-internal).
    private static func stringEncoding(_ charset: String?) -> String.Encoding {
        switch charset?.uppercased() {
        case "US-ASCII": return .ascii
        case "ISO-8859-1": return .isoLatin1
        case "ISO-8859-2": return .isoLatin2
        default: return .utf8  // UTF-8 and unknown
        }
    }
}
