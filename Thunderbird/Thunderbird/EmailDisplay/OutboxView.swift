// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftData
import SwiftUI

/// Shows messages still waiting to send (or that failed), with manual retry / delete.
struct OutboxView: View {
    @Environment(Outbox.self) private var outbox
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OutgoingEmail.createdAt, order: .reverse) private var messages: [OutgoingEmail]

    var body: some View {
        NavigationStack {
            Group {
                if messages.isEmpty {
                    ContentUnavailableView(
                        "Outbox Empty",
                        systemImage: "tray",
                        description: Text("Messages waiting to send appear here."))
                } else {
                    List {
                        ForEach(messages) { message in
                            row(message)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        outbox.delete(message)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        outbox.retry(message)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Outbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ message: OutgoingEmail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.subject.isEmpty ? String(localized: "(No subject)") : message.subject)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                statusBadge(message)
            }
            Text("To: \(message.recipientSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let lastError = message.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusBadge(_ message: OutgoingEmail) -> some View {
        switch message.status {
        case .queued:
            Label("Queued", systemImage: "clock").labelStyle(.titleAndIcon).font(.caption2).foregroundStyle(.secondary)
        case .sending:
            HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("Sending").font(.caption2) }
        case .failed:
            let exhausted = message.attemptCount >= Outbox.maxAttempts
            Label(exhausted ? "Failed" : "Retrying", systemImage: exhausted ? "exclamationmark.triangle" : "arrow.clockwise")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(exhausted ? .red : .orange)
        }
    }
}
