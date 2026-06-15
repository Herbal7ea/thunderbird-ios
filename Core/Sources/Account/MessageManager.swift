// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Fetch and display messages for a given `Account`.
@Observable
public final class MessageManager {
    public let account: Account
    public var error: AccountError?

    public init(account: Account) {
        self.account = account
    }

    /// Phase 1 diagnostic: print the subjects of the most recent `count` messages in INBOX.
    ///
    /// Connects (authenticating via XOAUTH2 for OAuth2 accounts), selects INBOX, fetches the
    /// highest `count` sequence numbers, and prints each subject newest-first.
    public func printTopSubjects(_ count: Int = 10) async {
        do {
            guard account.emailProtocol == .imap else {
                print("OAuth Phase 1: only IMAP is supported in this phase")
                return
            }
            let client: IMAPClient = try await account.imapClient
            let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
            guard let inbox: IMAP.Mailbox = mailboxes.first(where: {
                $0.0.path.name.description.uppercased() == "INBOX"
            })?.0 else {
                print("OAuth Phase 1: INBOX not found")
                return
            }
            let status: IMAP.Mailbox.Status = try await client.select(mailbox: inbox)
            let total: Int = status.messageCount ?? 0
            guard total > 0 else {
                print("OAuth Phase 1: INBOX is empty")
                return
            }
            let set = SequenceSet(max(1, total - count + 1)...total)
            let messages: MessageSet = try await client.fetch(set, attributes: .standard)
            print("OAuth Phase 1: top \(messages.count) INBOX subjects ↓")
            for number in messages.keys.sorted(by: >) {
                print("  • \(messages[number]?.envelope.subject ?? "(no subject)")")
            }
        } catch {
            self.error = AccountError(error)
            print("OAuth Phase 1 error: \(error)")
        }
    }
}
