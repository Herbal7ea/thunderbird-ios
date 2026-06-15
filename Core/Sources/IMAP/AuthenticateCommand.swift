// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import NIOCore
import NIOIMAP

// Authenticate to an IMAP server using SASL XOAUTH2 (OAuth2 bearer token).
// https://developers.google.com/workspace/gmail/imap/xoauth2-protocol
struct AuthenticateCommand: IMAPCommand {
    let username: String
    let token: String

    // MARK: IMAPCommand
    typealias Result = [Capability]
    typealias Handler = CapabilityHandler

    var name: String { "authenticate XOAUTH2 \"\(username)\"" }

    func tagged(_ tag: String) -> NIOIMAPCore.TaggedCommand {
        // SASL XOAUTH2 initial response: "user=<email>^Aauth=Bearer <token>^A^A" (^A = Ctrl+A / 0x01).
        // NIOIMAP base64-encodes the InitialResponse, so the raw bytes are passed here.
        let saslString = "user=\(username)\u{01}auth=Bearer \(token)\u{01}\u{01}"
        let initialResponse = InitialResponse(ByteBuffer(string: saslString))
        return TaggedCommand(
            tag: tag,
            command: .authenticate(mechanism: AuthenticationMechanism("XOAUTH2"), initialResponse: initialResponse)
        )
    }
}
