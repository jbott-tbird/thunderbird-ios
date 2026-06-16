// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
@testable import MIME
import Testing

struct BodyTests {
    @Test func headers() throws {
        #expect(
            try Body(.aol).headers == [
                "Content-Transfer-Encoding": "quoted-printable",
                "Content-Type": "multipart/alternative; boundary=\"-=Part.d96da9.c8ced2f941b41333.19beaf8523d.267666a9a62272b=-\"",
                "MIME-Version": "1.0"
            ])  // AOL puts the MIME header at the bottom
        #expect(
            try Body(.fastmail).headers == [
                "MIME-Version": "1.0",
                "Content-Transfer-Encoding": "8bit",
                "Content-Type": "multipart/alternative; boundary=\"_----------=_17617196041979919223967\""
            ])
        #expect(
            try Body(.icloud).headers == [
                "MIME-Version": "1.0",
                "Content-Transfer-Encoding": "quoted-printable",
                "Content-Type": "multipart/alternative; boundary=\"----=_Part_15950895_843396275.1764942606546\""
            ])
        #expect(
            try Body(.outlook).headers == [
                "MIME-Version": "1.0",
                "Content-Type": "multipart/alternative; boundary=\"b1_dd99cd789bcc10ebb82bcc39304a9664\""
            ])
        #expect(
            try Body(.posteo).headers == [
                "MIME-Version": "1.0",
                "Content-Type": "multipart/alternative; boundary=\"MULTIPART-MIXED-BOUNDARY\""
            ])
    }

    @Test func descriptionInit() throws {
        let aol: Body = try Body(.aol)
        #expect(aol.contentType == .multipart(.alternative, try! Boundary("-=Part.d96da9.c8ced2f941b41333.19beaf8523d.267666a9a62272b=-")))
        #expect(aol.contentTransferEncoding == .quotedPrintable)
        #expect(aol.parts.first?.contentType == .text(.html, .utf8))
        #expect(aol.parts.count == 1)
        let fastmail: Body = try Body(.fastmail)
        #expect(fastmail.contentType == .multipart(.alternative, try! Boundary("_----------=_17617196041979919223967")))
        #expect(fastmail.contentTransferEncoding == .data)
        #expect(fastmail.parts.first?.contentType == .text(.plain, .utf8))
        #expect(fastmail.parts.count == 2)
        let icloud: Body = try Body(.icloud)
        #expect(icloud.contentType == .multipart(.alternative, try! Boundary("----=_Part_15950895_843396275.1764942606546")))
        #expect(icloud.contentTransferEncoding == .quotedPrintable)
        #expect(icloud.parts.first?.contentType == .text(.html, .iso8859))
        #expect(icloud.parts.count == 1)
        let outlook: Body = try Body(.outlook)
        #expect(outlook.contentType == .multipart(.alternative, try! Boundary("b1_dd99cd789bcc10ebb82bcc39304a9664")))
        #expect(outlook.contentTransferEncoding == nil)
        #expect(outlook.parts.first?.contentType == .text(.plain, .utf8))
        #expect(outlook.parts.count == 2)
        let posteo: Body = try Body(.posteo)
        #expect(posteo.contentType == .multipart(.alternative, try! Boundary("MULTIPART-MIXED-BOUNDARY")))
        #expect(posteo.contentTransferEncoding == nil)
        #expect(posteo.parts.first?.contentType == .text(.html, .utf8))
        #expect(posteo.parts.count == 2)
    }

    // MARK: RawRepresentable
    @Test func rawValue() throws {
        #expect(try Body(.aol).rawValue.count == 4878)
        #expect(try Body(.fastmail).rawValue.count == 20530)
        #expect(try Body(.icloud).rawValue.count == 8852)
        #expect(try Body(.outlook).rawValue.count == 69556)
        #expect(try Body(.posteo).rawValue.count == 89893)
    }
}

extension BodyTests {
    @Test func empty() {
        #expect(Body.empty.parts.first?.data == "".data(using: .ascii)!)
        #expect(Body.empty.parts.first?.contentType == .text(.plain, .ascii))
        #expect(Body.empty.contentType == .text(.plain, .ascii))
    }

    @Test func isEmpty() throws {
        #expect(try Body(.aol).isEmpty == false)
        #expect(try Body(.fastmail).isEmpty == false)
        #expect(try Body(.icloud).isEmpty == false)
        #expect(try Body(.outlook).isEmpty == false)
        #expect(try Body(.posteo).isEmpty == false)
        #expect(Body.empty.isEmpty == true)
    }

    @Test func alternative() throws {
        let body: Body = try .alternative(plainText: "Hello, world", html: "<p>Hello, <b>world</b></p>")
        #expect(body.contentType.isMultipart)
        #expect(body.contentType.subtype == "alternative")
        #expect(body.parts.count == 2)
        // Plain text first, HTML last (least- to most-faithful per RFC 2046).
        #expect(body.parts[0].contentType == .text(.plain, .utf8))
        #expect(body.parts[1].contentType == .text(.html, .utf8))
        #expect(String(data: body.parts[0].data, encoding: .utf8) == "Hello, world")
        #expect(String(data: body.parts[1].data, encoding: .utf8) == "<p>Hello, <b>world</b></p>")
        // Round-trips: the serialized body parses back into two alternative parts.
        let parsed: Body = try Body(body.rawValue)
        #expect(parsed.contentType.subtype == "alternative")
        #expect(parsed.parts.count == 2)
    }
}

private extension Data {
    static var aol: Self { try! Bundle.module.data(forResource: "mime-body-aol.eml") }
    static var fastmail: Self { try! Bundle.module.data(forResource: "mime-body-fastmail.eml") }
    static var icloud: Self { try! Bundle.module.data(forResource: "mime-body-icloud.eml") }
    static var outlook: Self { try! Bundle.module.data(forResource: "mime-body-outlook.eml") }
    static var posteo: Self { try! Bundle.module.data(forResource: "mime-body-posteo.eml") }
}
