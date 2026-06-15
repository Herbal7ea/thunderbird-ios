// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import EmailAddress
import InfomaniakRichHTMLEditor
import MIME
import SMTP
import SwiftUI

/// Compose and directly send a new message through the account's outgoing (SMTP) server.
///
/// The body is edited with Infomaniak's `RichHTMLEditor` and sent as `text/html`.
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
    @State private var html: String = ""
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    @StateObject private var textAttributes = TextAttributes()

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
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    addressField("To", text: $to)
                    Divider()
                    addressField("Cc", text: $cc)
                    Divider()
                    addressField("Bcc", text: $bcc)
                    Divider()
                    HStack {
                        Text("Subject")
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .leading)
                        TextField("Subject", text: $subject)
                            .autocorrectionDisabled()
                    }
                    .padding(.vertical, 10)
                    Divider()
                }
                .padding(.horizontal)

                RichHTMLEditor(html: $html, textAttributes: textAttributes)
                    .editorScrollable(true)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                Divider()
                formatBar
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

    /// A persistent formatting bar; each button reflects and toggles the current selection's style.
    private var formatBar: some View {
        HStack(spacing: 22) {
            formatButton("bold", isActive: textAttributes.hasBold) { textAttributes.bold() }
            formatButton("italic", isActive: textAttributes.hasItalic) { textAttributes.italic() }
            formatButton("underline", isActive: textAttributes.hasUnderline) { textAttributes.underline() }
            formatButton("strikethrough", isActive: textAttributes.hasStrikethrough) { textAttributes.strikethrough() }
            formatButton("list.bullet", isActive: textAttributes.hasUnorderedList) { textAttributes.unorderedList() }
            formatButton("list.number", isActive: textAttributes.hasOrderedList) { textAttributes.orderedList() }
        }
        .font(.body)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func formatButton(_ systemImage: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func addressField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField("name@example.com", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
        }
        .padding(.vertical, 10)
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
            let part = try MIME.Part(data: Data(html.utf8), contentType: .text(.html, .utf8))
            let body = try MIME.Body(parts: [part], contentType: .text(.html, .utf8))
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
