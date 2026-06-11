#if os(iOS)

import Foundation
import UserNotifications

/// Base class for the Notification Service Extension.
///
/// App developers subclass this in their NSE target — no overrides needed:
///
///     import HightouchPush
///     class NotificationService: HightouchNotificationServiceExtension {}
///
/// The extension intercepts notifications before display and handles two things:
/// 1. Registers dynamic action buttons from `hightouch.actionButtons`
/// 2. Downloads rich media from `hightouch.attachmentUrl`
///
// TODO: Add delegate extensibility
// to let apps provide custom handling for non-Hightouch notifications.
open class HightouchNotificationServiceExtension: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var handlerCalled = false
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// Serializes the read-modify-write on the shared notification category set
    /// across concurrent NSE instances in the same extension process.
    private static let categoryRegistrar = CategoryRegistrar()

    // MARK: - Entry point

    override open func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.handlerCalled = false

        guard let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = mutableContent

        let payload = HTPushPayload(request.content.userInfo)
        // Extract attachmentUrl independently — HTPushPayload requires messageId,
        // but attachments should work even without one.
        let attachmentUrl = (request.content.userInfo[PayloadKey.hightouch] as? [String: Any])?[PayloadKey.attachmentUrl] as? String

        task = Task {
            // Run both tasks concurrently but return results instead of mutating
            // mutableContent directly — UNMutableNotificationContent is not Sendable.
            async let categoryId: String? = resolveCategory(payload: payload, currentCategoryId: mutableContent.categoryIdentifier)
            async let attachment: UNNotificationAttachment? = retrieveAttachment(attachmentUrl: attachmentUrl)

            // Apply category result eagerly — resolveCategory is fast (~ms, local system call)
            // so this completes well before timeout. Writing it to mutableContent immediately
            // ensures bestAttemptContent (same object) has buttons if timeout fires during
            // the slow attachment download.
            if let id = await categoryId {
                mutableContent.categoryIdentifier = id
            }
            if let att = await attachment {
                mutableContent.attachments.append(att)
            }

            callHandlerOnce(mutableContent)
        }
    }

    // MARK: - Timeout

    // Called by iOS automatically when notification service extension takes too long (~30 seconds)
    // Last chance to deliver whatever we have
    override open func serviceExtensionTimeWillExpire() {
        task?.cancel()
        if let bestAttemptContent = bestAttemptContent {
            callHandlerOnce(bestAttemptContent)
        }
    }

    // MARK: - Handler guard

    /// Ensures contentHandler is called exactly once, even if the Task and timeout race.
    private func callHandlerOnce(_ content: UNNotificationContent) {
        lock.lock()
        defer { lock.unlock() }
        guard !handlerCalled, let handler = contentHandler else { return }
        handlerCalled = true
        contentHandler = nil
        handler(content)
    }

    // MARK: - Task 1: Action buttons

    /// Returns the categoryIdentifier to set, or nil if no change needed.
    private func resolveCategory(
        payload: HTPushPayload?,
        currentCategoryId: String
    ) async -> String? {
        // If aps.category was already set, the sender pre-registered a static category — use it as-is.
        if !currentCategoryId.isEmpty {
            return nil
        }

        guard let payload = payload, !payload.messageId.isEmpty else {
            return nil
        }
        let messageId = payload.messageId

        guard let buttons = payload.actionButtons, !buttons.isEmpty else { return nil }
        let actions = buttons.compactMap { buildNotificationAction(from: $0.rawDict) }
        guard !actions.isEmpty else { return nil }

        let category = UNNotificationCategory(
            identifier: messageId,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )

        await Self.categoryRegistrar.register(category)

        return messageId
    }

    private func buildNotificationAction(from button: [String: Any]) -> UNNotificationAction? {
        guard let identifier = button[PayloadKey.identifier] as? String,
              let title = button[PayloadKey.title] as? String else {
            return nil
        }

        let buttonType = button[PayloadKey.buttonType] as? String ?? "default"
        let openApp = (button[PayloadKey.openApp] as? NSNumber)?.boolValue ?? true
        let requiresUnlock = (button[PayloadKey.requiresUnlock] as? NSNumber)?.boolValue ?? false

        var options: UNNotificationActionOptions = []
        if buttonType == "destructive" { options.insert(.destructive) }
        if openApp { options.insert(.foreground) }
        if requiresUnlock { options.insert(.authenticationRequired) }

        if buttonType == "textInput" {
            let inputTitle = button[PayloadKey.inputTitle] as? String ?? ""
            let inputPlaceholder = button[PayloadKey.inputPlaceholder] as? String ?? ""

            if #available(iOS 15.0, *), let icon = resolveIcon(from: button) {
                return UNTextInputNotificationAction(
                    identifier: identifier, title: title, options: options,
                    icon: icon, textInputButtonTitle: inputTitle, textInputPlaceholder: inputPlaceholder
                )
            }
            return UNTextInputNotificationAction(
                identifier: identifier, title: title, options: options,
                textInputButtonTitle: inputTitle, textInputPlaceholder: inputPlaceholder
            )
        }

        if #available(iOS 15.0, *), let icon = resolveIcon(from: button) {
            return UNNotificationAction(identifier: identifier, title: title, options: options, icon: icon)
        }
        return UNNotificationAction(identifier: identifier, title: title, options: options)
    }

    @available(iOS 15.0, *)
    private func resolveIcon(from button: [String: Any]) -> UNNotificationActionIcon? {
        guard let iconInfo = button[PayloadKey.actionIcon] as? [String: Any],
              let iconType = iconInfo[PayloadKey.iconType] as? String,
              let iconName = iconInfo[PayloadKey.iconName] as? String else {
            return nil
        }
        switch iconType {
        case "systemImage": return UNNotificationActionIcon(systemImageName: iconName)
        case "templateImage": return UNNotificationActionIcon(templateImageName: iconName)
        default: return nil
        }
    }

    // MARK: - Task 2: Rich media attachment

    /// Returns a UNNotificationAttachment, or nil if no attachment URL or download failed.
    private func retrieveAttachment(
        attachmentUrl: String?
    ) async -> UNNotificationAttachment? {
        guard let urlString = attachmentUrl,
              let url = URL(string: urlString) else {
            return nil
        }

        var tempUrl: URL?
        do {
            let (downloadedUrl, response) = try await downloadFile(from: url)
            tempUrl = downloadedUrl
            defer { if let t = tempUrl { try? FileManager.default.removeItem(at: t) } }

            // Fail fast on non-2xx responses — don't waste time moving/inspecting an error page.
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }

            let ext = attachmentFileExtension(from: response, url: url)
            let filename = UUID().uuidString + ext
            let destUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)

            try FileManager.default.moveItem(at: downloadedUrl, to: destUrl)
            tempUrl = nil // moveItem succeeded — file is now at destUrl, defer is disarmed

            do {
                return try UNNotificationAttachment(
                    identifier: filename,
                    url: destUrl,
                    options: nil
                )
            } catch {
                // Attachment init failed (unsupported type, size limit, etc.) —
                // clean up the file we already moved since iOS only takes ownership on success.
                try? FileManager.default.removeItem(at: destUrl)
                return nil
            }
        } catch {
            // downloadFile threw — tempUrl was never set, nothing to clean up.
            return nil
        }
    }

    private func downloadFile(from url: URL) async throws -> (URL, URLResponse) {
        if #available(iOS 15.0, *) {
            return try await URLSession.shared.download(from: url)
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                URLSession.shared.downloadTask(with: url) { localUrl, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let localUrl = localUrl, let response = response else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    // Move to a stable temp location before the system cleans up the original.
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                    do {
                        try FileManager.default.moveItem(at: localUrl, to: tmp)
                        continuation.resume(returning: (tmp, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }.resume()
            }
        }
    }

    /// Extracts just the file extension (e.g. ".jpg") from the response or URL.
    private func attachmentFileExtension(from response: URLResponse, url: URL) -> String {
        // Prefer extension from suggestedFilename (derived from Content-Disposition or MIME type).
        if let suggested = response.suggestedFilename {
            let ext = (suggested as NSString).pathExtension
            if !ext.isEmpty { return "." + ext }
        }
        // Fall back to URL path extension.
        let ext = url.pathExtension
        if !ext.isEmpty { return "." + ext }
        return ""
    }
}

// MARK: - Category registration actor

/// Serializes read-modify-write access to `UNUserNotificationCenter.notificationCategories()`
/// so concurrent NSE invocations don't overwrite each other's categories.
///
/// Swift actors are reentrant at `await` suspension points (SE-0306), so a plain actor
/// method with an `await` inside does not provide mutual exclusion across the suspension.
/// This implementation uses an `isProcessing` flag (actor-local, thus truly serialized)
/// to batch concurrent requests: the first caller drives the loop, and reentrant callers
/// suspend via CheckedContinuation until the loop has committed their category.
private actor CategoryRegistrar {
    private var pending: [UNNotificationCategory] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isProcessing = false

    func register(_ category: UNNotificationCategory) async {
        pending.append(category)
        if isProcessing {
            // Suspend until the driving caller's loop commits our category.
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }
        isProcessing = true
        while !pending.isEmpty {
            let batch = pending
            pending = []
            let center = UNUserNotificationCenter.current()
            var categories = await center.notificationCategories()
            for cat in batch { categories.update(with: cat) }
            center.setNotificationCategories(categories)
        }
        // All batches drained — resume any suspended callers.
        let currentWaiters = waiters
        waiters = []
        for waiter in currentWaiters { waiter.resume() }
        isProcessing = false
    }
}

#endif
