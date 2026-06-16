// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import Account

struct ContentView: View {
    @State private var isPresented: Bool = false
    @State private var hasAuthorization: Bool = false
    @State private var outbox = Outbox()
    @Environment(Accounts.self) private var accounts: Accounts
    @Environment(\.modelContext) private var modelContext

    // MARK: View
    var body: some View {
        VStack {
            if hasAuthorization {
                EmailListView()
                    .environment(accounts)
                    .environment(outbox)

            } else {
                NavigationStack {
                    WelcomeScreen($isPresented)
                }
                .sheet(isPresented: $isPresented) {
                    ManualAccount()
                }
                .presentationDragIndicator(.visible)

            }

        }
        .onChange(of: accounts.allAccounts, initial: true) {
            guard !accounts.allAccounts.isEmpty else {
                hasAuthorization = false
                return
            }
            hasAuthorization = accounts.allAccounts.contains { account in
                account.incomingServer?.authorization != nil
                    && account.outgoingServer?.authorization != nil
            }
            isPresented = false
        }
        .task {
            // Wire up the outbox and drain anything left queued from a previous launch (Phase 7).
            outbox.configure(modelContext: modelContext, accounts: accounts)
            await outbox.processQueue()
        }
    }
}

#Preview("Content View") {
    @Previewable @State var accounts: Accounts = Accounts()

    ContentView().environment(accounts)
}
