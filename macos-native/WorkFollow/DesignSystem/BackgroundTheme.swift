import AppKit
import SwiftUI

/// 可选背景主题。主页面用半透明内容面透出底图；弹层、下拉与对话框用不透明的
/// 主题底色，浮在任意页面上时文字对比不下降。
enum NativeBackgroundTheme: String, CaseIterable, Identifiable {
    case none
    case peachSoda
    case mintCloud
    case creamSticker
    case auroraJelly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无背景"
        case .peachSoda: return "蜜桃汽水"
        case .mintCloud: return "薄荷云朵"
        case .creamSticker: return "奶油贴纸"
        case .auroraJelly: return "极光果冻"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "保持纯色"
        case .peachSoda: return "暖光斑与上浮气泡"
        case .mintCloud: return "天空渐变与慢速云层"
        case .creamSticker: return "奶油底与摇摆贴纸"
        case .auroraJelly: return "极光色带与星点"
        }
    }

    var isThemed: Bool { self != .none }

    func railFill(for scheme: ColorScheme) -> Color {
        chromeFill(rail: true, scheme: scheme)
    }

    func navigationFill(for scheme: ColorScheme) -> Color {
        chromeFill(rail: false, scheme: scheme)
    }

    /// 弹层/下拉/对话框的底色。必须**不透明**：它们浮在任意页面或编辑器上方，
    /// 半透明会让下面的文字透出来。只混入很少的主题色，保持深色文字对比。
    func popupFill(for scheme: ColorScheme) -> Color {
        guard isThemed else { return WFColors.content }
        let dark = scheme == .dark
        switch self {
        case .none:
            return WFColors.content
        case .peachSoda:
            return bgColor(dark ? 0x261F1D : 0xFFF8F2)
        case .mintCloud:
            return bgColor(dark ? 0x1A2623 : 0xF3FCF9)
        case .creamSticker:
            return bgColor(dark ? 0x272219 : 0xFFFAED)
        case .auroraJelly:
            return bgColor(dark ? 0x161D28 : 0xF4F9FF)
        }
    }

    /// 弹层底色；主题关闭时保留调用方原来的底色（专注页用 FocusTheme.canvas 等）。
    func popupFillOrFallback(_ fallback: Color, for scheme: ColorScheme) -> Color {
        isThemed ? popupFill(for: scheme) : fallback
    }

    /// 列表 / 看板 / 时间线共用**同一个**选中行底色。每个主题用自己色相的浅色块：
    /// 极光偏蓝紫、蜜桃偏暖橙、薄荷偏绿、奶油偏琥珀。之前四套主题共用一个近白蓝
    /// `#EFF3FE`，在蜜桃/薄荷/奶油画布上几乎看不出选中；这里保证一眼可分。
    /// 关闭主题时沿用滴答实测的中性灰 `listSelection`。
    var selectionFill: Color {
        switch self {
        case .none: return WFColors.listSelection
        case .peachSoda: return adaptiveColor(light: 0xFFDCC4, dark: 0x4C3428)
        case .mintCloud: return adaptiveColor(light: 0xCFEFE1, dark: 0x21423A)
        case .creamSticker: return adaptiveColor(light: 0xF8E4B5, dark: 0x4A3A1B)
        case .auroraJelly: return adaptiveColor(light: 0xD9E1FF, dark: 0x333A5F)
        }
    }

    /// 主题页面上的输入框底色（快速添加、笔记搜索）：与选中同色相、更接近白的
    /// 常驻表面，靠一层细描边定形。关闭主题时回到各输入框自己的原底色。
    var inputFill: Color {
        switch self {
        case .none: return WFColors.quickAddIdleFill
        case .peachSoda: return adaptiveColor(light: 0xFFF7F0, dark: 0x2E2521)
        case .mintCloud: return adaptiveColor(light: 0xF1FBF7, dark: 0x1E2D28)
        case .creamSticker: return adaptiveColor(light: 0xFFFAEC, dark: 0x2F2820)
        case .auroraJelly: return adaptiveColor(light: 0xF3F8FF, dark: 0x1B2431)
        }
    }

    /// 主页面底纱的颜色。整窗画布与各页面的 `ThemedPageSurface` 共用同一个值，
    /// 后者在画布生效时会让出底色，两层不会叠成近白。
    func pageVeil(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(.sRGB, red: 0.10, green: 0.105, blue: 0.12, opacity: 1)
            : Color.white
    }

    private func chromeFill(rail: Bool, scheme: ColorScheme) -> Color {
        guard isThemed else { return rail ? WFColors.canvas : WFColors.content }
        let dark = scheme == .dark
        switch self {
        case .none:
            return rail ? WFColors.canvas : WFColors.content
        case .peachSoda:
            return dark
                ? (rail ? bgColor(0x261D1F, alpha: 0.60) : bgColor(0x281F21, alpha: 0.78))
                : (rail ? bgColor(0xFFF6EE, alpha: 0.60) : bgColor(0xFFF9F2, alpha: 0.76))
        case .mintCloud:
            return dark
                ? (rail ? bgColor(0x162423, alpha: 0.60) : bgColor(0x182725, alpha: 0.78))
                : (rail ? bgColor(0xEEFAF8, alpha: 0.58) : bgColor(0xF2FCF8, alpha: 0.76))
        case .creamSticker:
            return dark
                ? (rail ? bgColor(0x2B251D, alpha: 0.60) : bgColor(0x2D271E, alpha: 0.78))
                : (rail ? bgColor(0xFFF8E8, alpha: 0.58) : bgColor(0xFFFAEE, alpha: 0.76))
        case .auroraJelly:
            return dark
                ? (rail ? bgColor(0x111620, alpha: 0.55) : bgColor(0x131924, alpha: 0.74))
                : (rail ? bgColor(0xF2F8FF, alpha: 0.55) : bgColor(0xF5FAFF, alpha: 0.74))
        }
    }
}

enum NativeBackgroundIntensity: String, CaseIterable, Identifiable {
    case soft, medium, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: return "淡"
        case .medium: return "中"
        case .full: return "浓"
        }
    }

    var opacity: Double {
        switch self {
        case .soft: return 0.55
        case .medium: return 0.8
        case .full: return 1
        }
    }

    /// 页面底纱的不透明度：越淡底纱越实、主题越弱。
    func pageOpacity(base: Double) -> Double {
        let delta: Double
        switch self {
        case .soft: delta = 0.04
        case .medium: delta = 0
        case .full: delta = -0.04
        }
        return min(0.96, max(0.70, base + delta))
    }
}

private struct WorkFollowBackgroundThemeKey: EnvironmentKey {
    static let defaultValue: NativeBackgroundTheme = .none
}

private struct WorkFollowBackgroundIntensityKey: EnvironmentKey {
    static let defaultValue: NativeBackgroundIntensity = .medium
}

private struct WorkFollowPageCanvasKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var workfollowBackgroundTheme: NativeBackgroundTheme {
        get { self[WorkFollowBackgroundThemeKey.self] }
        set { self[WorkFollowBackgroundThemeKey.self] = newValue }
    }

    var workfollowBackgroundIntensity: NativeBackgroundIntensity {
        get { self[WorkFollowBackgroundIntensityKey.self] }
        set { self[WorkFollowBackgroundIntensityKey.self] = newValue }
    }

    /// 主窗口外壳已经铺了整窗画布：页面与导航列不再各自铺底，
    /// 否则多栏页面会在列边界出现深浅台阶。弹层、独立窗口不设置这个值，
    /// 仍由 `ThemedPageSurface` 自己铺底。
    var workfollowPageCanvasActive: Bool {
        get { self[WorkFollowPageCanvasKey.self] }
        set { self[WorkFollowPageCanvasKey.self] = newValue }
    }
}

/// AppKit 自建的面板（编辑器浮层、快速添加、提醒卡等）在窗口之外另建
/// `NSHostingView`，拿不到主窗口的 SwiftUI 环境。`AppEnvironment` 把当前主题
/// 同步到这里，宿主在创建根视图时补上，弹层底色才能和主界面一致。
@MainActor
enum NativeThemeBridge {
    static var theme: NativeBackgroundTheme = .none
    static var intensity: NativeBackgroundIntensity = .medium
    static var material: WFAppearanceMaterial = .classic
}

extension View {
    @MainActor
    func workfollowNativeTheme() -> some View {
        environment(\.workfollowBackgroundTheme, NativeThemeBridge.theme)
            .environment(\.workfollowBackgroundIntensity, NativeThemeBridge.intensity)
            .environment(\.workfollowMaterial, NativeThemeBridge.material)
    }
}

/// 主页面内容面的半透明底：主题开启时让窗口底图透上来，正文墨色不动。
/// 0.90 ≈ 只透 10% 背景；贴纸/云朵会变成很淡的色块，不会抢文字。
/// `opacity` 越小，主题越明显。浮层、弹窗和卡片用 `workfollowPopupSurface`
/// 或各自的不透明底色，避免叠出两层内容面。
struct ThemedPageSurface: View {
    var opacity: Double = 0.90

    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.workfollowBackgroundIntensity) private var intensity
    @Environment(\.workfollowPageCanvasActive) private var canvasActive
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if theme.isThemed, canvasActive {
            // 整窗画布已经是同一层底纱，再铺一次会把主题压回近白，
            // 列与列之间也会因为各自的 opacity 出现深浅台阶。
            Color.clear
        } else if theme.isThemed {
            theme.pageVeil(for: colorScheme).opacity(intensity.pageOpacity(base: opacity))
        } else {
            WFColors.content
        }
    }
}

extension View {
    func workfollowPageSurface(_ opacity: Double = WFPageSurface.veilOpacity) -> some View {
        background { ThemedPageSurface(opacity: opacity) }
    }
}

/// 页面底纱（铺在墙纸之上、内容之下的一层）的统一不透明度令牌。
/// 各工作区页面都继承这一档，避免页与页之间忽浓忽淡。
enum WFPageSurface {
    static let veilOpacity: Double = 0.90
}

/// 主窗口的整页底色：铺在墙纸之上、页面内容之下，整窗只有这一层。
///
/// 左起依次接续图标栏、二级导航和正文的底色，导航列右侧用一段渐变过渡到
/// 正文底纱。页面与导航列在画布生效时都让出底色，多栏页面（列表 / 详情 /
/// 编辑器 / AI 面板）因此共用同一层底色，列边界不会再出现深浅台阶。
struct WorkfollowPageCanvas: View {
    let theme: NativeBackgroundTheme
    var intensity: NativeBackgroundIntensity = .medium
    /// 图标栏 +（显示时）二级导航列的总宽。
    var leadingWidth: CGFloat = RailMetrics.width

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workfollowMaterial) private var material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if theme.isThemed {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let railEdge = min(RailMetrics.width, width)
                let navEdge = min(max(leadingWidth, railEdge), width)
                // 玻璃模式下图标栏/导航列自己画玻璃，画布让出背景，
                // 否则玻璃只会模糊一层已经着色的渐变，看不到壁纸。
                let glass = WFGlassSupport.isActive(material,
                                                    reduceTransparency: reduceTransparency || WFGlassSupport.systemReduceTransparency)
                let rail = glass ? Color.clear : theme.railFill(for: colorScheme)
                // 没有二级导航时，图标栏直接过渡到正文底色。
                let chrome = glass ? Color.clear
                    : leadingWidth > RailMetrics.width + 1
                        ? theme.navigationFill(for: colorScheme)
                        : theme.railFill(for: colorScheme)
                let fade = min(max(width * 0.12, 96), 180)
                let fadeEnd = min(width, navEdge + fade)
                let veil = theme.pageVeil(for: colorScheme)
                    .opacity(intensity.pageOpacity(base: 0.90))
                LinearGradient(stops: [
                    .init(color: rail, location: 0),
                    .init(color: rail, location: railEdge / width),
                    .init(color: chrome, location: navEdge / width),
                    .init(color: veil, location: fadeEnd / width),
                    .init(color: veil, location: 1)
                ], startPoint: .leading, endPoint: .trailing)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// 正文阅读面：压在主题背景之上的内容色薄纱，把文字后面的底图和动效洗淡。
/// 页面、侧栏和操作栏仍保留原浓度，只有承载正文的编辑区使用。
struct WorkfollowReadingSurface: View {
    var opacity: Double = 0.58

    @Environment(\.workfollowBackgroundTheme) private var theme

    var body: some View {
        if theme.isThemed {
            WFColors.content.opacity(opacity)
        } else {
            Color.clear
        }
    }
}

extension View {
    /// 编辑面板的页面底：主题底纱之上再铺一层正文阅读面。
    func workfollowEditorPageSurface(_ opacity: Double = 0.90) -> some View {
        background {
            ZStack {
                ThemedPageSurface(opacity: opacity)
                WorkfollowReadingSurface()
            }
        }
    }
}

/// 独立窗口（笔记/任务悬浮编辑窗）的整窗主题底：和主窗口的页面同源——
/// 底图在下、底纱在中、动效在上——但没有图标栏/导航列的横向渐变。
/// 最上面再压一层正文阅读面：悬浮窗整块都是正文，图案不能和文字抢对比。
/// 主题关闭时退回原来的不透明内容色。
struct WorkfollowStandalonePageBackground: View {
    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.workfollowBackgroundIntensity) private var intensity
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("backgroundAnimated") private var animated = true

    var body: some View {
        if theme.isThemed {
            ZStack {
                WorkFollowBackgroundView(theme: theme, intensity: intensity,
                                         animated: false, layer: .base)
                theme.pageVeil(for: colorScheme)
                    .opacity(intensity.pageOpacity(base: 0.90))
                WorkFollowBackgroundView(theme: theme, intensity: intensity,
                                         animated: animated, layer: .motion)
                    .opacity(NativeBackgroundMotion.opacity(for: colorScheme, intensity: intensity))
                WorkfollowReadingSurface()
            }
        } else {
            WFColors.content
        }
    }
}

/// 弹层/下拉/对话框的不透明主题底。`fallback` 用于主题关闭时保留各弹窗原来的
/// 底色（例如专注记录用 FocusTheme.canvas、系统 sheet 用 canvas）。
struct ThemedPopupSurface: View {
    var fallback: Color = WFColors.content

    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WFGlassSurface(shape: Rectangle(),
                       fallback: theme.isThemed ? theme.popupFill(for: colorScheme) : fallback)
    }
}

extension View {
    func workfollowPopupSurface(fallback: Color = WFColors.content) -> some View {
        background { ThemedPopupSurface(fallback: fallback) }
    }
}

/// 背景可以拆成两层用：底图（渐变/柔光）留在页面底纱下面，动态元素
/// （气泡、云朵、贴纸、极光带与星点）叠在底纱上面。底纱原本会把动效一起
/// 洗成近白，分层后动态才看得清，同时页面底色保持原来的浓度。
enum WorkFollowBackgroundLayer: Equatable {
    case full
    case base
    case motion

    var showsBase: Bool { self != .motion }
    var showsMotion: Bool { self != .base }
}

/// 叠在页面底纱之上的动效层强度。随浓度缩放，但保一个下限：调到“淡”
/// 时页面变白，气泡/云朵仍然要能看见，否则又回到“动态看不清楚”。
enum NativeBackgroundMotion {
    static func opacity(for scheme: ColorScheme,
                        intensity: NativeBackgroundIntensity) -> Double {
        let base = scheme == .dark ? 0.34 : 0.42
        return max(0.30, base * intensity.opacity)
    }
}

/// 四套背景共用的外壳；静态图案只绘制一次，动效交给独立图层。
struct WorkFollowBackgroundView: View {
    let theme: NativeBackgroundTheme
    var intensity: NativeBackgroundIntensity = .full
    var animated: Bool = true
    var layer: WorkFollowBackgroundLayer = .full

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMoving: Bool {
        theme.isThemed && animated && !reduceMotion && controlActiveState != .inactive
    }

    var body: some View {
        NativeBackgroundRenderer(theme: theme, dark: colorScheme == .dark,
                                 animated: isMoving, backgroundLayer: layer)
        .opacity(intensity.opacity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    static func artwork(theme: NativeBackgroundTheme, dark: Bool, size: CGSize,
                        time: TimeInterval, layer: WorkFollowBackgroundLayer) -> some View {
        switch theme {
        case .none:
            Color.clear
        case .peachSoda:
            PeachSodaScene(size: size, dark: dark, time: time, layer: layer)
        case .mintCloud:
            MintCloudScene(size: size, dark: dark, time: time, layer: layer)
        case .creamSticker:
            CreamStickerScene(size: size, dark: dark, time: time, layer: layer)
        case .auroraJelly:
            AuroraJellyScene(size: size, dark: dark, time: time, layer: layer)
        }
    }
}

// MARK: - 蜜桃汽水

private struct PeachSodaScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval
    let layer: WorkFollowBackgroundLayer



    var body: some View {
        let w = size.width
        let h = size.height
        let unit = max(w, h)
        ZStack {
            if layer.showsBase {
                LinearGradient(colors: dark
                    ? [bgColor(0x171113), bgColor(0x1F1518)]
                    : [bgColor(0xFFF9F4), bgColor(0xFFF6EC)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)

                SoftBlob(color: dark ? bgColor(0xD97A55) : bgColor(0xFF9B6E))
                    .frame(width: unit * 0.56, height: unit * 0.56)
                    .position(x: w * 0.04 + drift(time, period: 26) * w * 0.035,
                              y: h * 0.02 + drift(time, period: 33, phase: 0.3) * h * 0.035)

                SoftBlob(color: dark ? bgColor(0xC9973A) : bgColor(0xFFD166))
                    .frame(width: unit * 0.46, height: unit * 0.46)
                    .position(x: w * 0.96 + drift(time, period: 31, phase: 0.5) * -w * 0.03,
                              y: h * 0.04 + drift(time, period: 24, phase: 0.7) * h * 0.03)

                SoftBlob(color: dark ? bgColor(0xC25C7C) : bgColor(0xFF9FBA))
                    .frame(width: unit * 0.62, height: unit * 0.62)
                    .position(x: w * 0.72 + drift(time, period: 36, phase: 0.2) * w * 0.04,
                              y: h * 1.02 + drift(time, period: 29, phase: 0.6) * -h * 0.03)

                SoftBlob(color: dark ? bgColor(0x8A7350) : bgColor(0xFFF2CE))
                    .frame(width: unit * 0.36, height: unit * 0.36)
                    .position(x: w * 0.34 + drift(time, period: 23, phase: 0.8) * -w * 0.025,
                              y: h * 0.98 + drift(time, period: 27, phase: 0.4) * h * 0.02)
                    .opacity(dark ? 0.55 : 0.9)
            }


        }
        .frame(width: w, height: h)
        .clipped()
    }
}

private struct SoftBlob: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Circle().fill(RadialGradient(
                stops: [
                    .init(color: color.opacity(0.95), location: 0),
                    .init(color: color.opacity(0.55), location: 0.55),
                    .init(color: color.opacity(0), location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: min(proxy.size.width, proxy.size.height) * 0.5))
        }
    }
}

private struct SodaBubble: View {
    let diameter: CGFloat
    let dark: Bool
    let tint: Color

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: .white.opacity(dark ? 0.30 : 0.55), location: 0),
                    .init(color: tint.opacity(dark ? 0.65 : 0.65), location: 0.58),
                    .init(color: tint.opacity(dark ? 0.45 : 0.72), location: 1)
                ],
                center: UnitPoint(x: 0.32, y: 0.28),
                startRadius: 0,
                endRadius: max(1, diameter * 0.5)))
            .overlay(Circle().strokeBorder(tint.opacity(dark ? 0.75 : 0.9), lineWidth: 1.4))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - 薄荷云朵

private struct MintCloudScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval
    let layer: WorkFollowBackgroundLayer

    var body: some View {
        let w = size.width
        let h = size.height
        ZStack {
            if layer.showsBase {
                LinearGradient(colors: dark
                    ? [bgColor(0x0C1B24), bgColor(0x0E2420), bgColor(0x1C1B14)]
                    : [bgColor(0xDCF1FF), bgColor(0xE8F9F2), bgColor(0xFFF7E6)],
                    startPoint: .top, endPoint: .bottom)

                Ellipse()
                    .fill(RadialGradient(colors: [
                        bgColor(0xFFF3B8, alpha: dark ? 0.16 : 0.82),
                        bgColor(0xFFF3B8, alpha: 0)
                    ], center: .center, startRadius: 0, endRadius: max(1, w * 0.34)))
                    .frame(width: w * 0.62, height: h * 0.55)
                    .position(x: w * 0.92, y: h * 0.02)
            }


        }
        .frame(width: w, height: h)
        .clipped()
    }

    /// 云不能再用纯白：底纱压过之后白云和白底没有区别。改成上白下蓝的
    /// 渐变云，再给两朵大云画上表情，靠蓝色轮廓和墨点在背景里留形。
    fileprivate func cloud(width: CGFloat, height: CGFloat, face: Bool) -> some View {
        CuteCloudShape()
            .fill(LinearGradient(
                colors: dark
                    ? [Color.white.opacity(0.22), Color.white.opacity(0.10)]
                    : [Color.white, bgColor(0xA9D3E8)],
                startPoint: .top, endPoint: .bottom))
            .frame(width: width, height: height)
            .overlay {
                if face {
                    StickerFace(size: height * 0.9,
                                ink: (dark ? bgColor(0xD7E8F2) : bgColor(0x5C8FB3))
                                    .opacity(dark ? 0.55 : 1))
                        .offset(y: height * 0.14)
                }
            }
            .shadow(color: dark ? .clear : bgColor(0x7FAEC8).opacity(0.45),
                    radius: height * 0.28, y: height * 0.18)
    }


}

struct CuteCloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.addRoundedRect(in: CGRect(x: 0, y: h * 0.40, width: w, height: h * 0.60),
                            cornerSize: CGSize(width: h * 0.30, height: h * 0.30))
        path.addEllipse(in: CGRect(x: w * 0.14, y: 0, width: h * 0.94, height: h * 0.94))
        path.addEllipse(in: CGRect(x: w * 0.46, y: h * 0.14, width: h * 0.74, height: h * 0.74))
        return path
    }
}

struct CuteSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let w = rect.width * 0.5
        let h = rect.height * 0.5
        var path = Path()
        path.move(to: CGPoint(x: cx, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy),
                          control: CGPoint(x: cx + w * 0.22, y: cy - h * 0.22))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY),
                          control: CGPoint(x: cx + w * 0.22, y: cy + h * 0.22))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: cy),
                          control: CGPoint(x: cx - w * 0.22, y: cy + h * 0.22))
        path.addQuadCurve(to: CGPoint(x: cx, y: rect.minY),
                          control: CGPoint(x: cx - w * 0.22, y: cy - h * 0.22))
        path.closeSubpath()
        return path
    }
}

// MARK: - 奶油贴纸

private struct CreamStickerScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval
    let layer: WorkFollowBackgroundLayer

    var body: some View {
        let w = size.width
        let h = size.height
        let unit = max(h, w * 0.5)
        ZStack {
            if layer.showsBase {
                (dark ? bgColor(0x1E1A15) : bgColor(0xFFF8E9))

                Ellipse()
                    .fill(RadialGradient(colors: [
                        dark ? bgColor(0x3A3022, alpha: 0.7) : bgColor(0xFFFDF6),
                        .clear
                    ], center: .center, startRadius: 0, endRadius: max(1, w * 0.55)))
                    .frame(width: w * 0.9, height: h * 0.9)
                    .position(x: w * 0.5, y: h * 0.18)
            }


        }
        .frame(width: w, height: h)
        .clipped()
    }


}

private struct StickerFace: View {
    let size: CGFloat
    let ink: Color

    var body: some View {
        ZStack {
            HStack(spacing: size * 0.24) {
                Circle().fill(ink).frame(width: size * 0.10, height: size * 0.10)
                Circle().fill(ink).frame(width: size * 0.10, height: size * 0.10)
            }
            .offset(y: -size * 0.06)

            HStack(spacing: size * 0.34) {
                Ellipse().fill(bgColor(0xFF9FB2).opacity(0.75))
                    .frame(width: size * 0.11, height: size * 0.075)
                Ellipse().fill(bgColor(0xFF9FB2).opacity(0.75))
                    .frame(width: size * 0.11, height: size * 0.075)
            }
            .offset(y: size * 0.08)

            SmileShape()
                .stroke(ink, style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round))
                .frame(width: size * 0.30, height: size * 0.13)
                .offset(y: size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct SunSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(bgColor(0xF5B029))
                    .frame(width: size * 0.055, height: size * 0.17)
                    .offset(y: -size * 0.44)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            Circle().fill(bgColor(0xFFC53D)).frame(width: size * 0.70, height: size * 0.70)
            StickerFace(size: size * 0.40, ink: bgColor(0x7A5410))
        }
        .frame(width: size, height: size)
    }
}

private struct FlowerSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(bgColor(0xFF9FB2))
                    .frame(width: size * 0.48, height: size * 0.48)
                    .offset(y: -size * 0.21)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
            Circle().fill(bgColor(0xFFC53D)).frame(width: size * 0.44, height: size * 0.44)
            StickerFace(size: size * 0.26, ink: bgColor(0x7A5410))
        }
        .frame(width: size, height: size)
    }
}

private struct StickerStar: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            CuteSparkleShape().fill(bgColor(0x9EC5FF)).frame(width: size, height: size)
            StickerFace(size: size * 0.30, ink: bgColor(0x3B5C94))
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
    }
}

private struct CloudSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            CuteCloudShape()
                .fill(Color.white)
                .frame(width: size, height: size * 0.62)
            StickerFace(size: size * 0.28, ink: bgColor(0x7FA6C9))
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size * 0.62)
    }
}

private struct LeafSticker: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            LeafShape().fill(bgColor(0x8FD9A8))
            LeafVein()
                .stroke(bgColor(0x4F9E71), style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.height * 0.70),
                      control2: CGPoint(x: rect.width * 0.72, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.height * 0.62),
                      control2: CGPoint(x: rect.width * 0.74, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct LeafVein: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.28),
                          control: CGPoint(x: rect.width * 0.44, y: rect.height * 0.56))
        return path
    }
}

private struct HeartSticker: View {
    let size: CGFloat

    var body: some View {
        HeartShape()
            .fill(bgColor(0xFFB3C4))
            .frame(width: size, height: size)
    }
}

private struct HeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.92))
        path.addCurve(to: CGPoint(x: w * 0.03, y: h * 0.30),
                      control1: CGPoint(x: w * 0.20, y: h * 0.78),
                      control2: CGPoint(x: w * 0.02, y: h * 0.56))
        path.addCurve(to: CGPoint(x: w * 0.50, y: h * 0.26),
                      control1: CGPoint(x: w * 0.04, y: h * 0.06),
                      control2: CGPoint(x: w * 0.35, y: h * 0.02))
        path.addCurve(to: CGPoint(x: w * 0.97, y: h * 0.30),
                      control1: CGPoint(x: w * 0.65, y: h * 0.02),
                      control2: CGPoint(x: w * 0.96, y: h * 0.06))
        path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.92),
                      control1: CGPoint(x: w * 0.98, y: h * 0.56),
                      control2: CGPoint(x: w * 0.80, y: h * 0.78))
        path.closeSubpath()
        return path
    }
}

// MARK: - 极光果冻

private struct AuroraJellyScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval
    let layer: WorkFollowBackgroundLayer

    var body: some View {
        let w = size.width
        let h = size.height
        ZStack {
            if layer.showsBase {
                (dark ? bgColor(0x080B12) : bgColor(0xEFF6FF))
            }


        }
        .frame(width: w, height: h)
        .clipped()
    }


}

/// Uses the same artwork as the SwiftUI scenes above, but keeps each moving
/// element as a reusable bitmap. Positions and opacity animate independently.
@MainActor
enum BackgroundArtwork {
    static func sprites(theme: NativeBackgroundTheme, dark: Bool, size: CGSize,
                        scale: CGFloat, layer: WorkFollowBackgroundLayer) -> [BackgroundSprite] {
        guard theme.isThemed else { return [] }
        let w = size.width, h = size.height
        let prefix = "\(theme.rawValue)|\(dark)"
        var result: [BackgroundSprite] = []
        func add<V: View>(_ name: String, _ view: V, width: CGFloat, height: CGFloat,
                          x: CGFloat, y: CGFloat, padding: CGFloat = 0,
                          opacity: Float = 1, blend: String? = nil,
                          motions: [BackgroundLayerMotion] = [], rasterScale: CGFloat? = nil) {
            let artworkSize = CGSize(width: width + padding * 2, height: height + padding * 2)
            let content = AnyView(view.frame(width: width, height: height).padding(padding)
                .environment(\.colorScheme, dark ? .dark : .light))
            guard let image = BackgroundArtworkCache.image(key: "\(prefix)|\(name)", size: artworkSize,
                scale: rasterScale ?? min(scale, 2), content: content) else { return }
            result.append(BackgroundSprite(image: image, size: artworkSize,
                position: CGPoint(x: w * x, y: h * y), opacity: opacity, blendFilter: blend, motions: motions))
        }
        func oscillate(_ key: String, base: CGFloat, amplitude: CGFloat,
                       period: Double, phase: Double = 0) -> BackgroundLayerMotion {
            BackgroundLayerMotion(keyPath: key, period: period) { time in
                NSNumber(value: Double(base + amplitude * drift(time, period: period, phase: phase)))
            }
        }
        if layer.showsBase {
            add("base", WorkFollowBackgroundView.artwork(theme: theme, dark: dark, size: size,
                time: 11.6, layer: .base), width: w, height: h, x: 0.5, y: 0.5, rasterScale: 1)
        }
        guard layer.showsMotion else { return result }
        switch theme {
        case .none: break
        case .peachSoda:
            let unit = max(w, h)
            let tints = dark ? [bgColor(0xE07A5C), bgColor(0xD9738F), bgColor(0xC79A48)]
                : [bgColor(0xFF8F6B), bgColor(0xFF9FB8), bgColor(0xFFC15E)]
            for index in 0..<7 {
                let period = 20 + Double(index) * 3
                let phase = Double(index) * 0.14
                let diameter = unit * (0.016 + CGFloat(index % 3) * 0.008)
                let baseX = w * (0.09 + CGFloat(index) * 0.125)
                add("bubble\(index)", SodaBubble(diameter: diameter, dark: dark, tint: tints[index % 3]),
                    width: diameter, height: diameter, x: 0, y: 0, motions: [
                        BackgroundLayerMotion(keyPath: "position.x", period: period) { t in
                            NSNumber(value: Double(baseX + sin(rise(t, period: period, phase: phase) * .pi * 2) * w * 0.008))
                        },
                        BackgroundLayerMotion(keyPath: "position.y", period: period) { t in
                            NSNumber(value: Double(h * (1.10 - rise(t, period: period, phase: phase) * 1.24)))
                        },
                        BackgroundLayerMotion(keyPath: "opacity", period: period) { t in
                            let p = rise(t, period: period, phase: phase)
                            return NSNumber(value: p > 0.04 && p < 0.92 ? 1.0 : 0.0)
                        }
                    ])
            }
        case .mintCloud:
            let scene = MintCloudScene(size: size, dark: dark, time: 11.6, layer: .motion)
            let clouds: [(CGFloat, CGFloat, CGFloat, CGFloat, Bool, Double, Double, CGFloat)] = [
                (0.20, 0.064, 0.07, 0.11, true, 52, 0, 0.035),
                (0.14, 0.045, 0.87, 0.23, false, 68, 0.4, -0.028),
                (0.23, 0.074, 0.31, 0.94, true, 74, 0.7, 0.03)
            ]
            for (index, c) in clouds.enumerated() {
                add("cloud\(index)", scene.cloud(width: w * c.0, height: w * c.1, face: c.4),
                    width: w * c.0, height: w * c.1, x: c.2, y: c.3, padding: w * c.1 * 0.9,
                    motions: [oscillate("position.x", base: w * c.2, amplitude: w * c.7, period: c.5, phase: c.6)])
            }
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(0.18, 0.25, 18), (0.77, 0.15, 12), (0.58, 0.41, 15), (0.90, 0.45, 11)]
            for (index, star) in stars.enumerated() {
                let tint = index.isMultiple(of: 2) ? (dark ? bgColor(0x9FC1FF) : bgColor(0xF2B21F))
                    : (dark ? bgColor(0xFFE0A0) : bgColor(0x5F87F2))
                add("star\(index)", CuteSparkleShape().fill(tint), width: star.2, height: star.2,
                    x: star.0, y: star.1, motions: [
                        oscillate("opacity", base: 0.85375, amplitude: 0.14625, period: 5.5, phase: Double(index) * 0.37),
                        oscillate("transform.scale", base: 0.9415, amplitude: 0.0585, period: 5.5, phase: Double(index) * 0.37)
                    ])
            }
        case .creamSticker:
            let unit = max(h, w * 0.5)
            let opacity: Float = dark ? 0.72 : 1
            add("sun", SunSticker(size: unit * 0.13), width: unit * 0.13, height: unit * 0.13,
                x: 0.90, y: 0.10, opacity: opacity,
                motions: [oscillate("transform.rotation.z", base: 0, amplitude: 5 * .pi / 180, period: 9)])
            add("flower", FlowerSticker(size: unit * 0.075), width: unit * 0.075, height: unit * 0.075,
                x: 0.08, y: 0.46, opacity: opacity,
                motions: [oscillate("transform.rotation.z", base: 0, amplitude: -6 * .pi / 180, period: 7, phase: 0.4)])
            add("star", StickerStar(size: unit * 0.06), width: unit * 0.06, height: unit * 0.06,
                x: 0.20, y: 0.13, opacity: opacity, motions: [
                    oscillate("position.x", base: w * 0.20, amplitude: w * 0.006, period: 6, phase: 0.8),
                    oscillate("position.y", base: h * 0.13, amplitude: h * 0.008, period: 5.5)])
            add("cloud", CloudSticker(size: unit * 0.13), width: unit * 0.13, height: unit * 0.13,
                x: 0.86, y: 0.82, opacity: opacity,
                motions: [oscillate("position.y", base: h * 0.82, amplitude: h * 0.01, period: 8, phase: 0.6)])
            add("leaf", LeafSticker(size: unit * 0.055), width: unit * 0.055, height: unit * 0.055,
                x: 0.12, y: 0.90, opacity: opacity,
                motions: [oscillate("transform.rotation.z", base: 0, amplitude: 7 * .pi / 180, period: 7.5, phase: 0.2)])
            add("heart", HeartSticker(size: unit * 0.035), width: unit * 0.035, height: unit * 0.035,
                x: 0.47, y: 0.09, opacity: opacity,
                motions: [oscillate("position.y", base: h * 0.09, amplitude: h * 0.01, period: 5.5, phase: 0.5)])
            let dots: [(UInt32, CGFloat, CGFloat, CGFloat)] = [(0xFFC53D, 0.34, 0.22, 6), (0x8FD9A8, 0.70, 0.30, 5),
                (0x9EC5FF, 0.84, 0.62, 7), (0xFF9FB2, 0.26, 0.70, 5)]
            for (index, dot) in dots.enumerated() {
                add("dot\(index)", Circle().fill(bgColor(dot.0).opacity(dark ? 0.4 : 0.55)),
                    width: dot.3, height: dot.3, x: dot.1, y: dot.2)
            }
        case .auroraJelly:
            let colors = dark ? [bgColor(0x2FE0B5), bgColor(0x6E8BFF), bgColor(0xFF6FAE)]
                : [bgColor(0x3FCB9E), bgColor(0x6A8DFF), bgColor(0xFF7FBA)]
            let bands: [(CGFloat, CGFloat, CGFloat, CGFloat, Double, Double, Double)] = [
                (0.86, 0.55, 0.10, 0.08, -24, 34, 0), (0.82, 0.52, 0.95, 0.28, 20, 40, 0.35),
                (0.88, 0.50, 0.56, 0.94, -10, 30, 0.7)]
            for (index, b) in bands.enumerated() {
                let width = w * b.0, height = h * b.1
                let art = Ellipse().fill(RadialGradient(stops: [
                    .init(color: colors[index].opacity(dark ? 0.85 : 0.80), location: 0),
                    .init(color: colors[index].opacity(0.38), location: 0.55), .init(color: .clear, location: 1)
                ], center: .center, startRadius: 0, endRadius: max(width, height) * 0.55))
                add("band\(index)", art, width: width, height: height, x: b.2, y: b.3,
                    blend: dark ? "plusL" : "multiplyBlendMode", motions: [
                        oscillate("position.x", base: w * b.2, amplitude: w * 0.03, period: b.5, phase: b.6),
                        oscillate("position.y", base: h * b.3, amplitude: h * 0.02, period: b.5 * 1.3, phase: b.6),
                        oscillate("transform.rotation.z", base: CGFloat(b.4) * .pi / 180,
                                  amplitude: 4 * .pi / 180, period: b.5, phase: b.6)
                    ], rasterScale: 1)
            }
            let stars: [(CGFloat, CGFloat, CGFloat)] = [(0.28, 0.18, 13), (0.72, 0.32, 10), (0.86, 0.68, 15),
                (0.14, 0.62, 9), (0.48, 0.52, 11)]
            for (index, star) in stars.enumerated() {
                let tint = index.isMultiple(of: 2) ? (dark ? Color.white : bgColor(0x3F6FE0))
                    : (dark ? bgColor(0x9FC1FF) : bgColor(0xE0A000))
                add("star\(index)", CuteSparkleShape().fill(tint).shadow(color: tint.opacity(0.45), radius: 6),
                    width: star.2, height: star.2, x: star.0, y: star.1, padding: 16,
                    motions: [BackgroundLayerMotion(keyPath: "opacity", period: 6) { time in
                        let pulse = 0.675 + 0.325 * sin((time / 6 + Double(index) * 0.31) * .pi * 2)
                        return NSNumber(value: (0.6 + 0.4 * pulse) * (0.35 + 0.65 * pulse))
                    }])
            }
        }
        return result
    }
}

// MARK: - Helpers

private func bgColor(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255,
          opacity: alpha)
}

/// 浅/深两套不透明色，随系统外观切换（与 `WFColors.themed` 同一机制）。
private func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                       green: Double((hex >> 8) & 0xFF) / 255,
                       blue: Double(hex & 0xFF) / 255,
                       alpha: 1)
    })
}

private func drift(_ time: TimeInterval, period: Double, phase: Double = 0) -> CGFloat {
    CGFloat(sin((time / period + phase) * .pi * 2))
}

private func rise(_ time: TimeInterval, period: Double, phase: Double) -> CGFloat {
    let value = (time / period + phase).truncatingRemainder(dividingBy: 1)
    return CGFloat(value < 0 ? value + 1 : value)
}
