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
    var isLoadingMore: Bool = false
    /// False once paging has reached the oldest message; drives the "load more" trigger.
    var hasMore: Bool = true
    var errorMessage: String?

    /// How many newest messages have been loaded, so pagination knows where to continue.
    private var loadedCount: Int = 0
    private let pageSize: Int = 50

    /// Backing task for the IMAP IDLE live-update stream, if running.
    private var monitorTask: Task<Void, Never>?

    init(account: Account, modelContext: ModelContext) {
        self.account = account
        self.modelContext = modelContext
    }

    deinit { monitorTask?.cancel() }

    /// Reload the newest page of INBOX: upsert it, then prune messages deleted server-side.
    func refresh(count: Int = 50) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let emails: [EmailData] = try await MessageManager(account: account).fetchInbox(count: count)
            try upsert(emails)
            // The newest page contains every message at or above its lowest UID, so anything stored
            // in that range but missing from the page was deleted on the server — prune it.
            try prune(against: emails, openTop: true)
            loadedCount = max(loadedCount, emails.count)
            hasMore = emails.count >= count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch the next older page of messages (pagination beyond the newest page).
    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let older: [EmailData] = try await MessageManager(account: account)
                .fetchInbox(count: pageSize, olderThan: loadedCount)
            guard !older.isEmpty else { hasMore = false; return }
            try upsert(older)
            try prune(against: older, openTop: false)  // This page is a closed UID window
            loadedCount += older.count
            if older.count < pageSize { hasMore = false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mark a message read/unread locally and push `\Seen` to the server (two-way reconciliation).
    func setRead(_ email: Email, _ read: Bool) {
        guard email.isUnread == read else { return }
        email.isUnread = !read
        try? modelContext.save()
        let mailbox = email.mailbox, uid = email.uid
        Task { try? await MessageManager(account: account).markSeen(mailbox: mailbox, uid: uid, read) }
    }

    /// Toggle a message's flag locally and push `\Flagged` to the server (two-way reconciliation).
    func setFlagged(_ email: Email, _ flagged: Bool) {
        guard email.isFlagged != flagged else { return }
        email.isFlagged = flagged
        try? modelContext.save()
        let mailbox = email.mailbox, uid = email.uid
        Task { try? await MessageManager(account: account).markFlagged(mailbox: mailbox, uid: uid, flagged) }
    }

    /// Mark a batch of messages read locally and push `\Seen` for each to the server.
    func markAllRead(_ emails: [Email]) {
        let unread = emails.filter(\.isUnread)
        guard !unread.isEmpty else { return }
        for email in unread { email.isUnread = false }
        try? modelContext.save()
        let targets = unread.map { (mailbox: $0.mailbox, uid: $0.uid) }
        Task {
            let manager = MessageManager(account: account)
            for target in targets {
                try? await manager.markSeen(mailbox: target.mailbox, uid: target.uid, true)
            }
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

    /// Insert new messages or refresh the mutable fields (incl. server flags) of ones already stored.
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

    /// Delete locally-stored messages that a freshly fetched page proves are gone server-side.
    ///
    /// A page is a contiguous UID window. Any stored message whose UID falls in that window but isn't
    /// in the page was deleted on the server. `openTop` extends the window upward without bound — used
    /// for the newest page, which is authoritative for everything at or above its lowest UID.
    private func prune(against emails: [EmailData], openTop: Bool) throws {
        guard let minUID: Int = emails.map(\.uid).min() else { return }
        let maxUID: Int = emails.map(\.uid).max() ?? minUID
        let fetchedIDs = Set(emails.map(\.id))
        let accountID: UUID = account.id
        let mailbox: String = emails.first?.mailbox ?? "INBOX"
        let descriptor = FetchDescriptor<Email>(
            predicate: #Predicate {
                $0.accountID == accountID && $0.mailbox == mailbox
                    && $0.uid >= minUID && (openTop || $0.uid <= maxUID)
            })
        for email in try modelContext.fetch(descriptor) where !fetchedIDs.contains(email.id) {
            modelContext.delete(email)
        }
        try modelContext.save()
    }
}
