// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

public struct OAuth2: Decodable {
    /// Decoded response from the OAuth2 token endpoint (authorization-code exchange or refresh).
    public struct TokenResponse: Decodable, Sendable {
        public let accessToken: String
        public let expiresIn: Int?
        public let refreshToken: String?
        public let tokenType: String?

        /// Absolute expiry computed from `expires_in` relative to now, if provided.
        public func expiry(from now: Date = Date()) -> Date? {
            expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
        }

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
        }
    }

    /// Failure from the token endpoint (authorization-code exchange or refresh), carrying the
    /// HTTP status and the provider's error body so the cause is diagnosable.
    public struct TokenError: LocalizedError, Sendable {
        public let statusCode: Int
        public let body: String?

        public var errorDescription: String? {
            let detail: String = (body?.isEmpty == false) ? body! : "no response body"
            return "Sign-in failed (HTTP \(statusCode)): \(detail)"
        }
    }

    public struct Request: Equatable, Sendable {
        public let authURI: String
        public let tokenURI: String
        public let redirectURI: String
        public let responseType: String
        public let scope: [String]
        public let hosts: [String]
        public let clientID: String

        /// Build the authorization-request URL.
        ///
        /// - Parameters:
        ///   - hint: Optional email address to prepopulate the provider's account picker.
        ///   - codeChallenge: Optional PKCE `S256` challenge; pair it with the `codeVerifier` sent to ``tokenURL(_:codeVerifier:)``.
        public func authURL(hint: String? = nil, codeChallenge: String? = nil) -> URL {
            var components: URLComponents = URLComponents(string: authURI)!  // Validated during init
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: responseType),
                URLQueryItem(name: "scope", value: scope.joined(separator: " "))
            ]
            if let hint, !hint.isEmpty {  // Prepopulate email address for specific user
                components.queryItems?.append(URLQueryItem(name: "login_hint", value: hint))
            }
            if let codeChallenge, !codeChallenge.isEmpty {  // PKCE challenge for native clients (RFC 7636)
                components.queryItems?.append(URLQueryItem(name: "code_challenge", value: codeChallenge))
                components.queryItems?.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
            }
            return components.url!
        }

        /// Build the token-exchange URL for an authorization `code`.
        ///
        /// - Parameter codeVerifier: The PKCE verifier matching the challenge sent to ``authURL(hint:codeChallenge:)``.
        ///   Required for native clients, which have no client secret.
        public func tokenURL(_ code: String, codeVerifier: String? = nil) -> URL {
            var components: URLComponents = URLComponents(string: tokenURI)!  // Validated during init
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "client_secret", value: ""),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: code)
            ]
            if let codeVerifier, !codeVerifier.isEmpty {  // PKCE verifier paired with the auth-time challenge
                components.queryItems?.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
            }
            return components.url!
        }

        public func matches(_ host: String) -> Bool {
            for _host in hosts {
                guard host.hasSuffix(_host) else { continue }
                return true
            }
            return false
        }

        public init(authURI: String, tokenURI: String, redirectURI: String, responseType: String, scope: [String], clientID: String, hosts: [String] = []) throws {
            guard URL(string: authURI) != nil,
                URL(string: tokenURI) != nil,  // Validate URI strings pass failable URL init
                !redirectURI.isEmpty,
                !scope.isEmpty, !(scope.first ?? "").isEmpty,
                !clientID.isEmpty
            else {
                throw URLError(.badURL)
            }
            self.authURI = authURI
            self.tokenURI = tokenURI
            self.redirectURI = redirectURI
            self.responseType = responseType
            self.scope = scope
            self.hosts = hosts
            self.clientID = clientID
        }

        public init(_ oauth2: OAuth2, redirectURI: String, responseType: String, clientID: String) throws {
            try self.init(
                authURI: oauth2.authURL.absoluteString,
                tokenURI: oauth2.tokenURL.absoluteString,
                redirectURI: redirectURI,
                responseType: responseType,
                scope: oauth2.scope,
                clientID: clientID
            )
        }
    }

    public let authURL: URL
    public let tokenURL: URL
    public let scope: [String]
    public let issuer: String

    // MARK: Decodable
    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer = try decoder.container(keyedBy: Key.self)
        self.tokenURL = try container.decode(URL.self, forKey: .tokenURL)
        self.authURL = try container.decode(URL.self, forKey: .authURL)
        self.issuer = try container.decode(String.self, forKey: .issuer)
        self.scope = try container.decode(String.self, forKey: .scope).components(separatedBy: " ")
    }

    private enum Key: CodingKey {
        case authURL, issuer, scope, tokenURL
    }
}
