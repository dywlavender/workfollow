import AppKit
import SwiftUI

extension DocumentInk {
    var nativeColor: NSColor {
        switch self {
        case .accent: NSColor(WFColors.accent)
        case .danger: NSColor(WFColors.danger)
        case .argb(let value): NSColor(WFListPalette.swatch(value))
        }
    }
    func resolved(in appearance: NSAppearance) -> NSColor {
        var value = nativeColor
        appearance.performAsCurrentDrawingAppearance {
            value = nativeColor.usingColorSpace(.deviceRGB) ?? nativeColor
        }
        return value
    }
}

extension Set where Element == DocumentMark {
    var documentInk: DocumentInk? {
        compactMap { if case .ink(let value) = $0 { return value }; return nil }.first
    }
}
