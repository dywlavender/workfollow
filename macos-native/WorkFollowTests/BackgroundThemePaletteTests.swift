import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

final class BackgroundThemePaletteTests: XCTestCase {
    private func resolved(_ color: Color, dark: Bool) -> NSColor {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var result = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return result
    }

    private func delta(_ a: NSColor, _ b: NSColor) -> Double {
        abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent)
    }

    func testThemedSelectionFillsAreOpaqueAndDistinct() {
        let themes: [NativeBackgroundTheme] = [.peachSoda, .mintCloud, .creamSticker, .auroraJelly]
        for dark in [false, true] {
            let fills = themes.map { resolved($0.selectionFill, dark: dark) }
            for (index, fill) in fills.enumerated() {
                XCTAssertEqual(fill.alphaComponent, 1, accuracy: 0.01,
                               "\(themes[index]) 选中底色必须不透明")
            }
            for i in 0..<fills.count {
                for j in (i + 1)..<fills.count {
                    XCTAssertGreaterThan(delta(fills[i], fills[j]), 0.06,
                                         "\(themes[i]) 与 \(themes[j]) 的选中底色应看得出区别")
                }
            }
        }
    }

    func testSelectionStandsOutFromInputFill() {
        for theme in NativeBackgroundTheme.allCases where theme.isThemed {
            for dark in [false, true] {
                let selection = resolved(theme.selectionFill, dark: dark)
                let input = resolved(theme.inputFill, dark: dark)
                XCTAssertGreaterThan(delta(selection, input), 0.08,
                                     "\(theme) 的选中底色与输入框底色差异太小")
                XCTAssertEqual(input.alphaComponent, 1, accuracy: 0.01)
            }
        }
    }

    func testNonThemedSelectionStaysNeutral() {
        for dark in [false, true] {
            let fill = resolved(NativeBackgroundTheme.none.selectionFill, dark: dark)
            let least = min(fill.redComponent, fill.greenComponent, fill.blueComponent)
            let most = max(fill.redComponent, fill.greenComponent, fill.blueComponent)
            XCTAssertLessThan(most - least, 0.06, "无背景应保持中性灰")
        }
    }
}
