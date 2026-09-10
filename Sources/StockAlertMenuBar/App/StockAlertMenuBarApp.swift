import AppKit
import SwiftUI
import UserNotifications

@main
struct StockAlertMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = MenuSession.shared

    var body: some Scene {
        MenuBarExtra {
            RootPanel()
                .environment(session)
        } label: {
            StatusGlyph(triggered: session.isTriggered)
                .background { RevealPanelBridge().environment(session) }
        }
        .menuBarExtraStyle(.window)

        Window("StockAlert.pro", id: "panel") {
            RootPanel()
                .environment(session)
                .background(WindowChrome())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(Self.showsStandalonePanel ? .presented : .suppressed)
    }

    private static var showsStandalonePanel: Bool {
        CommandLine.arguments.contains("--panel")
            || ProcessInfo.processInfo.environment["STOCKALERT_SHOW_PANEL"] == "1"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            AppUpdater.shared.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { @MainActor in
                await MenuSession.shared.consumeCallback(url)
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushRegistration.shared.didReceiveDeviceToken(deviceToken)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {
        Task { @MainActor in
            PushRegistration.shared.didFailToRegister()
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard TriggeredNotice.isTriggered(notification) else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list])
        guard notification.request.trigger is UNPushNotificationTrigger else { return }
        Task { @MainActor in
            MenuSession.shared.handleIncomingPush()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        Task { @MainActor in
            MenuSession.shared.handleNotificationTap()
        }
    }
}

private struct RevealPanelBridge: View {
    @Environment(MenuSession.self) private var session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .onChange(of: session.wantsPanel) { _, wanted in
                guard wanted else { return }
                session.wantsPanel = false
                openWindow(id: "panel")
            }
    }
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
