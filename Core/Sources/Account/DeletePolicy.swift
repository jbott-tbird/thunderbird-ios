// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public enum DeletePolicy: Codable, CustomStringConvertible, Equatable, Hashable, RawRepresentable, Sendable {
    case after(days: Int = 7), onDelete, markAsRead, never

    // MARK: CustomStringConvertible
    public var description: String { rawValue }

    // MARK: RawRepresentable
    public var rawValue: String {
        switch self {
        case .after(let days): "after \(days) days"
        case .onDelete: "on delete"
        case .markAsRead: "mark as read"
        case .never: "never"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "on delete": self = .onDelete
        case "mark as read": self = .markAsRead
        case "never": self = .never
        default:
            let components: [String] = rawValue.components(separatedBy: " ")
            guard components.count == 3,
                components.first == "after",
                components.last == "days",
                let days: Int = Int(components[1]),
                days >= 0
            else {
                return nil
            }
            self = .after(days: days)
        }
    }
}
