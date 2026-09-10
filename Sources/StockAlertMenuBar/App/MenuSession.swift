import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class MenuSession {
    static let shared = MenuSession()

    var items: [ActivityItem] = []
    var selectedStatuses: Set<ActivityStatus> = ActivityStatus.storedSelection()
    var isTriggered = false
    var isLoading = false
    var isSigningIn = false
    var notice: String?
    var wantsPanel = false
    var session: DesktopSession?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user?.email }

    var visibleItems: [ActivityItem] {
        items.filter { item in
            guard let status = ActivityStatus(rawValue: item.actionType) else { return false }
            return selectedStatuses.contains(status)
        }
    }

    private var triggerResetTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var hasSeededActivity = false
    private var seenHistoryIds = Set<String>()
    private let signIn = DesktopSignIn()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var redeemingCode: String?

    private enum RefreshOrigin {
        case poll
        case push
    }

    init() {
        encoder.keyEncodingStrategy = .convertToSnakeCase
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let data = KeychainStore.load() {
            session = try? decoder.decode(DesktopSession.self, from: data)
        }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refreshActivity()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.refreshActivity()
            }
        }
        if isSignedIn {
            PushRegistration.shared.start()
        }
    }

    func openNewAlert() {
        Links.open(Links.app)
    }

    func openItem(_ item: ActivityItem) {
        guard let alertId = item.alertId, item.canOpen else { return }
        Links.open(Links.alert(alertId))
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func signInFromBrowser() {
        Task { await beginSignIn() }
    }

    func signOut() {
        let accessToken = session?.accessToken
        session = nil
        items = []
        notice = nil
        hasSeededActivity = false
        seenHistoryIds = []
        KeychainStore.clear()
        if let accessToken {
            let installId = InstallID.current()
            Task {
                try? await StockAlertAPI.unregisterApns(accessToken: accessToken, installId: installId)
            }
        }
    }

    func consumeCallback(_ url: URL) async {
        guard let code = AuthCallback.code(from: url) else { return }
        await redeem(code)
    }

    func handleIncomingPush() {
        noteTriggered()
        Task { await refreshActivity(origin: .push) }
    }

    func handleNotificationTap() {
        clearTriggered()
        revealPanel()
        Task { await refreshActivity(origin: .push) }
    }

    func clearTriggered() {
        triggerResetTask?.cancel()
        triggerResetTask = nil
        isTriggered = false
    }

    func toggleStatus(_ status: ActivityStatus) {
        if selectedStatuses.contains(status) {
            guard selectedStatuses.count > 1 else { return }
            selectedStatuses.remove(status)
        } else {
            selectedStatuses.insert(status)
        }
        ActivityStatus.persist(selectedStatuses)
    }

    func selectStatuses(_ statuses: Set<ActivityStatus>) {
        guard !statuses.isEmpty else { return }
        selectedStatuses = statuses
        ActivityStatus.persist(selectedStatuses)
    }

    var statusFilterSummary: String {
        ActivityStatus.summary(of: selectedStatuses)
    }

    func revealPanel() {
        NSApp.activate(ignoringOtherApps: true)
        wantsPanel = true
    }

    private func beginSignIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        notice = nil
        defer { isSigningIn = false }
        do {
            let callback = try await signIn.start()
            await consumeCallback(callback)
        } catch is CancellationError {
            return
        } catch {
            notice = "Sign in did not finish. Try again."
        }
    }

    private func redeem(_ code: String) async {
        guard redeemingCode != code else { return }
        redeemingCode = code
        defer { if redeemingCode == code { redeemingCode = nil } }
        do {
            try persist(try await StockAlertAPI.exchange(code: code))
            notice = nil
            await refreshActivity()
            PushRegistration.shared.start()
        } catch {
            notice = "Could not complete sign in."
        }
    }

    func refreshActivity() async {
        await refreshActivity(origin: .poll)
    }

    private func refreshActivity(origin: RefreshOrigin) async {
        guard isSignedIn else {
            items = []
            isLoading = false
            hasSeededActivity = false
            seenHistoryIds = []
            return
        }
        isLoading = items.isEmpty
        do {
            let token = try await validAccessToken()
            let next = try await StockAlertAPI.history(accessToken: token).map(ActivityMapping.item(from:))
            items = next
            notice = nil
            let ids = Set(next.map(\.id))
            if hasSeededActivity, origin == .poll {
                let fresh = next.filter { $0.actionType == "triggered" && !seenHistoryIds.contains($0.id) }
                if !fresh.isEmpty {
                    noteTriggered()
                    TriggeredNotice.post(fresh)
                }
            }
            seenHistoryIds.formUnion(ids)
            hasSeededActivity = true
        } catch let error as APIClientError where error.status == 401 {
            signOut()
            notice = "Session expired. Sign in again."
        } catch {
            notice = "Could not load activity."
        }
        isLoading = false
    }

    private func noteTriggered() {
        isTriggered = true
        SoundCue.playAlert()
        triggerResetTask?.cancel()
        triggerResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.isTriggered = false
        }
    }

    func syncPushToken() async {
        guard isSignedIn, let token = PushRegistration.shared.deviceToken else { return }
        do {
            try await StockAlertAPI.registerApns(
                accessToken: try await validAccessToken(),
                token: token,
                installId: InstallID.current(),
                environment: Endpoints.pushEnvironment
            )
        } catch let error as APIClientError where error.status == 401 {
            signOut()
            notice = "Session expired. Sign in again."
        } catch {
            return
        }
    }

    private func validAccessToken() async throws -> String {
        guard var current = session else {
            throw APIClientError(message: "Not signed in", status: 401)
        }
        let now = Int(Date().timeIntervalSince1970)
        if let expiry = current.expiresAt, expiry - 60 <= now {
            current = try await StockAlertAPI.refresh(refreshToken: current.refreshToken)
            try persist(current)
        }
        return current.accessToken
    }

    private func persist(_ next: DesktopSession) throws {
        session = next
        try KeychainStore.save(try encoder.encode(next))
    }
}

enum Links {
    static var app: URL { Endpoints.appOrigin }

    static func alert(_ id: String) -> URL {
        var components = URLComponents(url: app, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alert", value: id)]
        return components.url ?? app
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

enum SoundCue {
    static func playAlert() {
        if let sound = NSSound(named: "Tink") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

enum Palette {
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let successNS = NSColor(srgbRed: 35 / 255, green: 122 / 255, blue: 75 / 255, alpha: 1)

    static func action(_ type: String) -> Color { colors(type).text }
    static func dot(_ type: String) -> Color { colors(type).dot }

    private static func colors(_ type: String) -> (dot: Color, text: Color) {
        switch type {
        case "triggered": (triggered, triggeredText)
        case "created", "verified": (created, createdText)
        case "reactivated": (accentSecondary, accentSecondary)
        case "paused": (paused, pausedText)
        case "notification_failed": (destructive, destructive)
        case "notification_sent", "updated": (accentLight, accentLight)
        default: (Color.secondary, Color.secondary)
        }
    }

    private static let triggered = adaptive(light: (183, 121, 31), dark: (245, 158, 11))
    private static let triggeredText = adaptive(light: (122, 85, 20), dark: (251, 191, 36))
    private static let created = adaptive(light: (35, 122, 75), dark: (39, 166, 68))
    private static let createdText = adaptive(light: (23, 107, 67), dark: (85, 201, 111))
    private static let paused = adaptive(light: (59, 130, 246), dark: (99, 102, 241))
    private static let pausedText = adaptive(light: (29, 78, 216), dark: (165, 180, 252))
    private static let destructive = adaptive(light: (163, 58, 56), dark: (248, 113, 113))
    private static let accentLight = adaptive(light: (59, 130, 246), dark: (96, 165, 250))
    private static let accentSecondary = adaptive(light: (130, 80, 223), dark: (99, 102, 241))

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
}
