// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Authorization credential  for a given user name, either an OAuth token or basic password
public enum Authorization: CustomStringConvertible, Equatable {
    case basic(user: String, password: String)
    case oauth(user: String, token: Token)
    case none

    public var user: String {
        switch self {
        case .basic(let user, _), .oauth(let user, _): user
        case .none: ""
        }
    }

    /// Formatted `URLRequest` Authorization header value
    public var value: String {
        switch self {
        case .basic: "Basic \(password)"
        case .oauth(_, let token): "Bearer \(token.accessToken)"
        case .none: ""
        }
    }

    /// True when there is no usable credential (no password / no access token). Used to decide
    /// whether to store or remove a keychain entry — the serialized OAuth blob is never itself empty.
    var isEmpty: Bool {
        switch self {
        case .basic(_, let password): password.isEmpty
        case .oauth(_, let token): token.accessToken.isEmpty
        case .none: true
        }
    }

    /// Encoded `URLCredential` password value (for keychain storage). For OAuth this is the
    /// serialized ``Token`` (access + refresh + expiry), not just the access token.
    var password: String {
        switch self {
        case .basic(let user, let password): "\(user.components(separatedBy: " ")[0]):\(password)".data(using: .utf8)!.base64EncodedString()
        case .oauth(_, let token): token.serialized
        case .none: ""
        }
    }

    /// Derive appropriate authorization case from naked `URLCredential` user/password strings.
    init(user: String, password: String?) {
        let password: String = password ?? ""
        if let data: Data = Data(base64Encoded: password),
            let components: [String] = String(data: data, encoding: .utf8)?.components(separatedBy: ":"),
            components.count == 2, components.first == user.components(separatedBy: " ")[0]
        {
            self = .basic(user: user, password: components.last!)
        } else if let token: Token = Token(serialized: password) {
            self = .oauth(user: user, token: token)
        } else {
            self = .oauth(user: user, token: .bearer(password))  // Legacy bare access token
        }
    }

    // MARK: CustomStringConvertible
    public var description: String { value }
}
