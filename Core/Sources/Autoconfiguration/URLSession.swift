// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension URLSession {
    /// Query multiple autoconfig sources for a given email address.
    public func autoconfig(_ emailAddress: String, sources: [Source] = Source.allCases, queryMX: Bool = true) async throws -> (config: ClientConfig, source: Source) {
        for source in sources {
            guard let config: ClientConfig = try? await autoconfig(emailAddress, source: source).config else { continue }
            return (config, source)
        }
        guard queryMX else {
            throw URLError(.fileDoesNotExist)
        }
        let records: [MXRecord] = try await DNSResolver.queryMX(emailAddress)
        guard let host: String = records.first?.host else {
            throw URLError(.unsupportedURL)
        }
        let domain: String = try await domain(host: host)
        return try await autoconfig(domain, sources: sources, queryMX: false)
    }

    /// Query a single autoconfig source using  a given email address.
    public func autoconfig(_ emailAddress: String, source: Source) async throws -> (config: ClientConfig, data: (Data, Data)) {
        let url: URL = try .autoconfig(emailAddress, source: source)
        let data: (Data, URLResponse) = try await data(from: url)
        switch (data.1 as? HTTPURLResponse)?.statusCode {
        case 200:
            let json: Data = try XMLToJSONParser(emailAddress, data: data.0).data
            let container: Container = try JSONDecoder().decode(Container.self, from: json)
            return (container.clientConfig, (json, data.0))
        case 404:
            throw URLError(.fileDoesNotExist)
        default:
            throw URLError(.unsupportedURL)
        }
    }

    private struct Container: Decodable {
        let clientConfig: ClientConfig
    }
}

extension URLSession {
    /// Derive domain name from a give host name using the [Public Suffix List.](https://publicsuffix.org)
    public func domain(host: String) async throws -> String {
        let suffixList: [String] = try await suffixList()
        let parser: DomainParser = try DomainParser(host: host, suffixList: suffixList)
        return parser.domain
    }

    func suffixList() async throws -> [String] {
        let data: (Data, URLResponse) = try await data(from: .suffixList)
        let suffixList: [String] = try SuffixListParser(data: data.0).suffixList
        return suffixList
    }
}

extension URLSession {
    /// Exchange an OAuth2 authorization `code` for tokens.
    ///
    /// Pass the PKCE `codeVerifier` that was paired with the `code_challenge` sent on the authorization URL.
    public func token(_ request: OAuth2.Request, code: String, codeVerifier: String? = nil) async throws -> OAuth2.TokenResponse {
        try await exchange(.token(request, code: code, codeVerifier: codeVerifier))
    }

    /// Exchange a refresh token for a fresh access token.
    ///
    /// Refresh responses typically omit a new `refresh_token`; reuse the existing one when absent.
    public func refreshToken(tokenURI: String, clientID: String, refreshToken: String) async throws -> OAuth2.TokenResponse {
        try await exchange(.refresh(tokenURI: tokenURI, clientID: clientID, refreshToken: refreshToken))
    }

    private func exchange(_ urlRequest: URLRequest) async throws -> OAuth2.TokenResponse {
        let data: (Data, URLResponse) = try await data(for: urlRequest)
        let statusCode: Int = (data.1 as? HTTPURLResponse)?.statusCode ?? -1
        guard statusCode == 200 else {
            // Preserve the provider's error body (e.g. `invalid_grant`, `redirect_uri_mismatch`)
            // so token-exchange failures are diagnosable rather than a generic auth error.
            throw OAuth2.TokenError(statusCode: statusCode, body: String(data: data.0, encoding: .utf8))
        }
        return try JSONDecoder().decode(OAuth2.TokenResponse.self, from: data.0)
    }
}
