import UserNotifications

enum TriggeredNotice {
    static let idPrefix = "history-"

    @MainActor
    static func post(_ items: [ActivityItem]) {
        let center = UNUserNotificationCenter.current()
        for item in items.prefix(3) where item.actionType == "triggered" {
            let content = UNMutableNotificationContent()
            content.title = "\(item.symbol) Triggered"
            content.body = item.summary
            var info: [String: Any] = [
                "type": "alert.triggered",
                "historyId": item.id,
            ]
            if let alertId = item.alertId {
                info["alertId"] = alertId
            }
            content.userInfo = info
            center.add(
                UNNotificationRequest(
                    identifier: idPrefix + item.id,
                    content: content,
                    trigger: nil
                )
            )
        }
    }

    static func isTriggered(_ notification: UNNotification) -> Bool {
        let info = notification.request.content.userInfo
        if let type = info["type"] as? String {
            return type == "alert.triggered"
        }
        return notification.request.trigger is UNPushNotificationTrigger
            || notification.request.identifier.hasPrefix(idPrefix)
    }
}
