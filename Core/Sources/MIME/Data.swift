// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension Data {

    /// Transfer-decode raw body-section bytes (as fetched over IMAP) back to their original binary
    /// content, honoring the part's ``ContentTransferEncoding``.
    ///
    /// Unlike the `String` decoders in this module, this preserves arbitrary bytes — suitable for
    /// binary attachments (images, PDFs, …). `7bit`/`8bit`/`binary` and an absent encoding pass the
    /// bytes through unchanged. A malformed run returns the original bytes rather than throwing, so
    /// the caller always gets *something* to save.
    public func transferDecoded(_ encoding: ContentTransferEncoding?) -> Data {
        switch encoding {
        case .base64:
            // MIME wraps base64 bodies into short lines; ignore the inserted whitespace/newlines.
            return Data(base64Encoded: self, options: .ignoreUnknownCharacters) ?? self
        case .quotedPrintable:
            return Self.decodingQuotedPrintable(self)
        case .ascii, .data, .binary, .none:
            return self
        }
    }

    /// Byte-accurate quoted-printable decode: drop `=`-soft line breaks and turn `=XX` escapes into
    /// their octet. A bare `=` that isn't a valid escape is passed through literally.
    private static func decodingQuotedPrintable(_ data: Data) -> Data {
        let bytes: [UInt8] = Array(data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        let equals: UInt8 = UInt8(ascii: "=")
        let cr: UInt8 = 0x0D
        let lf: UInt8 = 0x0A
        var index: Int = 0
        while index < bytes.count {
            let byte: UInt8 = bytes[index]
            guard byte == equals else {
                output.append(byte)
                index += 1
                continue
            }
            // Soft line break: "=\r\n", "=\n", or a trailing "=".
            if index + 1 < bytes.count, bytes[index + 1] == lf {
                index += 2
                continue
            }
            if index + 2 < bytes.count, bytes[index + 1] == cr, bytes[index + 2] == lf {
                index += 3
                continue
            }
            // "=XX" hex escape.
            if index + 2 < bytes.count,
                let high: UInt8 = bytes[index + 1].hexDigitValue,
                let low: UInt8 = bytes[index + 2].hexDigitValue {
                output.append(high << 4 | low)
                index += 3
                continue
            }
            // Not a valid escape; keep the literal byte.
            output.append(byte)
            index += 1
        }
        return Data(output)
    }
}

private extension UInt8 {
    var hexDigitValue: UInt8? {
        switch self {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): self - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): self - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): self - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}
