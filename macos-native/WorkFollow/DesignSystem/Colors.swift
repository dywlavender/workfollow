import AppKit
import SwiftUI

enum WFColors {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let content = Color(nsColor: .textBackgroundColor)
    static let secondarySurface = Color(nsColor: .controlBackgroundColor)
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.5)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.494, green: 0.533, blue: 1, alpha: 1)
            : NSColor(red: 0.357, green: 0.361, blue: 0.922, alpha: 1)
    })
    static let selection = accent.opacity(0.10)
    static let hover = Color.primary.opacity(0.04)
}
