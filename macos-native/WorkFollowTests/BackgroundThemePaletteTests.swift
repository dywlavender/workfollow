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

    // MARK: - 卡片面 vs 页面面（用户反馈：卡片「看起来不在同一层」）

    /// 复算主题页面的最终底色：底图 → 底纱 → 动效，与 `WorkfollowPageCanvas`
    /// 和 `NativeBackgroundMotion` 的公式一致。测试里重算而不是截图，是为了
    /// 让「差多少级」成为可断言的数字。
    private func pageColor(theme: NativeBackgroundTheme, dark: Bool,
                           intensity: NativeBackgroundIntensity,
                           artwork: NSColor, motion: NSColor) -> NSColor {
        let base = theme.isThemed ? intensity.opacity : 0
        let veil = resolved(theme.pageVeil(for: dark ? .dark : .light), dark: dark)
        let veilAlpha = intensity.pageOpacity(base: 0.90)
        let motionAlpha = base * NativeBackgroundMotion.opacity(for: dark ? .dark : .light,
                                                                intensity: intensity)
        var color = artwork
        for (top, alpha) in [(veil, veilAlpha), (motion, motionAlpha)] where alpha > 0 {
            let a = CGFloat(alpha) * top.alphaComponent
            color = NSColor(srgbRed: color.redComponent * (1 - a) + top.redComponent * a,
                            green: color.greenComponent * (1 - a) + top.greenComponent * a,
                            blue: color.blueComponent * (1 - a) + top.blueComponent * a,
                            alpha: 1)
        }
        return color
    }

    /// 把一层半透明色叠到不透明底色上。
    private func composite(_ top: NSColor, over bottom: NSColor) -> NSColor {
        let a = top.alphaComponent
        return NSColor(srgbRed: bottom.redComponent * (1 - a) + top.redComponent * a,
                       green: bottom.greenComponent * (1 - a) + top.greenComponent * a,
                       blue: bottom.blueComponent * (1 - a) + top.blueComponent * a,
                       alpha: 1)
    }

    private func maxChannelDelta(_ a: NSColor, _ b: NSColor) -> CGFloat {
        max(abs(a.redComponent - b.redComponent),
            abs(a.greenComponent - b.greenComponent),
            abs(a.blueComponent - b.blueComponent))
    }

    /// 卡片最终渲染出来的颜色——**与 `ThemedCardSurface` 的实现同一模型**：
    /// 主题开启时是 `fallback.opacity(cardSurfaceFlattening)` 叠在页面上；
    /// 主题关闭时就是 `fallback` 本身。测试必须走这条路径，否则会照不到
    /// 「压平层被不透明 fallback 盖掉」这类实现错误。
    private func cardColor(theme: NativeBackgroundTheme, dark: Bool,
                           page: NSColor, fallback: Color = WFColors.content) -> NSColor {
        let fill = resolved(fallback, dark: dark)
        guard theme.isThemed else { return fill }
        let flattened = fill.withAlphaComponent(fill.alphaComponent
            * CGFloat(theme.cardSurfaceFlattening))
        return composite(flattened, over: page)
    }

    /// 每个主题最重的动效图形色（气泡/云/贴纸/极光带取最饱和的一支）。
    private func motionColor(_ theme: NativeBackgroundTheme) -> NSColor {
        switch theme {
        case .peachSoda:
            return NSColor(srgbRed: 0xFF / 255, green: 0xC1 / 255, blue: 0x5E / 255, alpha: 1)
        case .mintCloud:
            return NSColor(srgbRed: 0x5F / 255, green: 0x87 / 255, blue: 0xF2 / 255, alpha: 1)
        case .creamSticker:
            return NSColor(srgbRed: 0xFF / 255, green: 0xC5 / 255, blue: 0x3D / 255, alpha: 1)
        case .auroraJelly:
            return NSColor(srgbRed: 0x6A / 255, green: 0x8D / 255, blue: 0xFF / 255, alpha: 1)
        case .none:
            return NSColor.white
        }
    }

    /// 各主题底图的浅色端点。
    private func artworkColor(_ theme: NativeBackgroundTheme) -> NSColor {
        switch theme {
        case .peachSoda:
            return NSColor(srgbRed: 0xFF / 255, green: 0xF9 / 255, blue: 0xF4 / 255, alpha: 1)
        case .mintCloud:
            return NSColor(srgbRed: 0xDC / 255, green: 0xF1 / 255, blue: 0xFF / 255, alpha: 1)
        case .creamSticker:
            return NSColor(srgbRed: 0xFF / 255, green: 0xF8 / 255, blue: 0xE9 / 255, alpha: 1)
        case .auroraJelly:
            return NSColor(srgbRed: 0xEF / 255, green: 0xF6 / 255, blue: 0xFF / 255, alpha: 1)
        case .none:
            return NSColor.white
        }
    }

    /// 主题关闭时卡片必须原样等于 `fallback`——无主题下的视觉不能变。
    func testCardSurfaceIsExactFallbackWhenThemeIsOff() {
        for dark in [false, true] {
            let page = resolved(WFColors.content, dark: dark)
            let card = cardColor(theme: .none, dark: dark, page: page)
            let expected = resolved(WFColors.content, dark: dark)
            XCTAssertEqual(maxChannelDelta(card, expected), 0, accuracy: 0.0001,
                           "无主题时卡片必须逐值等于原底色")
            XCTAssertEqual(card.alphaComponent, 1, accuracy: 0.0001,
                           "无主题时卡片必须不透明")
        }
    }

    /// 压平率不能实到把主题整块抹掉，也不能淡到压不住动效。
    func testCardFlatteningStaysInUsefulRange() {
        for theme in NativeBackgroundTheme.allCases where theme.isThemed {
            XCTAssertGreaterThan(theme.cardSurfaceFlattening, 0.70,
                                 "\(theme) 压平层过透，分区边界会消失")
            XCTAssertLessThan(theme.cardSurfaceFlattening, 0.97,
                              "\(theme) 压平层过实，等于没跟主题走")
        }
        XCTAssertEqual(NativeBackgroundTheme.none.cardSurfaceFlattening, 1, accuracy: 0.0001,
                       "无主题时必须完全不稀释")
    }

    // MARK: - 正文阅读面（五个编辑区统一）

    /// 阅读面的不透明度必须**低于**结构性压平层。
    ///
    /// 两者是不同语义：阅读面（0.58）承载正文，要透、要让用户看见主题；
    /// 压平层（0.86）给看板列/时间线定分区边界，必须更实。若两者接近，
    /// 说明有人把正文编辑区又改回"实心色块"了——那正是用户反馈的
    /// 「和笔记不在同一层」。
    func testReadingSurfaceIsMoreTransparentThanStructuralFlattening() {
        let reading = WorkfollowReadingSurface().opacity
        XCTAssertLessThan(reading, 0.70,
                          "阅读面太实，正文区会变回不透明色块")
        for theme in NativeBackgroundTheme.allCases where theme.isThemed {
            XCTAssertLessThan(reading, theme.cardSurfaceFlattening,
                "\(theme) 阅读面必须比结构性压平层更透")
        }
    }

    /// 阅读面之下的正文区变化必须被压住——阈值以**笔记页现状**为准。
    ///
    /// 笔记页/任务详情页一直用 58% 阅读面，实测最坏摆幅 0.132（奶油贴纸·浓档）。
    /// 摘要、手记、会议纪要统一到这个值后，五个编辑区在主题下是**同一种透法**，
    /// 所以阈值取 0.14：既能挡住「退回到不透明色块」的回归（那是 0.31），
    /// 又不会把笔记页本身判成不合规。
    func testReadingSurfaceKeepsContentUniform() {
        let reading = CGFloat(WorkfollowReadingSurface().opacity)
        for theme in NativeBackgroundTheme.allCases where theme.isThemed {
            let artwork = artworkColor(theme)
            let motion = motionColor(theme)
            for intensity in NativeBackgroundIntensity.allCases {
                let flat = pageColor(theme: theme, dark: false, intensity: intensity,
                                     artwork: artwork, motion: artwork)
                let busy = pageColor(theme: theme, dark: false, intensity: intensity,
                                     artwork: artwork, motion: motion)
                let contentFlat = composite(
                    resolved(WFColors.content, dark: false).withAlphaComponent(reading), over: flat)
                let contentBusy = composite(
                    resolved(WFColors.content, dark: false).withAlphaComponent(reading), over: busy)
                let spread = maxChannelDelta(contentFlat, contentBusy)
                XCTAssertLessThanOrEqual(spread, 0.14,
                    "\(theme) \(intensity) 浅色：正文区在空白处与动效处的通道差 "
                    + String(format: "%.3f", spread) + " 超过 0.14"
                    + "（笔记页现状上限；退回不透明色块会到 0.31）")
            }
        }
    }

    /// 阅读面的默认不透明度必须落在可读区间：太透正文对比不足，太实又变成色块。
    func testReadingSurfaceOpacityStaysReadable() {
        let reading = WorkfollowReadingSurface().opacity
        XCTAssertGreaterThan(reading, 0.40,
                             "阅读面过透，正文对比会不足")
        XCTAssertLessThan(reading, 0.80,
                          "阅读面过实，正文区会变回不透明色块")
    }
}
