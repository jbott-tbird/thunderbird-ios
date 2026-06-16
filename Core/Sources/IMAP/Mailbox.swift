// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import NIOCore
import NIOIMAPCore

public typealias Mailbox = NIOIMAPCore.MailboxInfo

extension Mailbox {
    public typealias Attribute = NIOIMAPCore.MailboxInfo.Attribute
    public typealias Name = NIOIMAPCore.MailboxName
    public typealias Path = NIOIMAPCore.MailboxPath
    public typealias Status = NIOIMAPCore.MailboxStatus
}

extension Mailbox.Status {
    /// The mailbox `UIDVALIDITY` as a number, when present.
    ///
    /// NIOIMAPCore models `UIDValidity` as an opaque value with no public accessor, so the wrapped
    /// value is read reflectively. Returns `nil` if it can't be read (callers treat that as
    /// "unknown" — e.g. validity `0`). TODO: replace with a public accessor if upstreamed.
    public var uidValidityValue: UInt32? {
        guard let uidValidity else { return nil }
        return Mirror(reflecting: uidValidity).children.first { $0.label == "rawValue" }?.value as? UInt32
    }
}

extension MailboxName: @retroactive CustomStringConvertible, @retroactive ExpressibleByStringLiteral {
    public init(_ string: String) {
        self.init(ByteBuffer(string: string))
    }

    // MARK: CustomStringConvertible
    public var description: String { String(data: Data(bytes), encoding: .utf8) ?? "" }

    // MARK: ExpressibleByStringLiteral
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension MailboxPath: @retroactive CustomStringConvertible {
    public var lastPathComponent: String {
        guard let pathSeparator else {
            return name.description
        }
        return name.description.components(separatedBy: "\(pathSeparator)").last!
    }

    // MARK: CustomStringConvertible
    public var description: String { name.description }
}
