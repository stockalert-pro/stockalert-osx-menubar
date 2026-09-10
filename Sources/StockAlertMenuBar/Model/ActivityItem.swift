import Foundation

struct ActivityItem: Identifiable, Hashable {
    let id: String
    let alertId: String?
    let symbol: String
    let actionType: String
    let action: String
    let summary: String
    let firedAt: Date

    var canOpen: Bool {
        alertId != nil && actionType != "deleted"
    }
}

enum ActivityStatus: String, CaseIterable, Identifiable {
    case created
    case triggered
    case paused
    case reactivated
    case deleted

    var id: String { rawValue }

    var label: String { ActivityMapping.actionLabel(rawValue) }

    static let defaultSelection: Set<ActivityStatus> = [.created, .triggered]

    static func summary(of selection: Set<ActivityStatus>) -> String {
        if selection.count == allCases.count {
            return "All"
        }
        let labels = allCases.filter(selection.contains).map(\.label)
        if labels.count <= 2 {
            return labels.joined(separator: ", ")
        }
        return "\(selection.count)"
    }

    static func storedSelection() -> Set<ActivityStatus> {
        guard let raw = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
            return defaultSelection
        }
        let parsed = Set(raw.compactMap(ActivityStatus.init(rawValue:)))
        return parsed.isEmpty ? defaultSelection : parsed
    }

    static func persist(_ selection: Set<ActivityStatus>) {
        UserDefaults.standard.set(selection.map(\.rawValue).sorted(), forKey: storageKey)
    }

    private static let storageKey = "activityStatusFilter"
}

enum RelativeTime {
    static func string(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "en_US")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
