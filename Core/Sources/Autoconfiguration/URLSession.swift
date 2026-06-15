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
    /// Exchange an OAuth2 authorization `code` for an access token.
    ///
    /// Pass the PKCE `codeVerifier` that was paired with the `code_challenge` sent on the authorization URL.
    /// Returns the bearer access token. The refresh token is decoded but not yet persisted (Phase 2).
    public func token(_ request: OAuth2.Request, code: String, codeVerifier: String? = nil) async throws -> String {
        let urlRequest: URLRequest = try .token(request, code: code, codeVerifier: codeVerifier)
        let data: (Data, URLResponse) = try await data(for: urlRequest)
        guard (data.1 as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.userAuthenticationRequired)
        }
        let response: TokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data.0)
        return response.accessToken
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int?
        let refreshToken: String?
        let tokenType: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case tokenType = "token_type"
        }
    }
}
