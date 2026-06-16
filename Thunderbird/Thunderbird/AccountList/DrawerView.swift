//
//  Drawer.swift
//  Thunderbird
//
//  Created by Ashley Soucar on 4/10/26.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import SwiftUI

struct DrawerView: View {
    @Environment(Accounts.self) private var accounts: Accounts
    @Binding var showDrawer: Bool
    @Binding var selectedAccountID: String

    // MARK: View
    var body: some View {

        ZStack {
            if showDrawer {
                Button {
                    showDrawer.toggle()
                } label: {
                    Rectangle()
                        .fill(Color.primary.opacity(0.3))
                        .ignoresSafeArea()
                }
                .accessibilityLabel("dismiss")

                HStack {
                    VStack(alignment: .leading) {
                        ScrollView {
                            DrawerContent(showDrawer: $showDrawer, selectedAccountID: $selectedAccountID)
                        }
                        Spacer()
                        NavigationLink(destination: GeneralSettingsView()) {
                            Label("settings_header", systemImage: "gearshape")
                                .foregroundStyle(.black)
                        }
                    }
                    .padding()
                    .background()
                    Spacer()
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut, value: showDrawer)
        .toolbar(showDrawer ? .hidden : .visible, for: .navigationBar)
    }
}

#Preview("Account Drawer") {
    @Previewable @State var accounts: Accounts = Accounts()
    @Previewable @State var showDrawer: Bool = true
    @Previewable @State var selectedAccountID: String = ""
    DrawerView(showDrawer: $showDrawer, selectedAccountID: $selectedAccountID).environment(accounts)
}

//TODO: Connect to actual account and folder structure
struct DrawerContent: View {
    @Environment(Accounts.self) private var accounts: Accounts
    @Binding var showDrawer: Bool
    @Binding var selectedAccountID: String

    /// Whether `account` is the one currently being viewed (empty selection defaults to the first).
    private func isSelected(_ account: Account) -> Bool {
        if selectedAccountID == account.id.uuidString { return true }
        return selectedAccountID.isEmpty && account.id == accounts.allAccounts.first?.id
    }

    var body: some View {
        VStack(alignment: .leading) {
            if accounts.allAccounts.count > 1 {
                Text("Accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(accounts.allAccounts) { account in
                    Button {
                        selectedAccountID = account.id.uuidString
                        showDrawer = false
                    } label: {
                        HStack {
                            Image(systemName: isSelected(account) ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(.accent)
                            Text(account.name)
                                .fontWeight(isSelected(account) ? .semibold : .regular)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                Divider()
            }
            MailboxDropdownRowView(mailboxName: "Inbox", iconName: "tray")
            MailboxDropdownRowView(mailboxName: "Sent", iconName: "paperplane")
            Divider()
            Text("Account Folders")
            ForEach(accounts.allAccounts) { account in
                AccountFolderDisclosureView(account: account)
            }

        }
    }
}

//TODO: Remove when account color association happens
//we will associate a color with an account but don't yet
extension Color {
    static var random: Color {
        return Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1)
        )
    }
}
