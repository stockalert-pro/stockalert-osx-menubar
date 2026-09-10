import Foundation

struct DesktopUser: Codable, Hashable {
    var id: String
    var email: String?
}

struct DesktopSession: Codable, Hashable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Int?
    var user: DesktopUser?
}

struct HistoryRow: Decodable {
    var id: String
    var alertId: String?
    var symbol: String
    var actionType: String
    var actionTimestamp: String
    var triggerPrice: Double?
    var alertData: JSONMap?
}

enum StockAlertAPI {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func exchange(code: String) async throws -> DesktopSession {
        try await post(
            path: "v1/auth/desktop/exchange",
            body: ["code": code]
        )
    }

    static func refresh(refreshToken: String) async throws -> DesktopSession {
        try await post(
            path: "v1/auth/desktop/refresh",
            body: ["refresh_token": refreshToken]
        )
    }

    static func history(accessToken: String) async throws -> [HistoryRow] {
        var components = URLComponents(url: Endpoints.apiOrigin.appending(path: "v1/alerts/history"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "days", value: "7"),
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "mode", value: "compact"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    static func registerApns(accessToken: String, token: String, installId: String, environment: String) async throws {
        let _: ApnsRegisterResponse = try await post(
            path: "v1/user/notifications/apns/register",
            body: [
                "token": token,
                "install_id": installId,
                "environment": environment,
            ],
            accessToken: accessToken
        )
    }

    static func unregisterApns(accessToken: String, installId: String) async throws {
        let _: ApnsRegisterResponse = try await post(
            path: "v1/user/notifications/apns/unregister",
            body: ["install_id": installId],
            accessToken: accessToken
        )
    }

    private static func post<T: Decodable>(path: String, body: [String: String], accessToken: String? = nil) async throws -> T {
        var request = URLRequest(url: Endpoints.apiOrigin.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        if (200..<300).contains(status), envelope.success, let payload = envelope.data {
            return payload
        }
        throw APIClientError(message: envelope.error?.message ?? "Request failed", status: status)
    }
}

private struct APIEnvelope<T: Decodable>: Decodable {
    var success: Bool
    var data: T?
    var error: APIErrorBody?
}

private struct ApnsRegisterResponse: Decodable {
    var registered: Bool
}

private struct APIErrorBody: Decodable {
    var message: String?
}

struct APIClientError: Error {
    var message: String
    var status: Int
}

enum AuthCallback {
    static func code(from url: URL) -> String? {
        guard url.scheme == "stockalert" else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let isAuth = host == "auth" || path == "/auth" || path.hasPrefix("/auth/")
        guard isAuth else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let code = items?.first(where: { $0.name == "code" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let code, !code.isEmpty else { return nil }
        return code
    }
}

enum ActivityMapping {
    static func item(from row: HistoryRow) -> ActivityItem {
        ActivityItem(
            id: row.id,
            alertId: row.alertId,
            symbol: row.symbol,
            actionType: row.actionType,
            action: actionLabel(row.actionType),
            summary: detail(row),
            firedAt: Timestamp.date(from: row.actionTimestamp)
        )
    }

    static func actionLabel(_ actionType: String) -> String {
        switch actionType {
        case "triggered": "Triggered"
        case "created": "Created"
        case "paused": "Paused"
        case "deleted": "Deleted"
        case "notification_sent": "Sent"
        case "reactivated": "Reactivated"
        case "verified": "Verified"
        case "notification_failed": "Failed"
        case "updated": "Updated"
        default: actionType
        }
    }

    private static func detail(_ row: HistoryRow) -> String {
        let data = row.alertData ?? .empty
        let parameters = data.map("parameters") ?? .empty
        let condition = data.string("condition", "alertType")
            ?? parameters.string("condition", "alertType")

        guard let condition else {
            return ""
        }

        let thresholdValue = data.number(
            "threshold", "targetPrice", "thresholdDisplay", "peThreshold", "forwardPe"
        ) ?? parameters.number("threshold", "period", "limit", "percentageChange")
        var text = phrase(
            condition,
            threshold: formatThreshold(condition, thresholdValue),
            thresholdValue: thresholdValue,
            triggerPrice: row.triggerPrice,
            parameters: parameters,
            data: data,
            actionType: row.actionType
        )

        if row.actionType == "triggered", let price = row.triggerPrice {
            let money = Money.usd(price)
            if !text.contains(money) {
                switch condition {
                case "price_above", "price_below", "price_change_up", "price_change_down",
                     "ma_touch_above", "ma_touch_below", "daily_reminder":
                    text += " · \(money)"
                default:
                    break
                }
            }
        }

        return text
    }

    private static func phrase(
        _ condition: String,
        threshold: String?,
        thresholdValue: Double?,
        triggerPrice: Double?,
        parameters: JSONMap,
        data: JSONMap,
        actionType: String
    ) -> String {
        switch condition {
        case "price_above":
            return with("Price rises above", threshold)
        case "price_below":
            return with("Price falls below", threshold)
        case "price_change_up":
            return threshold.map { "Price rises by \($0)" } ?? "Price rises"
        case "price_change_down":
            return threshold.map { "Price falls by \($0)" } ?? "Price falls"
        case "new_high":
            return triggerPrice.map { "New 52-week high at \(Money.usd($0))" } ?? "New 52-week high"
        case "new_low":
            return triggerPrice.map { "New 52-week low at \(Money.usd($0))" } ?? "New 52-week low"
        case "reminder":
            return reminderPhrase(thresholdValue)
        case "daily_reminder":
            let time = parameters.string("deliveryTime")
            if time == "after_market_close" { return "Daily after market close" }
            if time == "market_open" { return "Daily at market open" }
            return "Daily price snapshot"
        case "ma_crossover_golden":
            return movingAverageCross(bullish: true, parameters: parameters)
        case "ma_crossover_death":
            return movingAverageCross(bullish: false, parameters: parameters)
        case "ma_touch_above":
            return movingAverageBreak(above: true, parameters: parameters, data: data, period: thresholdValue)
        case "ma_touch_below":
            return movingAverageBreak(above: false, parameters: parameters, data: data, period: thresholdValue)
        case "volume_change":
            return volumePhrase(thresholdValue: thresholdValue, parameters: parameters, data: data)
        case "rsi_limit":
            return rsiPhrase(
                threshold: threshold,
                parameters: parameters,
                data: data,
                actionType: actionType
            )
        case "pe_ratio_below":
            return pePhrase(forward: false, above: false, threshold: threshold, data: data, actionType: actionType)
        case "pe_ratio_above":
            return pePhrase(forward: false, above: true, threshold: threshold, data: data, actionType: actionType)
        case "forward_pe_below":
            return pePhrase(forward: true, above: false, threshold: threshold, data: data, actionType: actionType)
        case "forward_pe_above":
            return pePhrase(forward: true, above: true, threshold: threshold, data: data, actionType: actionType)
        case "earnings_announcement":
            return daysBefore(thresholdValue, event: "earnings", today: "Earnings today")
        case "dividend_ex_date":
            return daysBefore(thresholdValue, event: "ex-dividend", today: "Ex-dividend today")
        case "dividend_payment":
            return dividendPhrase(parameters: parameters, data: data, actionType: actionType)
        case "insider_transactions":
            return insiderPhrase(threshold: threshold, parameters: parameters)
        case "social_buzz":
            return socialBuzz(data: data, parameters: parameters)
        default:
            return with(condition.replacingOccurrences(of: "_", with: " "), threshold)
        }
    }

    private static func formatThreshold(_ condition: String, _ value: Double?) -> String? {
        guard let value else { return nil }
        switch condition {
        case "price_change_up", "price_change_down", "volume_change":
            return Money.percent(value)
        case "rsi_limit":
            return Money.rsi(value)
        case "pe_ratio_below", "pe_ratio_above", "forward_pe_below", "forward_pe_above":
            return "\(Money.plain(value))x"
        case "insider_transactions":
            return Money.usd(value, whole: true)
        default:
            return Money.usd(value)
        }
    }

    private static func socialBuzz(data: JSONMap, parameters: JSONMap) -> String {
        let evaluation = evaluationMap(data)
        let direction = evaluation.string("direction") ?? parameters.string("direction")
        let signal = evaluation.string("signal")
        let label: String
        if direction == "falling" {
            label = "Social buzz fading"
        } else if signal == "high_attention" || signal == "weekly" {
            label = "High social attention"
        } else if signal == "score_change" || signal == "daily_delta" {
            label = "Social discussion up"
        } else if direction == "rising" {
            label = "Social buzz rising"
        } else {
            label = "Social buzz"
        }
        let source = evaluation.string("source")
        if source == "x" { return "\(label) · X" }
        if source == "reddit" { return "\(label) · Reddit" }
        return label
    }

    private static func rsiPhrase(
        threshold: String?,
        parameters: JSONMap,
        data: JSONMap,
        actionType: String
    ) -> String {
        let evaluation = evaluationMap(data)
        let limit = data.number("threshold", "limit")
            ?? parameters.number("threshold", "limit")
        let current = evaluation.number("rsi", "currentRsi")
            ?? data.number("rsi", "currentRsi")
        let fired = actionType == "triggered"
        let direction = rsiDirection(parameters: parameters, data: data, evaluation: evaluation, limit: limit, current: current)
        let zone = rsiZone(limit)
        let verb: String
        switch direction {
        case "up":
            verb = fired ? "crossed above" : "crosses above"
        case "down":
            verb = fired ? "crossed below" : "crosses below"
        default:
            verb = fired ? "crossed" : "crosses"
        }

        let limitText = threshold ?? limit.map(Money.rsi)
        if fired, let current {
            var text = "RSI \(Money.rsi(current)) \(verb)"
            if let limitText { text += " \(limitText)" }
            if let zone { text += " · \(zone)" }
            return text
        }
        guard let limitText else { return "RSI" }
        if let zone {
            return "RSI \(verb) \(limitText) (\(zone))"
        }
        return "RSI \(verb) \(limitText)"
    }

    private static func rsiDirection(
        parameters: JSONMap,
        data: JSONMap,
        evaluation: JSONMap,
        limit: Double?,
        current: Double?
    ) -> String? {
        if let crossed = evaluation.bool("crossedAbove") {
            return crossed ? "up" : "down"
        }
        let raw = parameters.string("direction")
            ?? data.string("direction")
            ?? parameters.string("condition")
        switch raw {
        case "above", "up":
            return "up"
        case "below", "down":
            return "down"
        case "both", "either", "auto":
            if let current, let limit {
                return current >= limit ? "up" : "down"
            }
            return nil
        default:
            if let current, let limit {
                return current >= limit ? "up" : "down"
            }
            if let limit {
                if limit >= 70 { return "up" }
                if limit <= 30 { return "down" }
            }
            return nil
        }
    }

    private static func rsiZone(_ limit: Double?) -> String? {
        guard let limit else { return nil }
        if limit >= 70 { return "overbought" }
        if limit <= 30 { return "oversold" }
        return nil
    }

    private static func evaluationMap(_ data: JSONMap) -> JSONMap {
        data.map("evaluationMetadata") ?? .empty
    }

    private static func reminderPhrase(_ value: Double?) -> String {
        guard let value else { return "Reminder" }
        let days = max(0, Int(value.rounded()))
        if days == 0 { return "Check back today" }
        if days == 1 { return "Check back in 1 day" }
        return "Check back in \(days) days"
    }

    private static func daysBefore(_ value: Double?, event: String, today: String) -> String {
        guard let value else { return today.replacingOccurrences(of: " today", with: "") }
        let days = Int(value.rounded())
        if days <= 0 { return today }
        if days == 1 { return "1 day before \(event)" }
        return "\(days) days before \(event)"
    }

    private static func movingAverageCross(bullish: Bool, parameters: JSONMap) -> String {
        let short = Int((parameters.number("shortPeriod") ?? 50).rounded())
        let long = Int((parameters.number("longPeriod") ?? 200).rounded())
        if bullish {
            return "Golden Cross: \(short)-day above \(long)-day"
        }
        return "Death Cross: \(short)-day below \(long)-day"
    }

    private static func movingAverageBreak(
        above: Bool,
        parameters: JSONMap,
        data: JSONMap,
        period: Double?
    ) -> String {
        let days = period
            ?? parameters.number("period")
            ?? evaluationMap(data).number("maPeriod")
        let verb = above ? "breaks above" : "breaks below"
        if let days {
            return "Price \(verb) \(Money.plain(days))-day MA"
        }
        return "Price \(verb) moving average"
    }

    private static func volumePhrase(
        thresholdValue: Double?,
        parameters: JSONMap,
        data: JSONMap
    ) -> String {
        let baseline = parameters.string("volumeBaseline", "baseline")
            ?? data.string("volumeBaseline", "baseline")
        let vs: String
        switch baseline {
        case "ma100", "ma_100":
            vs = " vs 100-day avg"
        case "initial":
            vs = ""
        case "ma20", "ma_20", .none:
            vs = " vs 20-day avg"
        default:
            vs = " vs average"
        }
        if let thresholdValue {
            return "Volume \(thresholdValue >= 0 ? "up" : "down") \(Money.percent(abs(thresholdValue)))\(vs)"
        }
        if let multiplier = parameters.number("volumeMultiplier") ?? data.number("volumeMultiplier") {
            return "Volume \(Money.plain(multiplier))x\(vs.isEmpty ? " average" : vs)"
        }
        return "Volume change"
    }

    private static func pePhrase(
        forward: Bool,
        above: Bool,
        threshold: String?,
        data: JSONMap,
        actionType: String
    ) -> String {
        let name = forward ? "Forward P/E" : "P/E"
        let verb = above ? "rises above" : "falls below"
        let current = evaluationMap(data).number(
            forward ? "currentForwardPeRatio" : "currentPeRatio",
            "pe"
        )
        if actionType == "triggered", let current, let threshold {
            return "\(name) \(Money.plain(current))x, \(above ? "above" : "below") \(threshold)"
        }
        return with("\(name) \(verb)", threshold)
    }

    private static func dividendPhrase(parameters: JSONMap, data: JSONMap, actionType: String) -> String {
        let paid = actionType == "triggered"
        let perShare = evaluationMap(data).number("dividendPerShare")
        if let shares = parameters.number("shares") {
            let count = shares == 1 ? "1 share" : "\(Money.plain(shares)) shares"
            return paid ? "Dividend paid · \(count)" : "Dividend payment · \(count)"
        }
        if paid, let perShare {
            return "Dividend paid · \(Money.usd(perShare))/share"
        }
        return paid ? "Dividend paid today" : "Dividend payment"
    }

    private static func insiderPhrase(threshold: String?, parameters: JSONMap) -> String {
        let direction = parameters.string("direction")
        let action = direction == "buy" ? "Insider buys" : direction == "sell" ? "Insider sells" : "Insider trades"
        var text = threshold.map { "\(action) ≥ \($0)" } ?? action
        if let count = parameters.number("minExecutives"), count > 1 {
            let days = Int((parameters.number("windowDays") ?? 7).rounded())
            text += " · \(Money.plain(count))+ in \(days) days"
        }
        return text
    }

    private static func with(_ label: String, _ value: String?) -> String {
        guard let value, !value.isEmpty else { return label }
        return "\(label) \(value)"
    }
}

enum Money {
    static func usd(_ value: Double, whole: Bool = false) -> String {
        value.formatted(
            .currency(code: "USD")
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(whole ? 0 : 2))
        )
    }

    static func percent(_ value: Double) -> String {
        "\(plain(value))%"
    }

    static func plain(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%g", value)
    }

    static func rsi(_ value: Double) -> String {
        abs(value - value.rounded()) < 0.05
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
}

struct JSONMap: Decodable, Sendable {
    static let empty = JSONMap(values: [:])

    private let values: [String: JSONValue]

    private init(values: [String: JSONValue]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            values = [:]
            return
        }
        values = (try? container.decode([String: JSONValue].self)) ?? [:]
    }

    func map(_ key: String) -> JSONMap? {
        guard case .map(let nested)? = lookup(key) else { return nil }
        return JSONMap(values: nested)
    }

    func string(_ keys: String...) -> String? {
        for key in keys {
            if let value = lookup(key)?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }

    func number(_ keys: String...) -> Double? {
        for key in keys {
            if let value = lookup(key)?.numberValue { return value }
        }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = lookup(key) { return value }
        return nil
    }

    private func lookup(_ key: String) -> JSONValue? {
        if let value = values[key] { return value }
        let camel = JSONMap.camel(key)
        if camel != key, let value = values[camel] { return value }
        let snake = JSONMap.snake(key)
        if snake != key, let value = values[snake] { return value }
        return nil
    }

    private static func camel(_ key: String) -> String {
        guard key.contains("_") else { return key }
        let parts = key.split(separator: "_")
        guard let first = parts.first else { return key }
        return first.lowercased() + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    private static func snake(_ key: String) -> String {
        var result = ""
        for character in key {
            if character.isUppercase {
                result.append("_")
                result.append(character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }
}

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case map([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .map(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): Money.plain(value)
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(trimmed) { return value }
            let cleaned = trimmed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        default:
            return nil
        }
    }
}

enum Timestamp {
    static func date(from raw: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw) ?? Date.distantPast
    }
}
