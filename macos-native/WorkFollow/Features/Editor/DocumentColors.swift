import AppKit
import SwiftUI

/// 编辑器调色板：6 行 × 10 列，第一行是纯色，其余五行由浅到深。
/// 颜色以 `#rrggbb` 落进文档属性，Quill `color` / `background` 可直接互认。
enum DocumentColorPalette {
    /// 色板格子按位置编号：不同行会出现同一个颜色值，用色值当 `ForEach` 的 id
    /// 会让 SwiftUI 把重复项当成同一格丢掉（第五行后半段就是这样消失的）。
    struct Swatch: Identifiable, Equatable {
        let id: Int
        let hex: String
    }

    static let rows: [[String]] = [
        ["#ffffff", "#000000", "#0b7bff", "#00b8c4", "#00a95c", "#ff3b30", "#ff8a00", "#f5b800", "#7e4dd1", "#f04e86"],
        ["#f5f5f5", "#6e6e6e", "#dce9ff", "#d5f3f5", "#d9f3e3", "#ffddd9", "#ffe7cc", "#fff3cc", "#eadcff", "#ffdce8"],
        ["#dcdcdc", "#5a5a5a", "#a9c7ff", "#9fe3e8", "#a6e3c6", "#ffb3ac", "#ffc894", "#ffe58a", "#c9a9ff", "#ffb3cc"],
        ["#c2c2c2", "#464646", "#6ea4ff", "#55c8d2", "#5bc98f", "#ff7a6e", "#ffa94d", "#ffd54d", "#a374f0", "#ff7fa8"],
        ["#a6a6a6", "#333333", "#2f7bff", "#00a9b8", "#009250", "#e42d23", "#e27800", "#d49f00", "#6c3eb8", "#d43e73"],
        ["#8a8a8a", "#242424", "#0b4fd1", "#007a87", "#007a43", "#c81e16", "#c46600", "#b38600", "#5a2e9e", "#b82e5f"]
    ]

    static let swatches: [Swatch] = rows.enumerated().flatMap { row, colors in
        colors.enumerated().map { column, hex in Swatch(id: row * 10 + column, hex: hex) }
    }

    static let defaultHighlight = "#ffe98a"
}

extension NSColor {
    convenience init?(documentHex: String) {
        guard let normalized = QuillDeltaCodec.normalizedColor(documentHex),
              let value = UInt32(normalized.dropFirst(), radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                  green: CGFloat((value >> 8) & 0xff) / 255,
                  blue: CGFloat(value & 0xff) / 255,
                  alpha: 1)
    }
}

extension DocumentAlignment {
    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justify: .justified
        }
    }
}
