//
//  ReadEmailView.swift
//  Thunderbird
//
//  Created by Ashley Soucar on 10/20/25.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import WebKit
import Account
import EmailAddress

struct ReadEmailView: View {
    init(_ email: Email) {
        self.email = email
    }
    private var email: Email
    @Environment(Accounts.self) private var accounts: Accounts
    @Environment(\.modelContext) private var modelContext
    @State private var isLoadingBody = false
    @State private var draft: MessageDraft?

    /// The signed-in account's identities, used to omit self from reply-all recipients.
    private var identities: [EmailAddress] { accounts.allAccounts.first?.identities ?? [] }

    /// Fetch the full body on open (once), persist it, and mark the message read.
    private func loadBody() async {
        guard email.bodyText == nil, let account = accounts.allAccounts.first else { return }
        isLoadingBody = true
        defer { isLoadingBody = false }
        do {
            let body = try await MessageManager(account: account).fetchBody(mailbox: email.mailbox, uid: email.uid)
            email.bodyText = body.displayHTML ?? ""
            email.hasAttachments = body.hasAttachments
            email.isUnread = false
            try? modelContext.save()
        } catch {
            // Leave the body empty; the web view simply shows nothing.
        }
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(email.subject)
                        .font(.title3)
                    Spacer()
                    if email.hasAttachments {
                        Image(systemName: "paperclip").font(.caption)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading) {
                        SenderView(
                            email: email,
                            onReply: { draft = .reply(to: email) },
                            onReplyAll: { draft = .replyAll(to: email, identities: identities) },
                            onForward: { draft = .forward(email) }
                        )
                        if isLoadingBody && (email.bodyText ?? "").isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        WebView(htmlString: email.bodyText ?? "").scaledToFill()
                    }
                }

            }
            .task { await loadBody() }
            .sheet(item: $draft) { draft in
                if let account = accounts.allAccounts.first {
                    ComposeView(account: account, draft: draft)
                }
            }
            .padding()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            AlertManager.shared.showAlert = true
                            AlertManager.shared.alertTitle = "Archive"
                        }) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(.foreground)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(
                                "delete_button",
                                action: {

                                })
                            Button(
                                "archive_button",
                                action: {

                                })
                            Button(
                                "mark_read_button",
                                action: {

                                })
                            Button(
                                "mark_spam_button",
                                action: {

                                })
                            Button(
                                "flag_button",
                                action: {

                                })
                            Button(
                                "mute_button",
                                action: {

                                })
                            if email.isFlagged {
                                Button(
                                    "unpin_button",
                                    action: {

                                    })
                            } else {
                                Button(
                                    "pin_button",
                                    action: {

                                    })
                            }

                            Button(
                                "move_button",
                                action: {

                                })

                        } label: {
                            Label("options_button", systemImage: "ellipsis")
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: { draft = .reply(to: email) }) {
                            Image(systemName: "arrowshape.turn.up.left")
                                .foregroundStyle(.foreground)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: { draft = .replyAll(to: email, identities: identities) }) {
                            Image(systemName: "arrowshape.turn.up.left.2")
                                .foregroundStyle(.foreground)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: {
                            AlertManager.shared.showAlert = true
                            AlertManager.shared.alertTitle = "Trash"
                        }) {
                            Image(systemName: "trash")
                                .foregroundStyle(.foreground)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: { draft = .forward(email) }) {
                            Image(systemName: "arrowshape.turn.up.right")
                                .foregroundStyle(.foreground)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(action: {
                            AlertManager.shared.showAlert = true
                            AlertManager.shared.alertTitle = "More"
                        }) {
                            Label("options_button", systemImage: "ellipsis")
                        }
                    }
                }
        }
    }
}

struct AttachmentBlockView: View {
    init(_ attachments: [Data]) {
        self.attachments = attachments
    }
    private var attachments: [Data]
    var body: some View {
        VStack(alignment: .leading) {
            Text("^[\(attachments.count) attachment](inflect: true)")
                .font(.footnote)
            ForEach(attachments, id: \.self) { _ in
                SingleAttachment()
            }
        }

    }
}

struct SingleAttachment: View {
    init() {
        //Do Stuff
    }
    var body: some View {
        HStack {
            Image(systemName: "photo")
                .resizable()
                .frame(width: 56, height: 44)
                .foregroundStyle(.gray)
            VStack(alignment: .leading) {
                Text("rockFlying.png")
                Text("1.78 MB")
            }.font(.footnote)
        }
    }
}

struct WebView: UIViewRepresentable {
    let htmlString: String

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.responsiveDocument(htmlString), baseURL: nil)
    }

    /// Wrap message HTML in a mobile-friendly document: a `width=device-width` viewport (without it
    /// WKWebView lays out at a ~980px desktop width and shrinks everything), plus base styling that
    /// constrains images to the screen and wraps long content. Works for both full HTML emails and
    /// the plain-text `<pre>` fallback.
    static func responsiveDocument(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
          :root { color-scheme: light dark; }
          html { -webkit-text-size-adjust: 100%; }
          body { margin: 0; padding: 12px; font: -apple-system-body; line-height: 1.4; overflow-wrap: break-word; word-wrap: break-word; }
          img, video { max-width: 100%; height: auto; }
          table { max-width: 100%; }
          pre { white-space: pre-wrap; word-wrap: break-word; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

struct SenderView: View {
    init(
        email: Email,
        onReply: @escaping () -> Void = {},
        onReplyAll: @escaping () -> Void = {},
        onForward: @escaping () -> Void = {}
    ) {
        from = email.from
        sender = email.sender
        recipients = email.cc
        toText = email.to
        date = email.date
        replyTo = email.replyTo
        self.onReply = onReply
        self.onReplyAll = onReplyAll
        self.onForward = onForward
    }
    private var from: [EmailAddress]
    private var sender: [EmailAddress]
    private var replyTo: [EmailAddress]
    private var recipients: [EmailAddress]
    private var toText: [EmailAddress]
    private var date: Date
    private let onReply: () -> Void
    private let onReplyAll: () -> Void
    private let onForward: () -> Void
    @State private var showSenderRecipientInfo = false
    @State private var showEmailOptions = false

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                HStack {
                    Text(from.first?.value ?? "").font(.title3)
                }
                HStack {
                    Text("To: \(toText.first?.label ?? toText.first?.value ?? "")")
                    if recipients.count > 0 {
                        Text("+\(recipients.count)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.accent)
                .onTapGesture {
                    showSenderRecipientInfo = true
                }

            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(date, style: .date)
                    .font(.footnote)
                    .padding(.bottom, 4)
                Menu {
                    Button("reply_button", action: onReply)
                    Button("reply_all_button", action: onReplyAll)
                    Button("forward_button", action: onForward)
                    Button(
                        "forward_as_button",
                        action: {

                        })
                    Button(
                        "flag_button",
                        action: {

                        })
                    Button(
                        "delete_button",
                        action: {

                        })
                    Button(
                        "archive_button",
                        action: {

                        })
                    Button(
                        "edit_as_new_button",
                        action: {

                        })

                } label: {
                    Label("options_button", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.black)
                }
            }

        }
        .sheet(isPresented: $showSenderRecipientInfo) {
            VStack {
                Text(date.formatted(.dateTime.hour().minute().second().month(.abbreviated).day().year()))
                    .font(.caption2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding([.top, .trailing])

                List {
                    Section(header: Text("from_header")) {
                        ForEach(from) { person in
                            ContactCellView(contact: person)
                        }
                    }.listRowSeparator(.hidden)

                    if !sender.isEmpty {
                        Section(header: Text("sender_header")) {
                            ForEach(sender) { person in
                                ContactCellView(contact: person)
                            }
                        }.listRowSeparator(.hidden)
                    }
                    if !replyTo.isEmpty {
                        Section(header: Text("reply_to_header")) {
                            ForEach(replyTo) { person in
                                ContactCellView(contact: person)
                            }
                        }.listRowSeparator(.hidden)
                    }
                    Section(header: Text("to_header")) {
                        ForEach(toText) { person in
                            ContactCellView(contact: person)
                        }
                        if !recipients.isEmpty {
                            ForEach(recipients) { person in
                                ContactCellView(contact: person)
                            }
                        }
                    }.listRowSeparator(.hidden)

                }
                .listSectionSpacing(.compact)
            }
            .presentationDetents([.medium])

        }

    }
}

struct ContactCellView: View {
    let contact: EmailAddress
    init(contact: EmailAddress) {
        self.contact = contact
    }
    var body: some View {
        HStack {
            //TODO: Avatar with initials/icon
            VStack(alignment: .leading) {
                if contact.label != nil { Text(contact.label!) }
                Text(contact.value)
            }.font(.caption)
            //TODO: button for interaction
        }
    }
}
#Preview {
    let email = Email(
        subject: "This is the subject line of the email",
        from: [EmailAddress("sender1@test.com", label: "Sender1")],
        sender: [EmailAddress("sender1@test.com", label: "Sender1")],
        replyTo: [EmailAddress("sender1@test.com", label: "Sender1")],
        to: [EmailAddress("rheaThun@thundermail.com", label: "Rhea Thunderbird")],
        cc: [EmailAddress("roc@thundermail.com", label: "Roc")],
        isFlagged: true,
        bodyText: "<html><body><h2>Approval requested</h2><p>Laurel has requested an approval.</p></body></html>",
        hasAttachments: true
    )

    ReadEmailView(email)
        .environment(Accounts())
        .modelContainer(for: Email.self, inMemory: true)
}
