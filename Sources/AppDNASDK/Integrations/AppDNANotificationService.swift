import UserNotifications

/// Enhanced helper class for rich push notification media download.
/// Supports image (JPEG/PNG), GIF, and video (MP4) attachments.
/// Customers subclass this in their Notification Service Extension target
/// for richer media support than the basic NotificationService in RichPushExtension/.
open class AppDNANotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Check for image_url in push payload
        guard let imageUrlString = request.content.userInfo["image_url"] as? String,
              let imageUrl = URL(string: imageUrlString) else {
            contentHandler(content)
            return
        }

        // Download media and attach
        downloadMedia(url: imageUrl) { [weak self] localUrl in
            if let localUrl = localUrl,
               let attachment = try? UNNotificationAttachment(
                identifier: "appdna-media",
                url: localUrl,
                options: nil
               ) {
                content.attachments = [attachment]
            }
            self?.contentHandler?(content)
        }
    }

    open override func serviceExtensionTimeWillExpire() {
        if let content = bestAttemptContent {
            contentHandler?(content)
        }
    }

    private func downloadMedia(url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempUrl, response, error in
            guard let tempUrl = tempUrl, error == nil else {
                completion(nil)
                return
            }

            // Determine file extension from response
            let ext: String
            if let mimeType = (response as? HTTPURLResponse)?.mimeType {
                switch mimeType {
                case "image/jpeg": ext = "jpg"
                case "image/png": ext = "png"
                case "image/gif": ext = "gif"
                case "video/mp4": ext = "mp4"
                default: ext = "jpg"
                }
            } else {
                ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            }

            let localUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            do {
                try FileManager.default.moveItem(at: tempUrl, to: localUrl)
                completion(localUrl)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
}
