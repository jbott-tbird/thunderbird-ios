// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
@testable import MIME
import Testing

struct DataTests {
    @Test func base64TransferDecode() {
        #expect(Data("aGVsbG8=".utf8).transferDecoded(.base64) == Data("hello".utf8))
    }

    @Test func base64IgnoresLineWraps() {
        // MIME wraps base64 bodies into short lines; the decode must ignore the inserted newlines.
        #expect(Data("aGVs\r\nbG8=".utf8).transferDecoded(.base64) == Data("hello".utf8))
    }

    @Test func quotedPrintableTransferDecode() {
        // "=3D" → "=", and the trailing "=\r\n" is a soft line break that is dropped.
        #expect(Data("a=3Db=\r\nc".utf8).transferDecoded(.quotedPrintable) == Data("a=bc".utf8))
    }

    @Test func passthroughEncodingsAndNil() {
        #expect(Data("plain".utf8).transferDecoded(.ascii) == Data("plain".utf8))
        #expect(Data("plain".utf8).transferDecoded(.data) == Data("plain".utf8))
        #expect(Data("plain".utf8).transferDecoded(nil) == Data("plain".utf8))
    }
}
