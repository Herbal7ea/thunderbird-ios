//
//  EmailListView.swift
//  Thunderbird
//
//  Created by Ashley Soucar on 10/20/25.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import SwiftData
import Account

struct EmailListView: View {
    @Environment(Accounts.self) private var accounts: Accounts
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Email.date, order: .reverse) private var emails: [Email]
    @State private var inbox: Inbox?
    @State var editMode: EditMode = .inactive
    @State private var selections = Set<String>()
    @State private var showDrawer = false
    @State private var showCompose = false

    func sortEmails() {
        //Not yet implemented
        AlertManager.shared.showAlert = true
        AlertManager.shared.alertTitle = "Sort Emails"
    }

    func selectAll() {
        selections = Set(emails.map(\.id))
    }

    //TODO: also store \Seen on the server (Phase 3)
    func markAllRead() {
        for email in emails {
            email.isUnread = false
        }
        try? modelContext.save()
    }

    private func loadInbox() async {
        if inbox == nil, let account = accounts.allAccounts.first {
            inbox = Inbox(account: account, modelContext: modelContext)
        }
        await inbox?.refresh()
        inbox?.startLiveUpdates()  // Push new mail in real time via IMAP IDLE (Phase 5)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                if emails.isEmpty {
                    if inbox?.isLoading == true {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack {
                            Text("empty_inbox")
                                .padding(.bottom, 5)
                            Text("new_messages_will_appear")
                                .padding(.bottom, 10)
                            if let errorMessage = inbox?.errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            Button {
                                //Do Nothing
                            } label: {
                                Text("add_another_account")
                            }.buttonBorderShape(.capsule)
                                .buttonStyle(.bordered)
                                .foregroundStyle(.black)
                            Spacer()
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack {
                        List(emails, id: \.id, selection: $selections) { email in
                            NavigationLink {
                                ReadEmailView(email)
                            } label: {
                                EmailCellView(email: email)
                            }
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                LongPressGesture().onEnded { _ in
                                    withAnimation {
                                        editMode = .active
                                    }
                                }
                            )
                            .listRowSeparator(.hidden)
                            .navigationLinkIndicatorVisibility(.hidden)
                        }
                        .refreshable {
                            await inbox?.refresh()
                        }
                    }.environment(\.editMode, $editMode)
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                }
                Button {
                    showCompose = true
                } label: {
                    Image("compose")
                        .font(.title.weight(.regular))
                        .padding(.all, 12)
                        .padding(.leading, 5)
                        .background(Color(white: 0.9))
                        .foregroundColor(.muted)
                        .clipShape(Circle())
                }
                .background(.clear)
                .padding()
                .disabled(accounts.allAccounts.first == nil)
                DrawerView(showDrawer: $showDrawer)
            }
            .navigationTitle("inbox_header")
            .navigationBarBackButtonHidden(editMode.isEditing)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDrawer = true
                    } label: {
                        Label("Account", systemImage: "line.3.horizontal").labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    if editMode.isEditing == true {
                        Button(
                            "close_button", systemImage: "xmark",
                            action: {
                                withAnimation {
                                    editMode = .inactive
                                }
                            })
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(
                            "date_sort_button",
                            action: {
                                sortEmails()
                            })
                        Button(
                            "read_status_sort_button",
                            action: {
                                sortEmails()
                            })
                        Button(
                            "has_attachments_sort_button",
                            action: {
                                sortEmails()
                            })
                    } label: {
                        Label("sort_button", systemImage: "line.3.horizontal.decrease", )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(
                            editMode.isEditing ? "done_button" : "select_all_button",
                            action: {
                                withAnimation {
                                    editMode = editMode.isEditing ? .inactive : .active
                                }
                                selectAll()
                            })
                        Button(
                            "mark_all_read_button",
                            action: {
                                markAllRead()
                            })
                        Button(
                            "account_sign_out_button",
                            action: {
                                accounts.deleteAccounts()
                            })
                    } label: {
                        Label("options_button", systemImage: "ellipsis")
                    }
                }
            }
            .task {
                await loadInbox()
            }
            .sheet(isPresented: $showCompose) {
                if let account = accounts.allAccounts.first {
                    ComposeView(account: account)
                }
            }
        }
    }
}

#Preview("Email List") {
    @Previewable @State var flags: FeatureFlags = FeatureFlags(distribution: .current)
    @Previewable @State var accounts: Accounts = Accounts()
    EmailListView()
        .environment(flags)
        .environment(accounts)
        .modelContainer(for: Email.self, inMemory: true)
}
