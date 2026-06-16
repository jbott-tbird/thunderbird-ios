// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import NIOCore
@testable import SMTP
import Testing

struct RequestEncoderTests {
    @Test func encode() throws {
        var buffer: ByteBuffer = ByteBuffer()
        try RequestEncoder().encode(data: .hello("smtp.example.com"), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "EHLO smtp.example.com\r\n")
        try RequestEncoder().encode(data: .startTLS, out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "STARTTLS\r\n")
        try RequestEncoder().encode(data: .authLogin, out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "AUTH LOGIN\r\n")
        try RequestEncoder().encode(data: .authXOAuth2(username: "user@example.com", token: "ya29.token"), out: &buffer)
        // base64("user=user@example.com\u{01}auth=Bearer ya29.token\u{01}\u{01}")
        #expect(
            buffer.readString(length: buffer.readableBytes)
                == "AUTH XOAUTH2 dXNlcj11c2VyQGV4YW1wbGUuY29tAWF1dGg9QmVhcmVyIHlhMjkudG9rZW4BAQ==\r\n")
        try RequestEncoder().encode(data: .authUser("user@example.com"), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "dXNlckBleGFtcGxlLmNvbQ==\r\n")
        try RequestEncoder().encode(data: .authPassword("P@s$W0rd"), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "UEBzJFcwcmQ=\r\n")
        try RequestEncoder().encode(data: .mailFrom("Sender Name <sender@example.com>"), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "MAIL FROM:<sender@example.com>\r\n")
        try RequestEncoder().encode(data: .recipient("Recipient Name <recipient@example.com>"), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "RCPT TO:<recipient@example.com>\r\n")
        try RequestEncoder().encode(data: .data, out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "DATA\r\n")
        try RequestEncoder().encode(data: .transferData(.example), out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == example)
        try RequestEncoder().encode(data: .quit, out: &buffer)
        #expect(buffer.readString(length: buffer.readableBytes) == "QUIT\r\n")
    }
}

// swift-format-ignore
private let example: String = """
From: Sender Name <sender@example.com>\r
To: Recipient Name <recipient@example.com> no.name@exmaple.com\r
Date: Thu, 06 Nov 2025 21:05:50 +0000\r
Message-ID: <1762463150.A51D5B17@example.com>\r
Subject: Example email subject\r
Content-Type: text/plain; charset="US-ASCII"\r
\r
Plain text body content (using only US-ASCII characters)\r
\r
.\r

"""
