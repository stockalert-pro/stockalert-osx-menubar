import AppKit
import Foundation

enum BrandAsset {
    static func image(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            return image
        }

        let fromSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/\(name).png", directoryHint: .notDirectory)
        return NSImage(contentsOf: fromSource)
    }
}
