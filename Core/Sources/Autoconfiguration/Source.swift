// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

/// Autoconfig locations to query, in query order: the Thunderbird ISPDB first, then the
/// email provider's own subdomain or well-known location.
///
/// The ISPDB is queried first because major providers (Gmail, AOL, …) are curated there but do
/// not host a provider config at `autoconfig.<domain>`. Probing the provider first triggers a
/// failed DNS lookup (e.g. `autoconfig.gmail.com`) that surfaces as noisy CFNetwork errors before
/// the ISPDB ultimately resolves them. Domains absent from the ISPDB still fall through to their
/// own provider/well-known config.
public enum Source: CaseIterable, CustomStringConvertible {
    case ispDB, provider, wellKnown  // Query order

    // MARK: CustomStringConvertible
    public var description: String {
        switch self {
        case .provider: "provider"
        case .wellKnown: "provider (alternate)"
        case .ispDB: "ISPDB"
        }
    }
}
