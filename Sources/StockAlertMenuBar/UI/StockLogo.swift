import AppKit
import SwiftUI

@MainActor
enum StockLogoStore {
    private static let cache = NSCache<NSString, NSImage>()
    private static var failed: Set<String> = []
    private static var inflight: [String: Task<NSImage?, Never>] = [:]

    static func image(for symbol: String) async -> NSImage? {
        let key = symbol.uppercased()
        if failed.contains(key) { return nil }
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if let existing = inflight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://api.elbstream.com/logos/symbol/\(encoded)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let image = NSImage(data: data),
                  image.size.width > 0
            else { return nil }
            return image
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        if let image {
            cache.setObject(image, forKey: key as NSString)
        } else {
            failed.insert(key)
        }
        return image
    }
}

struct StockMark: View {
    let symbol: String
    let actionType: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mark
            StatusDot(actionType: actionType)
                .offset(x: 2, y: 2)
        }
        .task(id: symbol) {
            image = await StockLogoStore.image(for: symbol)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        let shape = Circle()
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text(String(symbol.prefix(2)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.55))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1),
                lineWidth: 1
            )
        }
    }
}

struct StatusDot: View {
    let actionType: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(Palette.dot(actionType))
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .strokeBorder(
                        colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.92),
                        lineWidth: 1.5
                    )
            }
    }
}
