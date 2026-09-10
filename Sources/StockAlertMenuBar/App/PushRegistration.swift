import AppKit
import Foundation
import UserNotifications

enum InstallID {
    private static let key = "install-id"

    static func current() -> String {
        if let existing = UserDefaults.standard.string(forKey: key), UUID(uuidString: existing) != nil {
            return existing.lowercased()
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

@MainActor
final class PushRegistration {
    static let shared = PushRegistration()

    private let center = UNUserNotificationCenter.current()
    private(set) var deviceToken: String?

    func start() {
        guard MenuSession.shared.isSignedIn else { return }
        Task { await requestAndRegister() }
    }

    func didReceiveDeviceToken(_ token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        Task { await MenuSession.shared.syncPushToken() }
    }

    func didFailToRegister() {
        MenuSession.shared.notice = "Notifications are off."
    }

    private func requestAndRegister() async {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else {
            didFailToRegister()
            return
        }
        NSApp.registerForRemoteNotifications()
        await MenuSession.shared.syncPushToken()
    }
}
