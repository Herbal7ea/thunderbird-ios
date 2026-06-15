// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import Foundation
import SwiftData

/// Persisted message, keyed by account + mailbox + UID validity + UID.
///
/// Built and updated from a ``Account/EmailData`` snapshot (mapped off the IMAP fetch). Envelope
/// fields are populated immediately; `bodyText` / `hasAttachments` are filled lazily when a message
/// is opened (Milestone E).
@Model
final class Email {
    /// Stable identity (`EmailData.id`); unique so re-fetching a message upserts rather than duplicates.
    @Attribute(.unique) var id: String
    var accountID: UUID
    var mailbox: String
    var uid: Int
    var uidValidity: Int

    var subject: String
    var from: [EmailAddress]
    var sender: [EmailAddress]
    var replyTo: [EmailAddress]
    var to: [EmailAddress]
    var cc: [EmailAddress]
    var bcc: [EmailAddress]
    var date: Date
    var isUnread: Bool
    var isFlagged: Bool
    var threadID: String?
    var messageID: String?

    // Populated lazily when the message is opened (Milestone E).
    var bodyText: String?
    var hasAttachments: Bool

    /// True when the message belongs to a conversation/thread.
    var isThread: Bool { threadID != nil }

    init(_ data: EmailData) {
        self.id = data.id
        self.accountID = data.accountID
        self.mailbox = data.mailbox
        self.uid = data.uid
        self.uidValidity = data.uidValidity
        self.subject = data.subject
        self.from = data.from
        self.sender = data.sender
        self.replyTo = data.replyTo
        self.to = data.to
        self.cc = data.cc
        self.bcc = data.bcc
        self.date = data.date
        self.isUnread = data.isUnread
        self.isFlagged = data.isFlagged
        self.threadID = data.threadID
        self.messageID = data.messageID
        self.bodyText = nil
        self.hasAttachments = false
    }

    /// Refresh server-mutable envelope fields from a newer fetch. Identity and the lazily fetched
    /// body are left untouched.
    func update(from data: EmailData) {
        subject = data.subject
        from = data.from
        sender = data.sender
        replyTo = data.replyTo
        to = data.to
        cc = data.cc
        bcc = data.bcc
        date = data.date
        isUnread = data.isUnread
        isFlagged = data.isFlagged
        threadID = data.threadID
        messageID = data.messageID
    }
}
