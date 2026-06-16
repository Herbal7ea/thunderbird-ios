// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// Fetch and send messages for a given `Account`.
///
/// A lightweight, `Sendable` service over an immutable `Account` — its methods can be called from
/// any actor (e.g. a `@MainActor` view model awaiting an off-actor IMAP/SMTP operation).
public final class MessageManager: Sendable {
    public let account: Account

    public init(account: Account) {
        self.account = account
    }

    /// Fetch the most recent `count` messages from INBOX as `Sendable` ``EmailData`` snapshots,
    /// newest first.
    ///
    /// Connects (authenticating via XOAUTH2 for OAuth2 accounts), selects INBOX, and fetches the
    /// highest `count` sequence numbers at the envelope level. Returns an empty array for non-IMAP
    /// accounts or an empty/absent INBOX.
    public func fetchInbox(count: Int = 50) async throws -> [EmailData] {
        guard account.emailProtocol == .imap else { return [] }
        let client: IMAPClient = try await account.imapClient
        let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
        guard let inbox: IMAP.Mailbox = mailboxes.first(where: {
            $0.0.path.name.description.uppercased() == "INBOX"
        })?.0 else {
            return []
        }
        let mailboxName: String = inbox.path.name.description
        let status: IMAP.Mailbox.Status = try await client.select(mailbox: inbox)
        let total: Int = status.messageCount ?? 0
        let uidValidity: Int = Int(status.uidValidityValue ?? 0)
        guard total > 0 else { return [] }
        let set = SequenceSet(max(1, total - count + 1)...total)
        let messages: MessageSet = try await client.fetch(set, attributes: .standard)
        return messages
            .sorted { $0.key > $1.key }  // Newest (highest sequence number) first
            .map { EmailData(accountID: account.id, mailbox: mailboxName, uidValidity: uidValidity, message: $0.value) }
    }

    /// Fetch and extract the full body (HTML/plain text + attachment metadata) of a message by UID,
    /// optionally marking it `\Seen`.
    ///
    /// Selects `mailbox`, fetches the complete message for `uid`, and walks its MIME tree.
    public func fetchBody(mailbox: String, uid: Int, markSeen: Bool = true) async throws -> MessageBody {
        guard account.emailProtocol == .imap else {
            return MessageBody(html: nil, plainText: nil, attachments: [])
        }
        let client: IMAPClient = try await account.imapClient
        let mailboxes: [(IMAP.Mailbox, IMAP.Mailbox.Status?)] = try await client.list()
        guard let target: IMAP.Mailbox = mailboxes.first(where: { $0.0.path.name.description == mailbox })?.0 else {
            throw IMAPError.commandFailed("Mailbox \(mailbox) not found")
        }
        try await client.select(mailbox: target)
        let imapUID = UID(rawValue: UInt32(uid))
        let message: Message = try await client.fetch(uid: imapUID, attributes: .complete)
        if markSeen {
            try? await client.markSeen(uid: imapUID)
        }
        return MessageBody(message)
    }

    /// Send a composed message through the account's outgoing (SMTP) server.
    ///
    /// Refreshes the outgoing OAuth token if it is near expiry, then connects and sends over SMTP
    /// `XOAUTH2` (or `AUTH LOGIN` for password accounts). A non-expired token that the server still
    /// rejects triggers one forced refresh + retry, mirroring ``Account/imapClient``.
    public func send(_ email: SMTP.Email) async throws {
        guard account.emailProtocol == .imap, let outgoingServer = account.outgoingServer else {
            throw SMTPError.serverProtocolMismatch
        }
        try await account.refreshOutgoingTokenIfNeeded()
        do {
            try await SMTPClient(try SMTP.Server(account.outgoingServer ?? outgoingServer)).send(email)
        } catch SMTPError.authenticationFailed {
            guard try await account.refreshOutgoingTokenIfNeeded(force: true) else {
                throw SMTPError.authenticationFailed
            }
            try await SMTPClient(try SMTP.Server(account.outgoingServer ?? outgoingServer)).send(email)
        }
    }

    /// Diagnostic: print the subjects of the most recent `count` INBOX messages (temporary, until
    /// the inbox list view is wired in Milestone D).
    public func printTopSubjects(_ count: Int = 10) async {
        do {
            let emails: [EmailData] = try await fetchInbox(count: count)
            print("OAuth: top \(emails.count) INBOX subjects ↓")
            for email in emails {
                print("  • \(email.subject.isEmpty ? "(no subject)" : email.subject)")
            }
        } catch {
            print("OAuth fetch error: \(error)")
        }
    }
}
