// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import SwiftData
import SwiftUI

@main
struct App: SwiftUI.App {
    @State private var accounts: Accounts = Accounts()
    @State private var showAlert = false
    @State private var featureFlags: FeatureFlags = FeatureFlags(distribution: .current)

    // MARK: App
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(accounts).environment(featureFlags)
                if showAlert {
                    FeatureNotImplementedView()
                }
            }
        }
        .modelContainer(for: [Email.self, OutgoingEmail.self])
        .onChange(of: AlertManager.shared.showAlert) {
            showAlert = AlertManager.shared.showAlert
        }
        #if os(macOS)
        .defaultSize(width: 768.0, height: 512.0)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
