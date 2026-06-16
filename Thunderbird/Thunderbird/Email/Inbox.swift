// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import Foundation
import SwiftData

/// Loads an account's INBOX from IMAP into SwiftData and tracks load state for the UI.
///
/// The IMAP fetch runs off the main actor (returning `Sendable` ``Account/EmailData``); the upsert
/// into the model context happens here on the main actor. The list view observes the persisted
/// ``Email`` rows via `@Query`, so it updates as rows are written.
@MainActor
@Observable
final class Inbox {
    let account: Account
    private let modelContext: ModelContext

    var isLoading: Bool = false
    var errorMessage: String?

    /// Backing task for the IMAP IDLE live-update stream, if running.
    private var monitorTask: Task<Void, Never>?

    init(account: Account, modelContext: ModelContext) {
        self.account = account
        self.modelContext = modelContext
    }

    deinit { monitorTask?.cancel() }

    /// Fetch the newest `count` INBOX messages and upsert them into the store.
    func refresh(count: Int = 50) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let emails: [EmailData] = try await MessageManager(account: account).fetchInbox(count: count)
            try upsert(emails)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Start streaming live INBOX changes via IMAP IDLE, upserting pushed messages as they arrive.
    ///
    /// Idempotent: a second call while a monitor is running is a no-op. If the server doesn't support
    /// IDLE (or the connection drops for good), the stream ends quietly and the view falls back to
    /// load-on-appear and pull-to-refresh.
    func startLiveUpdates() {
        guard monitorTask == nil else { return }
        let manager = MessageManager(account: account)
        monitorTask = Task { [weak self] in
            do {
                for try await update in manager.monitorInbox() {
                    guard let self else { return }
                    switch update {
                    case .added(let emails):
                        try? self.upsert(emails)
                    case .needsReconcile:
                        await self.refresh()
                    }
                }
            } catch {
                // IDLE unsupported or the connection was lost; manual refresh remains available.
            }
            self?.monitorTask = nil
        }
    }

    /// Stop streaming live updates (e.g. when the inbox leaves the screen).
    func stopLiveUpdates() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Insert new messages or refresh the mutable fields of ones already stored. Messages removed
    /// server-side are not pruned here (full sync is a later phase).
    private func upsert(_ emails: [EmailData]) throws {
        for data in emails {
            let id: String = data.id
            var descriptor: FetchDescriptor<Email> = FetchDescriptor(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let existing: Email = try modelContext.fetch(descriptor).first {
                existing.update(from: data)
            } else {
                modelContext.insert(Email(data))
            }
        }
        try modelContext.save()
    }
}
