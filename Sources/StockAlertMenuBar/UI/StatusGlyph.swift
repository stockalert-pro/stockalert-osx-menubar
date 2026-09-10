import AppKit
import SwiftUI

struct StatusGlyph: View {
    let triggered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let mark = colorScheme == .dark ? Self.dark : Self.light
        Group {
            if triggered {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .foregroundStyle(Color(nsColor: Palette.successNS))
            } else {
                Image(nsImage: mark)
                    .renderingMode(.original)
            }
        }
        .frame(width: Self.pointSize.width, height: Self.pointSize.height)
        .accessibilityLabel(triggered ? "StockAlert.pro, new alert" : "StockAlert.pro")
    }

    private static let pointSize = NSSize(width: 18, height: 18)
    private static let dark = sized("BellOnDark")
    private static let light = sized("BellOnLight")

    private static func sized(_ name: String) -> NSImage {
        let image = BrandAsset.image(named: name) ?? NSImage(size: pointSize)
        image.size = pointSize
        image.isTemplate = false
        return image
    }
}
