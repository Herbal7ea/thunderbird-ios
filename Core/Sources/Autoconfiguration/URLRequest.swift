// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

extension URLRequest {
    public static func token(_ request: OAuth2.Request, code: String, codeVerifier: String? = nil) throws -> Self {
        guard
            var components: URLComponents = URLComponents(
                url: request.tokenURL(code, codeVerifier: codeVerifier),
                resolvingAgainstBaseURL: false
            ), let httpBody: Data = components.percentEncodedQuery?.data(using: .utf8)
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
