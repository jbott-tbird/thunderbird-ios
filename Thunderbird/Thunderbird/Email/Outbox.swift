// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import EmailAddress
import Foundation
import MIME
import SMTP
import SwiftData

/// Drains the persisted ``OutgoingEmail`` queue over SMTP, with bounded exponential-backoff retry.
///
/// Composing enqueues a message and returns immediately; delivery happens here in the background and
/// survives relaunch (the queue is in SwiftData). The queue is processed on launch, after each
/// enqueue, when a back-off timer fires, and on manual retry.
@MainActor
@Observable
final class Outbox {
    /// Give up automatic retries after this many failed attempts (manual retry still works).
    static let maxAttempts: Int = 5

    private var modelContext: ModelContext?
    private var accounts: Accounts?
    private var isProcessing: Bool = false
    private var retryTask: Task<Void, Never>?

    /// Wire up the store and account lookup. Call once, early (e.g. from `ContentView`).
    func configure(modelContext: ModelContext, accounts: Accounts) {
        self.modelContext = modelContext
        self.accounts = accounts
    }

    /// Queue a composed message for delivery and start processing.
    func enqueue(
        account: Account,
        sender: EmailAddress,
        to: [EmailAddress],
        cc: [EmailAddress],
        bcc: [EmailAddress],
        subject: String,
        html: String,
        plainText: String
    ) {
        guard let modelContext else { return }
        let message = OutgoingEmail(
            accountID: account.id, sender: [sender], to: to, cc: cc, bcc: bcc,
            subject: subject, html: html, plainText: plainText)
        modelContext.insert(message)
        try? modelContext.save()
        Task { await processQueue() }
    }

    /// Attempt to send every eligible queued/failed message, oldest first.
    func processQueue() async {
        guard let modelContext, let accounts, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let now = Date()
        let descriptor = FetchDescriptor<OutgoingEmail>(sortBy: [SortDescriptor(\.createdAt)])
        guard let messages = try? modelContext.fetch(descriptor) else { return }

        for message in messages where isEligible(message, now: now) {
            guard let account = accounts.account(for: message.accountID), let sender = message.sender.first else {
                message.status = .failed
                message.lastError = String(localized: "Account is no longer available.")
                try? modelContext.save()
                continue
            }
            message.status = .sending
            message.lastError = nil
            try? modelContext.save()

            do {
                let body = try MIME.Body.alternative(plainText: message.plainText, html: message.html)
                let email = SMTP.Email(
                    sender: sender,
                    recipients: message.to,
                    copied: message.cc,
                    blindCopied: message.bcc,
                    subject: message.subject,
                    body: body)
                try await MessageManager(account: account).send(email)
                modelContext.delete(message)  // Delivered — drop it from the queue
            } catch {
                message.attemptCount += 1
                message.lastError = "\(error)"
                message.status = .failed
                message.nextAttemptAt = message.attemptCount >= Self.maxAttempts
                    ? nil
                    : now.addingTimeInterval(backoff(message.attemptCount))
            }
            try? modelContext.save()
        }

        scheduleNextRetry()
    }

    /// Re-queue a message for an immediate manual retry.
    func retry(_ message: OutgoingEmail) {
        message.status = .queued
        message.attemptCount = 0
        message.nextAttemptAt = nil
        message.lastError = nil
        try? modelContext?.save()
        Task { await processQueue() }
    }

    /// Remove a message from the queue without sending it.
    func delete(_ message: OutgoingEmail) {
        modelContext?.delete(message)
        try? modelContext?.save()
    }

    /// A queued message, or a failed one whose back-off has elapsed and attempts remain.
    private func isEligible(_ message: OutgoingEmail, now: Date) -> Bool {
        switch message.status {
        case .queued:
            return true
        case .sending:
            return false  // In flight elsewhere
        case .failed:
            return message.attemptCount < Self.maxAttempts && (message.nextAttemptAt ?? now) <= now
        }
    }

    /// Exponential back-off (5s, 10s, 20s, …) capped at 10 minutes.
    private func backoff(_ attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(attempt - 1)) * 5, 600)
    }

    /// Schedule a single wake-up at the soonest pending retry time, replacing any existing one.
    private func scheduleNextRetry() {
        retryTask?.cancel()
        retryTask = nil
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<OutgoingEmail>()
        guard let messages = try? modelContext.fetch(descriptor) else { return }
        let now = Date()
        let nextAttempts = messages
            .filter { $0.status == .failed && $0.attemptCount < Self.maxAttempts }
            .compactMap { $0.nextAttemptAt }
        guard let soonest = nextAttempts.min() else { return }
        let delay = max(soonest.timeIntervalSince(now), 1)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.processQueue()
        }
    }
}
