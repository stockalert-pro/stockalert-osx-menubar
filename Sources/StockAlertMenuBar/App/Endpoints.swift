import Foundation

enum Endpoints {
    static var apiOrigin: URL {
        origin(environment: "STOCKALERT_API_ORIGIN", fallback: "https://api.stockalert.pro")
    }

    static var appOrigin: URL {
        origin(environment: "STOCKALERT_APP_ORIGIN", fallback: "https://app.stockalert.pro")
    }

    static var connect: URL {
        appOrigin.appending(path: "mac/connect")
    }

    static var pushEnvironment: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "StockAlertPushEnvironment") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "production" ? "production" : "sandbox"
    }

    private static func origin(environment: String, fallback: String) -> URL {
        if let raw = ProcessInfo.processInfo.environment[environment]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: raw),
           isAllowedOrigin(url)
        {
            return url
        }
        return URL(string: fallback)!
    }

    private static func isAllowedOrigin(_ url: URL) -> Bool {
        switch url.scheme {
        case "https":
            return true
        case "http":
            let host = url.host?.lowercased()
            return host == "localhost" || host == "127.0.0.1"
        default:
            return false
        }
    }
}
