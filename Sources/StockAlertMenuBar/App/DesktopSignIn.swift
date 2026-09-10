import AppKit
import AuthenticationServices
import Foundation

@MainActor
final class DesktopSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var dummyWindow: NSWindow?
    private var continuation: CheckedContinuation<URL, Error>?

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = Self.makeSession { url, error in
                Task { @MainActor in
                    self.finish(url: url, error: error)
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            self.session = session
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if !session.start() {
                finish(url: nil, error: APIClientError(message: "Could not open the sign-in page", status: 0))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = NSApp.windows.first(where: \.isVisible) {
            return window
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.orderFrontRegardless()
        dummyWindow = window
        return window
    }

    private func finish(url: URL?, error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        session = nil
        dummyWindow?.orderOut(nil)
        dummyWindow = nil
        NSApp.setActivationPolicy(.accessory)
        if let url {
            continuation.resume(returning: url)
        } else if let error, Self.isCancel(error) {
            continuation.resume(throwing: CancellationError())
        } else {
            continuation.resume(throwing: error ?? APIClientError(message: "Sign in did not complete", status: 0))
        }
    }

    nonisolated private static func makeSession(
        completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) -> ASWebAuthenticationSession {
        ASWebAuthenticationSession(
            url: Endpoints.connect,
            callbackURLScheme: "stockalert",
            completionHandler: completion
        )
    }

    private static func isCancel(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}
