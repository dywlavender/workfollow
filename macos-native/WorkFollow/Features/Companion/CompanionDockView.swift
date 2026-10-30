import SwiftUI

enum CompanionLayout {
    /// 图标栏宽 62，猫占 46，左右各留 8。
    static let perchMascotSize: CGFloat = 46
    static let bubbleWidth: CGFloat = 196
    static let perchWidth: CGFloat = 250
    /// 气泡以角色头部中线为轴上下展开；下方多留 20pt，气泡变高时先向下长。
    static let perchMascotBottomInset: CGFloat = 20
    static let perchHeight: CGFloat = 160
    /// 图标栏底部的同步/搜索/设置三行加上内边距；猫停在它们上方。
    static let railBottomReserve: CGFloat = 156
}

/// 停在图标栏空白处的小伙伴。气泡向右浮出，不参与主界面布局；
/// 窗口高度不足 600 时由外壳隐藏，避免和图标栏顶部图标相撞。
///
/// 持续状态（专注/休息/会议/AI/同步）只换表情和道具，不挂气泡：
/// 专注动辄 25 分钟，常驻气泡会一直压住导航列底部。只有短事件才说话。
struct CompanionPerchView: View {
    @ObservedObject var director: CompanionSceneDirector
    let character: CompanionCharacter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: CompanionPresentation? { director.presentation }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CompanionMascotView(character: character,
                                phase: presentation?.phase ?? .idle,
                                scene: presentation?.scene,
                                prop: presentation?.prop,
                                size: CompanionLayout.perchMascotSize)
                .contentShape(Rectangle())
                .onTapGesture { director.pet() }
                .help("摸摸小伙伴")
                .accessibilityElement()
                .accessibilityLabel("小伙伴")
                .accessibilityHint("点一下互动")
                .accessibilityAddTraits(.isButton)
                .padding(.bottom, CompanionLayout.perchMascotBottomInset)

            if let presentation, !presentation.isSticky, !presentation.message.isEmpty {
                bubbleView(presentation)
            }
        }
        .frame(width: CompanionLayout.perchWidth,
               height: CompanionLayout.perchHeight,
               alignment: .bottomLeading)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
                   value: presentation?.id)
    }

    /// 气泡中心对齐角色头部中线：短气泡贴着嘴角，长气泡上下平分增长。
    private func bubbleView(_ presentation: CompanionPresentation) -> some View {
        let centerOffset = CompanionLayout.perchMascotBottomInset
            + CompanionLayout.perchMascotSize / 2
        return CompanionBubble(message: presentation.message,
                               actionTitle: presentation.actionTitle,
                               onAction: { director.postponeOverdueTask() },
                               onDismiss: { director.dismissPresentation() },
                               onHoverChanged: { director.setBubbleHovered($0) })
            .frame(width: CompanionLayout.bubbleWidth, alignment: .leading)
            .alignmentGuide(.bottom) { dimensions in
                dimensions.height / 2 + centerOffset
            }
            .offset(x: CompanionLayout.perchMascotSize + 8)
            .id(presentation.id)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
    }
}

private struct CompanionBubble: View {
    let message: String
    let actionTitle: String?
    let onAction: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(WFColors.text)
                // 带操作按钮的气泡必须保持一行（逾期文案已压缩）；普通提示最多两行。
                .lineLimit(actionTitle == nil ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            if let actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WFColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WFColors.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
        // 右上角 × 的常驻槽位：悬停时才画出按钮，文字不因此重排。
        .padding(.trailing, 24)
        .padding(.vertical, 7)
        .frame(maxWidth: CompanionLayout.bubbleWidth, alignment: .leading)
        // 气泡是浮在任意页面上的弹层，底色跟主题弹层同一套不透明底色；
        // 继续用 WFColors.content 会在主题开启时成为唯一一块不跟着变色的卡片。
        .background(theme.popupFill(for: colorScheme), in: CompanionBubbleShape())
        .overlay {
            CompanionBubbleShape()
                .stroke(WFColors.border, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(WFColors.hover))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭提示")
                .accessibilityLabel("关闭提示")
                .padding(.top, 3)
                .padding(.trailing, 4)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .onHover {
            hovering = $0
            onHoverChanged($0)
        }
        // 气泡在鼠标还压着时到期消失，不会触发 onHover(false)，这里补一次复位。
        .onDisappear { onHoverChanged(false) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        // 用 contain 而不是 combine：× 要能单独被读屏和键盘选中。
        .accessibilityElement(children: .contain)
    }
}

/// 左边缘带小尖角的对话气泡。尖角在左边缘垂直居中，正对角色头部中线。
struct CompanionBubbleShape: Shape {
    var cornerRadius: CGFloat = 10
    var tailWidth: CGFloat = 8
    var tailHalfHeight: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.height / 2)
        let centerY = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius, startAngle: .degrees(0), endAngle: .degrees(90),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius, startAngle: .degrees(90), endAngle: .degrees(180),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: centerY + tailHalfHeight))
        path.addLine(to: CGPoint(x: rect.minX - tailWidth, y: centerY))
        path.addLine(to: CGPoint(x: rect.minX, y: centerY - tailHalfHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius, startAngle: .degrees(180), endAngle: .degrees(270),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct CompanionMascotView: View {
    let character: CompanionCharacter
    let phase: CompanionPhase
    var scene: CompanionScene? = nil
    var prop: String? = nil
    var animated: Bool = true
    var size: CGFloat = CompanionLayout.perchMascotSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    private var moves: Bool {
        animated && !reduceMotion && controlActiveState != .inactive
    }

    var body: some View {
        Group {
            if moves {
                TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                    canvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(time: 1.2)
            }
        }
        .frame(width: size, height: size)
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 96
            context.scaleBy(x: scale, y: scale)
            CompanionMascotArt.draw(context: &context,
                                    character: character,
                                    phase: phase,
                                    scene: scene,
                                    prop: prop,
                                    time: time)
        }
    }
}

private enum CompanionMascotArt {
    private static let catBody = Color(red: 0.949, green: 0.635, blue: 0.361)
    private static let catFace = Color(red: 0.973, green: 0.718, blue: 0.471)
    private static let catBelly = Color(red: 1.0, green: 0.890, blue: 0.776)
    private static let catOutline = Color(red: 0.851, green: 0.541, blue: 0.298)
    private static let bunnyBody = Color(red: 1.0, green: 0.878, blue: 0.541)
    private static let bunnyFace = Color(red: 1.0, green: 0.914, blue: 0.659)
    private static let bunnyBelly = Color(red: 1.0, green: 0.953, blue: 0.808)
    private static let bunnyOutline = Color(red: 0.878, green: 0.710, blue: 0.247)
    private static let pink = Color(red: 1.0, green: 0.702, blue: 0.769)
    private static let ink = Color(red: 0.290, green: 0.227, blue: 0.180)
    private static let headphone = Color(red: 0.357, green: 0.420, blue: 0.478)

    static func draw(context: inout GraphicsContext, character: CompanionCharacter,
                     phase: CompanionPhase, scene: CompanionScene?, prop: String?,
                     time: TimeInterval) {
        let body = character == .cat ? catBody : bunnyBody
        let face = character == .cat ? catFace : bunnyFace
        let belly = character == .cat ? catBelly : bunnyBelly
        let outline = character == .cat ? catOutline : bunnyOutline
        let bounce: CGFloat
        switch phase {
        case .happy: bounce = max(0, sin(time * 3.4)) * -2.2
        case .celebrate: bounce = abs(sin(time * 4.6)) * -5
        default: bounce = 0
        }
        let tailSpeed = (phase == .happy || phase == .celebrate) ? 3.4 : 1.4
        let tailAngle = sin(time * tailSpeed) * 7

        context.fill(Path(ellipseIn: CGRect(x: 25, y: 85, width: 46, height: 8)),
                     with: .color(.black.opacity(0.08)))

        var layered = context
        layered.translateBy(x: 0, y: bounce)

        if character == .cat {
            var tail = Path()
            tail.move(to: CGPoint(x: 72, y: 82))
            tail.addCurve(to: CGPoint(x: 89, y: 62),
                          control1: CGPoint(x: 90, y: 85),
                          control2: CGPoint(x: 95, y: 70))
            layered.drawLayer { layer in
                layer.translateBy(x: 72, y: 82)
                layer.rotate(by: .degrees(tailAngle))
                layer.translateBy(x: -72, y: -82)
                layer.stroke(tail, with: .color(body),
                             style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
        } else {
            layered.fill(Path(ellipseIn: CGRect(x: 78, y: 74, width: 14, height: 14)),
                         with: .color(Color.white.opacity(0.96)))
            layered.stroke(Path(ellipseIn: CGRect(x: 78, y: 74, width: 14, height: 14)),
                           with: .color(outline.opacity(0.35)), lineWidth: 1)
        }

        layered.fill(Path(ellipseIn: CGRect(x: 20, y: 54, width: 56, height: 38)),
                     with: .color(body))
        layered.fill(Path(ellipseIn: CGRect(x: 32, y: 66, width: 32, height: 24)),
                     with: .color(belly))
        layered.fill(Path(ellipseIn: CGRect(x: 29, y: 84, width: 15, height: 7)),
                     with: .color(belly))
        layered.fill(Path(ellipseIn: CGRect(x: 52, y: 84, width: 15, height: 7)),
                     with: .color(belly))

        if phase == .sleep {
            drawBlanket(&layered)
        }

        if character == .cat {
            drawCatEar(&layered, x: 36, mirrored: false, fill: face, outline: outline)
            drawCatEar(&layered, x: 36, mirrored: true, fill: face, outline: outline)
        } else {
            drawBunnyEar(&layered, x: 38, angle: -8, fill: face, outline: outline)
            drawBunnyEar(&layered, x: 58, angle: 8, fill: face, outline: outline)
        }

        layered.fill(Path(ellipseIn: CGRect(x: 18, y: 28, width: 60, height: 52)),
                     with: .color(face))
        layered.stroke(Path(ellipseIn: CGRect(x: 18, y: 28, width: 60, height: 52)),
                       with: .color(outline), lineWidth: 2)

        drawFace(&layered, phase: phase, time: time, outline: outline, ink: ink)

        if phase == .focus {
            if scene == .aiThinking {
                drawThoughtDots(&layered, time: time)
            } else {
                drawHeadphones(&layered)
            }
        }

        if phase == .sleep {
            drawSleepMarks(&layered, time: time)
        }
        if phase == .celebrate {
            drawSparkles(&layered, time: time)
        }

        if let prop, !prop.isEmpty {
            let bob = sin(time * 2) * 1.8
            layered.draw(Text(prop).font(.system(size: 18)),
                         at: CGPoint(x: 84, y: 19 + bob), anchor: .center)
        }
    }

    private static func drawCatEar(_ context: inout GraphicsContext, x: CGFloat, mirrored: Bool,
                                   fill: Color, outline: Color) {
        var path = Path()
        path.move(to: CGPoint(x: x - 1, y: 39))
        path.addLine(to: CGPoint(x: x - 7, y: 16))
        path.addQuadCurve(to: CGPoint(x: x - 3, y: 11),
                          control: CGPoint(x: x - 8, y: 11))
        path.addLine(to: CGPoint(x: x + 13, y: 30))
        path.closeSubpath()
        var inner = Path()
        inner.move(to: CGPoint(x: x + 1, y: 34))
        inner.addLine(to: CGPoint(x: x - 3, y: 20))
        inner.addLine(to: CGPoint(x: x + 8, y: 29))
        inner.closeSubpath()

        if mirrored {
            let flip = CGAffineTransform(translationX: 96, y: 0).scaledBy(x: -1, y: 1)
            path = path.applying(flip)
            inner = inner.applying(flip)
        }
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(outline), lineWidth: 2)
        context.fill(inner, with: .color(pink.opacity(0.65)))
    }

    private static func drawBunnyEar(_ context: inout GraphicsContext, x: CGFloat, angle: Double,
                                     fill: Color, outline: Color) {
        var layer = context
        layer.translateBy(x: x, y: 28)
        layer.rotate(by: .degrees(angle))
        layer.translateBy(x: -x, y: -28)
        let outer = CGRect(x: x - 7, y: 3, width: 14, height: 42)
        let inner = CGRect(x: x - 3.5, y: 9, width: 7, height: 30)
        layer.fill(Path(ellipseIn: outer), with: .color(fill))
        layer.stroke(Path(ellipseIn: outer), with: .color(outline), lineWidth: 2)
        layer.fill(Path(ellipseIn: inner), with: .color(pink.opacity(0.62)))
    }

    private static func drawFace(_ context: inout GraphicsContext, phase: CompanionPhase,
                                 time: TimeInterval, outline: Color, ink: Color) {
        let blinkCycle = time.truncatingRemainder(dividingBy: 4.6)
        let blinking = blinkCycle > 4.42 && blinkCycle < 4.58
        let closed = phase == .happy || phase == .celebrate || phase == .sleep || blinking

        if closed {
            let leftY: CGFloat = phase == .sleep ? 53 : 52
            var left = Path()
            if phase == .happy || phase == .celebrate {
                left.move(to: CGPoint(x: 34, y: leftY))
                left.addQuadCurve(to: CGPoint(x: 44, y: leftY),
                                  control: CGPoint(x: 39, y: leftY - 4))
            } else {
                left.move(to: CGPoint(x: 35, y: leftY))
                left.addLine(to: CGPoint(x: 43, y: leftY))
            }
            var right = Path()
            if phase == .happy || phase == .celebrate {
                right.move(to: CGPoint(x: 52, y: leftY))
                right.addQuadCurve(to: CGPoint(x: 62, y: leftY),
                                   control: CGPoint(x: 57, y: leftY - 4))
            } else {
                right.move(to: CGPoint(x: 53, y: leftY))
                right.addLine(to: CGPoint(x: 61, y: leftY))
            }
            context.stroke(left, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            context.stroke(right, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        } else {
            let left = CGRect(x: 35.5, y: 47, width: 7, height: 10.5)
            let right = CGRect(x: 53.5, y: 47, width: 7, height: 10.5)
            context.fill(Path(ellipseIn: left), with: .color(ink))
            context.fill(Path(ellipseIn: right), with: .color(ink))
            context.fill(Path(ellipseIn: CGRect(x: 38, y: 49, width: 2.4, height: 3.2)),
                          with: .color(.white.opacity(0.9)))
            context.fill(Path(ellipseIn: CGRect(x: 56, y: 49, width: 2.4, height: 3.2)),
                          with: .color(.white.opacity(0.9)))
        }

        var nose = Path()
        nose.move(to: CGPoint(x: 45.5, y: 59))
        nose.addLine(to: CGPoint(x: 50.5, y: 59))
        nose.addLine(to: CGPoint(x: 48, y: 62))
        nose.closeSubpath()
        context.fill(nose, with: .color(Color(red: 0.851, green: 0.427, blue: 0.427)))

        var smile = Path()
        smile.move(to: CGPoint(x: 44, y: 64))
        smile.addQuadCurve(to: CGPoint(x: 52, y: 64), control: CGPoint(x: 48, y: 67.5))
        context.stroke(smile, with: .color(Color(red: 0.478, green: 0.290, blue: 0.133)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        context.fill(Path(ellipseIn: CGRect(x: 26, y: 58, width: 8, height: 6)), with: .color(pink.opacity(0.55)))
        context.fill(Path(ellipseIn: CGRect(x: 62, y: 58, width: 8, height: 6)), with: .color(pink.opacity(0.55)))

        var whiskers = Path()
        whiskers.move(to: CGPoint(x: 25, y: 58)); whiskers.addLine(to: CGPoint(x: 17, y: 56))
        whiskers.move(to: CGPoint(x: 25, y: 63)); whiskers.addLine(to: CGPoint(x: 17, y: 63))
        whiskers.move(to: CGPoint(x: 71, y: 58)); whiskers.addLine(to: CGPoint(x: 79, y: 56))
        whiskers.move(to: CGPoint(x: 71, y: 63)); whiskers.addLine(to: CGPoint(x: 79, y: 63))
        context.stroke(whiskers, with: .color(outline.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    private static func drawHeadphones(_ context: inout GraphicsContext) {
        var band = Path()
        band.move(to: CGPoint(x: 22, y: 46))
        band.addQuadCurve(to: CGPoint(x: 74, y: 46), control: CGPoint(x: 48, y: 13))
        context.stroke(band, with: .color(headphone), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        for rect in [CGRect(x: 16, y: 43, width: 13, height: 21),
                     CGRect(x: 67, y: 43, width: 13, height: 21)] {
            context.fill(Path(roundedRect: rect, cornerRadius: 6.5), with: .color(headphone))
            context.fill(Path(roundedRect: rect.insetBy(dx: 3, dy: 4), cornerRadius: 4),
                         with: .color(Color.white.opacity(0.28)))
        }
    }

    private static func drawThoughtDots(_ context: inout GraphicsContext, time: TimeInterval) {
        for index in 0..<3 {
            let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 2.6 - Double(index) * 0.45))
            let radius = 1.7 + CGFloat(index) * 0.7
            let point = CGPoint(x: 77 + CGFloat(index) * 5, y: 32 - CGFloat(index) * 5)
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(catOutline.opacity(pulse)))
        }
    }

    private static func drawBlanket(_ context: inout GraphicsContext) {
        let rect = CGRect(x: 23, y: 73, width: 50, height: 21)
        context.fill(Path(roundedRect: rect, cornerRadius: 10),
                     with: .color(Color(red: 0.788, green: 0.929, blue: 0.863)))
        context.fill(Path(roundedRect: CGRect(x: 27, y: 76, width: 42, height: 5), cornerRadius: 2.5),
                     with: .color(.white.opacity(0.48)))
    }

    private static func drawSleepMarks(_ context: inout GraphicsContext, time: TimeInterval) {
        let drift = sin(time * 1.8) * 1.5
        context.draw(Text("z").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(catOutline.opacity(0.75)),
                     at: CGPoint(x: 13, y: 25 + drift), anchor: .center)
        context.draw(Text("z").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(catOutline.opacity(0.55)),
                     at: CGPoint(x: 20, y: 17 - drift), anchor: .center)
    }

    private static func drawSparkles(_ context: inout GraphicsContext, time: TimeInterval) {
        let specs: [(CGFloat, CGFloat, Color)] = [
            (13, 23, Color(red: 1.0, green: 0.847, blue: 0.420)),
            (82, 27, Color(red: 1.0, green: 0.702, blue: 0.769)),
            (14, 45, Color(red: 0.663, green: 0.780, blue: 1.0))
        ]
        for (index, spec) in specs.enumerated() {
            let pulse = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 4.2 + Double(index) * 1.3))
            let side = 4 + CGFloat(pulse) * 3
            var sparkle = Path()
            sparkle.move(to: CGPoint(x: spec.0, y: spec.1 - side))
            sparkle.addQuadCurve(to: CGPoint(x: spec.0 + side, y: spec.1),
                                 control: CGPoint(x: spec.0, y: spec.1))
            sparkle.addQuadCurve(to: CGPoint(x: spec.0, y: spec.1 + side),
                                 control: CGPoint(x: spec.0, y: spec.1))
            sparkle.addQuadCurve(to: CGPoint(x: spec.0 - side, y: spec.1),
                                 control: CGPoint(x: spec.0, y: spec.1))
            sparkle.addQuadCurve(to: CGPoint(x: spec.0, y: spec.1 - side),
                                 control: CGPoint(x: spec.0, y: spec.1))
            sparkle.closeSubpath()
            context.fill(sparkle, with: .color(spec.2.opacity(pulse)))
        }
    }
}
