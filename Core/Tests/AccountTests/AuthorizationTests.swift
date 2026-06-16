// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

@testable import Account
import Testing
import Foundation

struct AuthorizationTests {
    @Test func user() {
        #expect(Authorization.basic(user: "user@example.com IMAP:E621E1F8", password: "").user == "user@example.com IMAP:E621E1F8")
        #expect(Authorization.oauth(user: "user@example.com IMAP:E621E1F8", token: "").user == "user@example.com IMAP:E621E1F8")
        #expect(Authorization.none.user == "")
    }

    @Test func value() {
        #expect(Authorization.basic(user: "user@example.com IMAP:E621E1F8", password: "P@$sW0rd!").value == "Basic dXNlckBleGFtcGxlLmNvbTpQQCRzVzByZCE=")
        #expect(Authorization.oauth(user: "user@example.com IMAP:E621E1F8", token: "fmu1-1e911257e86b1f194daa-0-a89faae5c11f").value == "Bearer fmu1-1e911257e86b1f194daa-0-a89faae5c11f")
        #expect(Authorization.none.value == "")
    }

    @Test func password() {
        #expect(Authorization.basic(user: "user@example.com IMAP:E621E1F8", password: "P@$sW0rd!").password == "dXNlckBleGFtcGxlLmNvbTpQQCRzVzByZCE=")
        // OAuth stores the serialized token blob; it round-trips back to the same authorization.
        let oauth: Authorization = .oauth(user: "user@example.com IMAP:E621E1F8", token: "fmu1-1e911257e86b1f194daa-0-a89faae5c11f")
        #expect(Authorization(user: "user@example.com IMAP:E621E1F8", password: oauth.password) == oauth)
        #expect(Authorization.none.password == "")
    }

    @Test func userInit() {
        #expect(Authorization(user: "user@example.com IMAP:E621E1F8", password: "dXNlckBleGFtcGxlLmNvbTpQQCRzVzByZCE=") == .basic(user: "user@example.com IMAP:E621E1F8", password: "P@$sW0rd!"))
        #expect(Authorization(user: "user@example.com IMAP:E621E1F8", password: "fmu1-1e911257e86b1f194daa-0-a89faae5c11f") == .oauth(user: "user@example.com IMAP:E621E1F8", token: "fmu1-1e911257e86b1f194daa-0-a89faae5c11f"))
    }
}
