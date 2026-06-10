// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import AuthenticationServices
import Autoconfiguration
import SwiftUI

struct OAuthButton: View {
    let emailAddress: String

    init(_ emailAddress: String = "", token: Binding<Token?>, error: Binding<Error?>) {
        self.emailAddress = emailAddress
        _token = token
        _error = error
    }

    @Binding private var token: Token?
    @Binding private var error: Error?
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var request: OAuth2.Request?

    private func authenticate() async {
        do {
            error = nil
            guard let request else { return }
            // The web authentication callback has to match the request redirect URI.
            // Google iOS clients use the reversed client ID scheme, while other
            // providers may use the app's bundle scheme.
            guard let callbackScheme = URL(string: request.redirectURI)?.scheme else {
                throw URLError(.badURL)
            }
            let _: URL = try await webAuthenticationSession.authenticate(
                using: request.authURL(hint: emailAddress),
                callback: .customScheme(callbackScheme),
                additionalHeaderFields: [:])

            // TODO: Exchange auth code for bearer or access/refresh token; for now, succeed here and return fake bearer token...
            token = .bearer("fake-1e911257e86b1f194daa-0-a89faae5c11f")
        } catch {
            self.error = error
        }
    }

    private func configure() async {
        do {
            error = nil
            request = try await OAuth2.request(emailAddress)
        } catch {
            self.error = error
        }
    }

    // MARK: View
    var body: some View {
        Button(action: {
            Task {
                await authenticate()
            }
        }) {
            Text("account_oauth_sign_in_button")
        }
        .buttonStyle(.borderedProminent)
        .tint(.accent)
        .disabled(request == nil)
        .task {
            await configure()
        }
    }
}

#Preview("OAuth Button") {
    @Previewable @State var token: Token?
    @Previewable @State var error: Error?

    OAuthButton("example@thunderbird.net", token: $token, error: $error)
}
