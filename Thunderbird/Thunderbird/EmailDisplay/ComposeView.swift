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

    @State private var to: String
    @State private var cc: String
    @State private var bcc: String
    @State private var subject: String
    @State private var html: String
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    @StateObject private var textAttributes = TextAttributes()

    /// Open the composer for `account`, optionally prefilled (e.g. a reply or forward ``MessageDraft``).
    init(account: Account, draft: MessageDraft = MessageDraft()) {
        self.account = account
        _to = State(initialValue: draft.to)
        _cc = State(initialValue: draft.cc)
        _bcc = State(initialValue: draft.bcc)
        _subject = State(initialValue: draft.subject)
        _html = State(initialValue: draft.html)
    }

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

    /// Best-effort plain-text rendering of the editor's HTML, used as the `multipart/alternative`
    /// fallback for clients that don't render HTML. Converts block/line tags to newlines and list
    /// items to bullets, strips remaining tags, and decodes the common HTML entities.
    private func plainText(fromHTML html: String) -> String {
        var text = html
        let tagReplacements: [(pattern: String, replacement: String)] = [
            ("(?i)<li[^>]*>", "\n• "),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|li|tr|h[1-6]|ul|ol|blockquote)>", "\n"),
        ]
        for (pattern, replacement) in tagReplacements {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode `&amp;` last so e.g. "&amp;lt;" doesn't collapse into "<".
        let entities: [(entity: String, character: String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let body = try MIME.Body.alternative(plainText: plainText(fromHTML: html), html: html)
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
