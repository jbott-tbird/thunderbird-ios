// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Multipart body element described in [RFC 2045](https://www.rfc-editor.org/rfc/rfc2045#section-2.6)
public struct Body: CustomStringConvertible, RawRepresentable, Sendable {
    public let contentTransferEncoding: ContentTransferEncoding?
    public let contentType: ContentType
    public let parts: [Part]

    public var headers: [String: String] {
        var headers: [String: String] = [:]
        if contentType.isMultipart {
            headers["MIME-Version"] = "1.0"
        }
        if let contentTransferEncoding {
            headers["Content-Transfer-Encoding"] = contentTransferEncoding.description
        }
        headers["Content-Type"] = contentType.description
        return headers
    }

    public init(parts: [Part], contentType: ContentType = .multipart(.mixed), encoding: ContentTransferEncoding? = nil) throws {
        guard !parts.isEmpty else {
            throw MIMEError.dataNotFound
        }
        if parts.count == 1 {
            switch parts[0].contentType {
            case .text:
                contentTransferEncoding = parts[0].contentTransferEncoding
                self.contentType = contentType
            default:
                throw MIMEError.contentTypeNotPossible(contentType)
            }
        } else if contentType.isMultipart {
            contentTransferEncoding = encoding
            self.contentType = contentType
        } else {
            throw MIMEError.contentTypeNotPossible(contentType)
        }
        self.parts = parts
    }

    /// Read headers and decode body from raw ASCII blob.
    public init(_ description: String) throws {
        let part: Part = try Part(description)
        switch part.contentType {
        case .multipart:
            let parts: [Part] = try part.parts
            try self.init(parts: parts, contentType: part.contentType, encoding: part.contentTransferEncoding)
        case .text(let subtype, let charset):
            try self.init(parts: [part], contentType: .text(subtype, charset))
        default:
            throw MIMEError.contentTypeNotPossible(part.contentType)
        }
    }

    /// Read headers and decode body from raw ASCII data.
    public init(_ description: Data) throws {
        guard let description: String = String(data: description, encoding: .ascii) else {
            throw MIMEError.dataNotDecoded(description, encoding: .ascii)
        }
        try self.init(description)
    }

    // MARK: CustomStringConvertible
    public var description: String { String(data: rawValue, encoding: .ascii)! }

    // MARK: RawRepresentable
    public var rawValue: Data {
        var data: Data = Data()
        for key in headers.keys {
            data.append("\(key): \(headers[key]!)\(crlf)".data(using: .ascii)!)
        }
        switch contentType {
        case .multipart(_, let boundary):
            data.append(try! parts.data(using: boundary))
        case .text:
            data.append(crlf.data(using: .ascii)!)
            data.append(parts[0].data)
            data.append(crlf.data(using: .ascii)!)
        default:
            fatalError(MIMEError.contentTypeNotPossible(contentType).description)
        }
        return data
    }

    public init?(rawValue: Data) {
        try? self.init(rawValue)
    }
}

extension Body {
    public static var empty: Self {
        try! Self(
            parts: [
                try! Part(data: "".data(using: .ascii)!, contentType: .text(.plain, .ascii))
            ], contentType: .text(.plain, .ascii))
    }

    public var isEmpty: Bool {
        parts.count == 1 && (String(data: parts[0].data, encoding: .ascii) ?? "").isEmpty
    }
}

extension Body {
    /// Build a `multipart/alternative` body that pairs a plain-text and an HTML rendering of the
    /// same message. Per [RFC 2046 §5.1.4](https://www.rfc-editor.org/rfc/rfc2046#section-5.1.4)
    /// the parts are ordered least- to most-faithful (plain text first, HTML last) so a client
    /// renders the richest representation it supports and falls back to plain text otherwise. Both
    /// parts are UTF-8.
    public static func alternative(plainText: String, html: String) throws -> Self {
        let text: Part = try Part(data: Data(plainText.utf8), contentType: .text(.plain, .utf8))
        let markup: Part = try Part(data: Data(html.utf8), contentType: .text(.html, .utf8))
        return try Self(parts: [text, markup], contentType: .multipart(.alternative))
    }
}
