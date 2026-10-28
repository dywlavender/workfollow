import AppKit

final class DocumentInlineSymbolCell: NSTextAttachmentCell {
    let symbol: DocumentInlineSymbol
    let tint: NSColor

    init(symbol: DocumentInlineSymbol, tint: NSColor = .secondaryLabelColor) {
        self.symbol = symbol; self.tint = tint
        super.init(textCell: symbol.textFallback)
    }
    required init(coder: NSCoder) {
        symbol = (coder.decodeObject(forKey: "symbol") as? String).flatMap(DocumentInlineSymbol.init(rawValue:)) ?? .calendar
        tint = coder.decodeObject(forKey: "symbolTint") as? NSColor ?? .secondaryLabelColor
        super.init(coder: coder)
    }
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(symbol.rawValue, forKey: "symbol"); coder.encode(tint, forKey: "symbolTint")
    }

    override func cellSize() -> NSSize { NSSize(width: 14, height: 14) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -2) }
    override func draw(withFrame frame: NSRect, in view: NSView?) {
        guard let image = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular)) else {
            super.draw(withFrame: frame, in: view); return
        }
        let size = image.size
        let scale = min(12 / max(1, size.width), 12 / max(1, size.height))
        let bounds = NSRect(x: frame.midX - size.width * scale / 2,
                            y: frame.midY - size.height * scale / 2,
                            width: size.width * scale, height: size.height * scale)
        let appearance = view?.window?.effectiveAppearance ?? view?.effectiveAppearance ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            let colored = NSImage(size: bounds.size)
            colored.lockFocus()
            let rect = NSRect(origin: .zero, size: bounds.size)
            image.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceIn)
            colored.unlockFocus()
            colored.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: nil)
        }
    }
}
