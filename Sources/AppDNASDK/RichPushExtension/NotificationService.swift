import UserNotifications

/// UNNotificationServiceExtension for rich push content (image download).
/// Add as a separate target: AppDNANotificationServiceExtension
open class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override open func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttempt = bestAttempt

        // Download image attachment if present
        if let imageUrlString = bestAttempt.userInfo["image_url"] as? String,
           let url = URL(string: imageUrlString) {
            downloadAttachment(url: url) { attachment in
                if let attachment = attachment {
                    bestAttempt.attachments = [attachment]
                }
                contentHandler(bestAttempt)
            }
        } else {
            contentHandler(bestAttempt)
        }
    }

    override open func serviceExtensionTimeWillExpire() {
        // Deliver best attempt before time runs out
        if let contentHandler = contentHandler, let bestAttempt = bestAttempt {
            contentHandler(bestAttempt)
        }
    }

    private func downloadAttachment(url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                completion(nil)
                return
            }

            // Determine file extension from response or URL
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)

            do {
                try FileManager.default.moveItem(at: localURL, to: tempFile)
                let attachment = try UNNotificationAttachment(
                    identifier: "image",
                    url: tempFile,
                    options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
