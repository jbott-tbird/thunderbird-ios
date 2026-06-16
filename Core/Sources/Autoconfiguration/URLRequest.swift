// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension URLRequest {
    public static func token(_ request: OAuth2.Request, code: String, codeVerifier: String? = nil) throws -> Self {
        try postForm(url: request.tokenURL(code, codeVerifier: codeVerifier))
    }

    /// Build the `grant_type=refresh_token` POST against the token endpoint.
    public static func refresh(tokenURI: String, clientID: String, refreshToken: String) throws -> Self {
        guard var components: URLComponents = URLComponents(string: tokenURI) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: ""),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        guard let url: URL = components.url else { throw URLError(.badURL) }
        return try postForm(url: url)
    }

    /// Move a URL's query string into a `application/x-www-form-urlencoded` POST body.
    private static func postForm(url: URL) throws -> Self {
        guard
            var components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let httpBody: Data = components.percentEncodedQuery?.data(using: .utf8)
        else {
            throw URLError(.badURL)
        }
        components.queryItems = nil
        var request: Self = Self(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = httpBody
        return request
    }
}
