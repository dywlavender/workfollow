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

    /// 编辑格式工具条的底色。必须是**不透明**色：工具条常驻在正文上方，
    /// 半透明会把滚到下面的文字透出来。约 10% 主题色混白/混深，只做一层
    /// 很淡的着色，不改变正文墨色的对比判断。
    func editorBarFill(for scheme: ColorScheme) -> Color {
        guard isThemed else { return WFColors.content }
        let dark = scheme == .dark
        switch self {
        case .none:
            return WFColors.content
        case .peachSoda:
            return bgColor(dark ? 0x2E2521 : 0xFFF1E7)
        case .mintCloud:
            return bgColor(dark ? 0x1D2D28 : 0xE9F9F3)
        case .creamSticker:
            return bgColor(dark ? 0x2E291D : 0xFFF7E3)
        case .auroraJelly:
            return bgColor(dark ? 0x1B2738 : 0xEDF4FF)
        }
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
}

extension View {
    @MainActor
    func workfollowNativeTheme() -> some View {
        environment(\.workfollowBackgroundTheme, NativeThemeBridge.theme)
            .environment(\.workfollowBackgroundIntensity, NativeThemeBridge.intensity)
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
    func workfollowPageSurface(_ opacity: Double = 0.90) -> some View {
        background { ThemedPageSurface(opacity: opacity) }
    }
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

    var body: some View {
        if theme.isThemed {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let railEdge = min(RailMetrics.width, width)
                let navEdge = min(max(leadingWidth, railEdge), width)
                // 没有二级导航时，图标栏直接过渡到正文底色。
                let chrome = leadingWidth > RailMetrics.width + 1
                    ? theme.navigationFill(for: colorScheme)
                    : theme.railFill(for: colorScheme)
                let fade = min(max(width * 0.12, 96), 180)
                let fadeEnd = min(width, navEdge + fade)
                let veil = theme.pageVeil(for: colorScheme)
                    .opacity(intensity.pageOpacity(base: 0.90))
                LinearGradient(stops: [
                    .init(color: theme.railFill(for: colorScheme), location: 0),
                    .init(color: theme.railFill(for: colorScheme), location: railEdge / width),
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

/// 弹层/下拉/对话框的不透明主题底。`fallback` 用于主题关闭时保留各弹窗原来的
/// 底色（例如专注记录用 FocusTheme.canvas、系统 sheet 用 canvas）。
struct ThemedPopupSurface: View {
    var fallback: Color = WFColors.content

    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        theme.isThemed ? theme.popupFill(for: colorScheme) : fallback
    }
}

extension View {
    func workfollowPopupSurface(fallback: Color = WFColors.content) -> some View {
        background { ThemedPopupSurface(fallback: fallback) }
    }
}

/// 四套背景共用的外壳：按外观取色、按浓度淡出、按系统设置静止。
/// 20fps 足够慢速漂移，避免 60fps 下持续重绘整块窗口背景。
struct WorkFollowBackgroundView: View {
    let theme: NativeBackgroundTheme
    var intensity: NativeBackgroundIntensity = .full
    var animated: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMoving: Bool {
        theme.isThemed && animated && !reduceMotion && controlActiveState != .inactive
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if isMoving {
                    TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                        scene(size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    scene(size: size, time: 11.6)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(intensity.opacity)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func scene(size: CGSize, time: TimeInterval) -> some View {
        switch theme {
        case .none:
            Color.clear
        case .peachSoda:
            PeachSodaScene(size: size, dark: colorScheme == .dark, time: time)
        case .mintCloud:
            MintCloudScene(size: size, dark: colorScheme == .dark, time: time)
        case .creamSticker:
            CreamStickerScene(size: size, dark: colorScheme == .dark, time: time)
        case .auroraJelly:
            AuroraJellyScene(size: size, dark: colorScheme == .dark, time: time)
        }
    }
}

// MARK: - 蜜桃汽水

private struct PeachSodaScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval

    var body: some View {
        let w = size.width
        let h = size.height
        let unit = max(w, h)
        ZStack {
            LinearGradient(colors: dark
                ? [bgColor(0x171113), bgColor(0x1F1518)]
                : [bgColor(0xFFF9F4), bgColor(0xFFF6EC)],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            SoftBlob(color: dark ? bgColor(0xC97A5B) : bgColor(0xFFA880))
                .frame(width: unit * 0.56, height: unit * 0.56)
                .position(x: w * 0.04 + drift(time, period: 26) * w * 0.035,
                          y: h * 0.02 + drift(time, period: 33, phase: 0.3) * h * 0.035)

            SoftBlob(color: dark ? bgColor(0xB08A3A) : bgColor(0xFFE28C))
                .frame(width: unit * 0.46, height: unit * 0.46)
                .position(x: w * 0.96 + drift(time, period: 31, phase: 0.5) * -w * 0.03,
                          y: h * 0.04 + drift(time, period: 24, phase: 0.7) * h * 0.03)

            SoftBlob(color: dark ? bgColor(0xA85B74) : bgColor(0xFFB2C7))
                .frame(width: unit * 0.62, height: unit * 0.62)
                .position(x: w * 0.72 + drift(time, period: 36, phase: 0.2) * w * 0.04,
                          y: h * 1.02 + drift(time, period: 29, phase: 0.6) * -h * 0.03)

            SoftBlob(color: dark ? bgColor(0x8A7350) : bgColor(0xFFF2CE))
                .frame(width: unit * 0.36, height: unit * 0.36)
                .position(x: w * 0.34 + drift(time, period: 23, phase: 0.8) * -w * 0.025,
                          y: h * 0.98 + drift(time, period: 27, phase: 0.4) * h * 0.02)
                .opacity(dark ? 0.55 : 0.9)

            ForEach(0..<6, id: \.self) { index in
                let period = 22 + Double(index) * 3
                let progress = rise(time, period: period, phase: Double(index) * 0.17)
                let diameter = unit * (0.012 + CGFloat(index % 3) * 0.005)
                let wobble = CGFloat(sin(Double(progress) * .pi * 2))
                SodaBubble(diameter: diameter, dark: dark)
                    .position(x: w * (0.10 + CGFloat(index) * 0.145) + wobble * w * 0.008,
                              y: h * (1.10 - progress * 1.24))
                    .opacity(progress > 0.04 && progress < 0.92 ? 1 : 0)
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

    var body: some View {
        Circle()
            .fill(RadialGradient(
                stops: [
                    .init(color: .white.opacity(dark ? 0.22 : 0.95), location: 0),
                    .init(color: .white.opacity(dark ? 0.06 : 0.18), location: 0.6),
                    .init(color: .white.opacity(0), location: 1)
                ],
                center: UnitPoint(x: 0.32, y: 0.28),
                startRadius: 0,
                endRadius: max(1, diameter * 0.5)))
            .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.16 : 0.5), lineWidth: 1))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - 薄荷云朵

private struct MintCloudScene: View {
    let size: CGSize
    let dark: Bool
    let time: TimeInterval

    var body: some View {
        let w = size.width
        let h = size.height
        let cloudColor = dark ? Color.white.opacity(0.13) : Color.white.opacity(0.96)
        ZStack {
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

            cloud(width: w * 0.20, height: w * 0.064, color: cloudColor)
                .position(x: w * 0.07 + drift(time, period: 52) * w * 0.035, y: h * 0.11)
            cloud(width: w * 0.14, height: w * 0.045, color: cloudColor.opacity(0.9))
                .position(x: w * 0.87 + drift(time, period: 68, phase: 0.4) * -w * 0.028, y: h * 0.23)
            cloud(width: w * 0.23, height: w * 0.074, color: cloudColor.opacity(0.82))
                .position(x: w * 0.31 + drift(time, period: 74, phase: 0.7) * w * 0.03, y: h * 0.94)

            sparkle(x: 0.18, y: 0.25, side: 14, index: 0)
            sparkle(x: 0.77, y: 0.15, side: 9, index: 1)
            sparkle(x: 0.58, y: 0.41, side: 11, index: 2)
            sparkle(x: 0.90, y: 0.45, side: 8, index: 3)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func cloud(width: CGFloat, height: CGFloat, color: Color) -> some View {
        CuteCloudShape()
            .fill(color)
            .frame(width: width, height: height)
    }

    private func sparkle(x: CGFloat, y: CGFloat, side: CGFloat, index: Int) -> some View {
        let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin((time / 5.5 + Double(index) * 0.37) * .pi * 2))
        return CuteSparkleShape()
            .fill((dark ? bgColor(0xCFE7FF) : bgColor(0xFFF3B8)).opacity(0.65 + 0.35 * pulse))
            .frame(width: side, height: side)
            .position(x: size.width * x, y: size.height * y)
            .scaleEffect(0.82 + 0.18 * CGFloat(pulse))
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

    var body: some View {
        let w = size.width
        let h = size.height
        let unit = max(h, w * 0.5)
        ZStack {
            (dark ? bgColor(0x1E1A15) : bgColor(0xFFF8E9))

            Ellipse()
                .fill(RadialGradient(colors: [
                    dark ? bgColor(0x3A3022, alpha: 0.7) : bgColor(0xFFFDF6),
                    .clear
                ], center: .center, startRadius: 0, endRadius: max(1, w * 0.55)))
                .frame(width: w * 0.9, height: h * 0.9)
                .position(x: w * 0.5, y: h * 0.18)

            Group {
                SunSticker(size: unit * 0.13)
                    .position(x: w * 0.90, y: h * 0.10)
                    .rotationEffect(.degrees(Double(drift(time, period: 9)) * 5))

                FlowerSticker(size: unit * 0.075)
                    .position(x: w * 0.08, y: h * 0.46)
                    .rotationEffect(.degrees(Double(drift(time, period: 7, phase: 0.4)) * -6))

                StickerStar(size: unit * 0.06)
                    .position(x: w * 0.20 + drift(time, period: 6, phase: 0.8) * w * 0.006,
                              y: h * 0.13 + drift(time, period: 5.5) * h * 0.008)

                CloudSticker(size: unit * 0.13)
                    .position(x: w * 0.86, y: h * 0.82 + drift(time, period: 8, phase: 0.6) * h * 0.01)

                LeafSticker(size: unit * 0.055)
                    .position(x: w * 0.12, y: h * 0.90)
                    .rotationEffect(.degrees(Double(drift(time, period: 7.5, phase: 0.2)) * 7))

                HeartSticker(size: unit * 0.035)
                    .position(x: w * 0.47, y: h * 0.09 + drift(time, period: 5.5, phase: 0.5) * h * 0.01)
            }
            .opacity(dark ? 0.72 : 1)

            stickerDot(color: bgColor(0xFFC53D), x: 0.34, y: 0.22, side: 6)
            stickerDot(color: bgColor(0x8FD9A8), x: 0.70, y: 0.30, side: 5)
            stickerDot(color: bgColor(0x9EC5FF), x: 0.84, y: 0.62, side: 7)
            stickerDot(color: bgColor(0xFF9FB2), x: 0.26, y: 0.70, side: 5)
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func stickerDot(color: Color, x: CGFloat, y: CGFloat, side: CGFloat) -> some View {
        Circle().fill(color.opacity(dark ? 0.4 : 0.55))
            .frame(width: side, height: side)
            .position(x: size.width * x, y: size.height * y)
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

    var body: some View {
        let w = size.width
        let h = size.height
        ZStack {
            (dark ? bgColor(0x080B12) : bgColor(0xEFF6FF))

            aurora(color: dark ? bgColor(0x0E6B5B) : bgColor(0xA9EED9),
                    width: w * 0.80, height: h * 1.00, x: 0.10, y: 0.06,
                    angle: -18, period: 34, phase: 0)
            aurora(color: dark ? bgColor(0x1B2C6B) : bgColor(0xBBD3FF),
                    width: w * 0.78, height: h * 0.95, x: 0.95, y: 0.12,
                    angle: 22, period: 40, phase: 0.35)
            aurora(color: dark ? bgColor(0x6B2440) : bgColor(0xFFD2E5),
                    width: w * 0.82, height: h * 0.90, x: 0.56, y: 1.05,
                    angle: -8, period: 30, phase: 0.7)

            ForEach(0..<4, id: \.self) { index in
                let specs: [(CGFloat, CGFloat, CGFloat)] = [(0.32, 0.20, 5), (0.74, 0.34, 4), (0.86, 0.70, 6), (0.16, 0.64, 4)]
                let spec = specs[index]
                let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin((time / 6 + Double(index) * 0.31) * .pi * 2))
                Circle()
                    .fill(Color.white.opacity(dark ? 0.85 : 0.9))
                    .frame(width: spec.2, height: spec.2)
                    .shadow(color: (dark ? Color.white : bgColor(0x6389F5)).opacity(0.55),
                            radius: 5)
                    .position(x: w * spec.0, y: h * spec.1)
                    .opacity(0.35 + 0.65 * pulse)
            }
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func aurora(color: Color, width: CGFloat, height: CGFloat,
                        x: CGFloat, y: CGFloat, angle: Double,
                        period: Double, phase: Double) -> some View {
        let wobble = drift(time, period: period, phase: phase)
        return Ellipse()
            .fill(RadialGradient(
                stops: [
                    .init(color: color.opacity(dark ? 0.72 : 0.55), location: 0),
                    .init(color: color.opacity(dark ? 0.30 : 0.22), location: 0.55),
                    .init(color: color.opacity(0), location: 1)
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(1, max(width, height) * 0.55)))
            .frame(width: width, height: height)
            .rotationEffect(.degrees(angle + Double(wobble) * 4))
            .position(x: size.width * x + wobble * size.width * 0.03,
                      y: size.height * y + drift(time, period: period * 1.3, phase: phase) * size.height * 0.02)
            .blendMode(dark ? .plusLighter : .multiply)
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

private func drift(_ time: TimeInterval, period: Double, phase: Double = 0) -> CGFloat {
    CGFloat(sin((time / period + phase) * .pi * 2))
}

private func rise(_ time: TimeInterval, period: Double, phase: Double) -> CGFloat {
    let value = (time / period + phase).truncatingRemainder(dividingBy: 1)
    return CGFloat(value < 0 ? value + 1 : value)
}
