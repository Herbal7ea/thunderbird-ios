// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import EmailAddress
import MIME
import SMTP
import SwiftUI

/// Compose and directly send a new message through the account's outgoing (SMTP) server.
///
/// Phase 3 scope: new messages only (reply/forward is Phase 4) and direct send with inline result
/// (the persisted outbox/queue is Phase 7).
struct ComposeView: View {
    let account: Account

    @Environment(\.dismiss) private var dismiss

    @State private var to: String = ""
    @State private var cc: String = ""
    @State private var bcc: String = ""
    @State private var subject: String = ""
    @State private var messageBody: String = ""
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    private enum Phase: Equatable {
        case editing
        case sending
    }

    /// The address mail is sent from — the account's first configured identity.
    private var sender: EmailAddress? { account.identities.first }

    private var canSend: Bool {
        phase == .editing && sender != nil && !recipients(to).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    addressField("To", text: $to)
                    addressField("Cc", text: $cc)
                    addressField("Bcc", text: $bcc)
                }
                Section {
                    TextField("Subject", text: $subject)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Message", text: $messageBody, axis: .vertical)
                        .lineLimit(8...)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(phase == .sending)
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .sending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
        }
    }

    private func addressField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField("name@example.com", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
        }
    }

    /// Split a comma-separated field into addresses, ignoring blanks.
    private func recipients(_ field: String) -> [EmailAddress] {
        field
            .split(separator: ",")
            .map { EmailAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.value.isEmpty }
    }

    private func send() async {
        guard let sender else { return }
        errorMessage = nil
        phase = .sending
        do {
            let part = try MIME.Part(data: Data(messageBody.utf8), contentType: .text(.plain, .utf8))
            let body = try MIME.Body(parts: [part], contentType: .text(.plain, .utf8))
            let email = SMTP.Email(
                sender: sender,
                recipients: recipients(to),
                copied: recipients(cc),
                blindCopied: recipients(bcc),
                subject: subject,
                body: body
            )
            try await MessageManager(account: account).send(email)
            dismiss()
        } catch {
            errorMessage = "\(error)"
            phase = .editing
        }
    }
}
