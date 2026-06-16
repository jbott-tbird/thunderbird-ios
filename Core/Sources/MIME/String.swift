// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension String {

    /// Line is defined as a sequence of octets separated by a [CRLF](https://developer.mozilla.org/en-US/docs/Glossary/CRLF)
    /// Described in [RFC 2045](https://www.rfc-editor.org/rfc/rfc2045#section-2.10)
    public static var crlf: Self { "\r\n" }

    /// ASCII-compatible UUID string separator
    public static var separator: Self { "-" }

    /// ASCII representation, if `String` is ASCII
    public var ascii: Self? {
        guard let data: Data = data(using: .ascii) else {
            return nil
        }
        return Self(data: data, encoding: .ascii)
    }

    /// Capitalization case formats
    public enum Case: CaseIterable {
        case sentence, title
    }

    /// Overload capitalization with alternate case options
    public func capitalized(_ `case`: Case) -> Self {
        switch `case` {
        case .sentence: "\(prefix(1).capitalized)\(dropFirst())"
        case .title: capitalized
        }
    }

    /// Break email header value string into parameter keys and values.
    public var parameters: [Self: Self] {
        var parameters: [Self: Self] = [:]
        for parameter in components(separatedBy: ";") {
            guard let index: String.Index = parameter.firstIndex(of: "=") else {
                continue
            }
            let key: String = "\(parameter.prefix(upTo: index))".lowercased().trimmed()
            let value: String = "\(parameter.trimmed().dropFirst(key.count + 1))".removing(.quotes).trimmed()
            parameters[key] = value
        }
        return parameters
    }

    /// Decode any [RFC 2047](https://www.rfc-editor.org/rfc/rfc2047)-encoded email header string
    public func headerDecoded() throws -> Self {

        // Because encoding creates significantly longer strings, headers can be encoded in multiple segments
        // Allows selecting the shortest encoding method for arbitrary chunks
        let segments: [Self] = trimmed().components(separatedBy: "?= =?")
        if segments.count > 1 {
            let segments: [Self] = try segments.map {
                try "\(!$0.hasPrefix("=?") ? "=?" : "")\($0)\(!$0.hasSuffix("?=") ? "?=" : "")".headerDecoded()
            }
            return segments.joined(separator: "")
        }
        var string: Self = trimmed()
        guard string.hasPrefix("=?"), string.hasSuffix("?=") else {
            return self  // String not header-encoded; skip decoding
        }
        let components: [Self] = Array(string.components(separatedBy: "?").dropLast().dropFirst())
        guard components.count > 2 else {
            throw MIMEError.headerNotDecoded(string)
        }
        let encoding: Encoding = try Encoding(components[0])
        let contentTransferEncoding: ContentTransferEncoding = try ContentTransferEncoding(components[1])
        string = components.dropFirst(2).joined(separator: "?")
        switch contentTransferEncoding {
        case .base64:
            return try Self(base64: string, encoding: encoding)
        case .quotedPrintable:
            return try string.decodingQuotedPrintable(to: encoding, isEncodedWord: true)
        default:
            throw MIMEError.headerNotDecoded(string)
        }
    }

    /// Encode any string as a UTF-8, base64 email header.
    /// Described in [RFC 2047](https://www.rfc-editor.org/rfc/rfc2047)
    public func headerEncoded() throws -> Self {
        if let data: Data = data(using: .ascii),
            let string: Self = Self(data: data, encoding: .ascii)
        {
            return string  // Already plain ASCII
        }
        guard let data: Data = data(using: .utf8) else {
            throw MIMEError.dataNotFound
        }
        return [
            "=",
            "UTF-8",
            "B",
            data.base64EncodedString(),
            "="
        ].joined(separator: "?")
    }

    /// Decode quoted-printable data to given `String.Encoding`.
    public init(quotedPrintable data: Data, encoding: Encoding = .utf8) throws {
        guard let string: String = String(data: data, encoding: encoding) else {
            throw MIMEError.dataNotDecoded(data, encoding: encoding)
        }
        self = try Self(quotedPrintable: string, encoding: encoding)
    }

    /// Decode quoted-printable string to given `String.Encoding`.
    public init(quotedPrintable string: Self, encoding: Encoding = .utf8) throws {
        self = try string.decodingQuotedPrintable(to: encoding)
    }

    /// Decode base64 data to given `String.Encoding`.
    public init(base64 data: Data, encoding: Encoding = .utf8) throws {
        guard let string: String = String(data: data, encoding: .utf8) else {
            throw MIMEError.dataNotDecoded(data, encoding: encoding)
        }
        self = try string.decodingBase64(to: encoding)
    }

    /// Decode base64 string to given `String.Encoding`.
    public init(base64 string: Self, encoding: Encoding = .utf8) throws {
        self = try string.decodingBase64(to: encoding)
    }

    func decodingBase64(to encoding: Encoding = .utf8) throws -> Self {
        // MIME wraps base64 bodies into short lines; ignore the inserted whitespace/newlines.
        guard let data: Data = Data(base64Encoded: self, options: .ignoreUnknownCharacters),
            let string: Self = Self(data: data, encoding: encoding)
        else {
            throw MIMEError.headerNotDecoded(self)
        }
        return string
    }

    /// Decode quoted-printable text.
    ///
    /// Soft line breaks (`=` before CRLF/LF) are dropped and `=XX` octets decoded, then the bytes
    /// are interpreted in `encoding` (falling back to UTF-8 / Latin-1 so a single malformed run
    /// can't lose the whole message). A bare `=` that isn't a valid escape is passed through
    /// literally rather than failing the entire decode. `_` maps to space only for RFC 2047
    /// header encoded-words (`isEncodedWord`), never in message bodies.
    func decodingQuotedPrintable(to encoding: Encoding = .utf8, isEncodedWord: Bool = false) throws -> Self {
        var source: Self = replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        if isEncodedWord {
            source = source.replacingOccurrences(of: "_", with: " ")
        }
        let characters: [Character] = Array(source)
        var bytes: [UInt8] = []
        var index: Int = 0
        while index < characters.count {
            let character: Character = characters[index]
            if character == "=", index + 2 < characters.count,
                let high: Int = characters[index + 1].hexDigitValue,
                let low: Int = characters[index + 2].hexDigitValue
            {
                bytes.append(UInt8(high << 4 | low))
                index += 3
            } else {
                bytes.append(contentsOf: Array(String(character).utf8))
                index += 1
            }
        }
        guard
            let string: Self = Self(bytes: bytes, encoding: encoding)
                ?? Self(bytes: bytes, encoding: .utf8)
                ?? Self(bytes: bytes, encoding: .isoLatin1)
        else {
            throw MIMEError.dataNotQuotedPrintable
        }
        return string
    }

    func removing(_ characters: [Character]) -> Self {
        var string: Self = "\(self)"
        for character in characters {
            string = string.replacingOccurrences(of: "\(character)", with: "")
        }
        return string
    }

    func trimmed() -> Self {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public var crlf: String { .crlf }

extension [Character] {
    static var quotes: Self { ["\"", "'"] }
}

extension ContentTransferEncoding {
    init(_ string: String) throws {
        switch string.trimmed().uppercased() {
        case "B":
            self = .base64
        case "Q":
            self = .quotedPrintable
        default:
            throw MIMEError.headerNotDecoded(string)
        }
    }
}

extension String.Encoding {

    // TODO: Use `String.Encoding.init(ianaName:)` instead, once available in 26.4 SDK
    // https://developer.apple.com/documentation/swift/string/encoding/init(iananame:)
    init(_ string: String) throws {
        switch string.trimmed().uppercased() {
        case "US-ASCII":
            self = .ascii
        case "ISO-8859-1":
            self = .isoLatin1
        case "ISO-8859-2":
            self = .isoLatin2
        case "UTF-8":
            self = .utf8
        default:
            throw MIMEError.headerNotDecoded(string)
        }
    }
}
