import SwiftUI

/// 任务空态的统一组件（阶段3）：线稿插画 +（可选）文案。
/// 插画是纯装饰：不拦截点击、不进可访问性树；描边统一走 `WFColors.tertiaryText`
/// ——深浅色自动适配，绘制里禁止硬编码灰阶。
/// 两个挂载点：详情右栏（无文案，保持壳层"纯装饰"既有契约，锚点宽度 176 由
/// 契约测试锁定）；列表空态（带 `TaskListViewDefaults.emptyStateMessage` 的
/// 分视图文案）。构图对齐滴答空态的气质：摊开的笔记本 + 咖啡杯 + 稀疏星点。
struct TaskEmptyStateView: View {
    enum Style { case list, inspector }

    let style: Style
    var message: String? = nil

    var body: some View {
        VStack(spacing: WFSpace.md) {
            illustration
                .frame(width: style == .inspector ? 176 : 168,
                       height: style == .inspector ? 120 : 108)
            if let message {
                Text(message)
                    .font(WFType.body)
                    .foregroundStyle(WFColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 场景式线稿（对照滴答空态插画迭代）：整体 -8° 桌面摆拍构图，便签笑脸、
    /// 清单卡片、摊开的笔记本、咖啡杯、铅笔五件套，后物被前物遮挡——遮挡靠
    /// 物件先填底色（WFColors.content，与空态表面同色、深浅色自适应）再描边。
    /// 所有描边仍走 WFColors.tertiaryText，禁止硬编码灰阶。
    private var illustration: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
            let ink = WFColors.tertiaryText
            let paper = WFColors.content

            // 场景整体倾斜：先把原点挪到画布中心再旋转，物件坐标都相对中心。
            context.translateBy(x: w / 2, y: h / 2)
            context.rotate(by: .degrees(-8))

            // —— 便签 + 笑脸（最后排）——
            var sticky = context
            sticky.translateBy(x: 20, y: -38)
            sticky.rotate(by: .degrees(7))
            var note = Path()
            note.addRoundedRect(in: CGRect(x: -14, y: -14, width: 28, height: 28),
                                cornerSize: CGSize(width: 2, height: 2))
            sticky.fill(note, with: .color(paper))
            sticky.stroke(note, with: .color(ink), style: stroke)
            var eyes = Path()
            eyes.addEllipse(in: CGRect(x: -6, y: -7, width: 3, height: 3))
            eyes.addEllipse(in: CGRect(x: 3, y: -7, width: 3, height: 3))
            sticky.fill(eyes, with: .color(ink))
            var mouth = Path()
            mouth.move(to: CGPoint(x: -5, y: 3))
            mouth.addQuadCurve(to: CGPoint(x: 5, y: 3), control: CGPoint(x: 0, y: 9))
            sticky.stroke(mouth, with: .color(ink),
                          style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

            // —— 清单卡片（中后排）：一行已完成带删除线，一行待办 ——
            var cardCtx = context
            cardCtx.translateBy(x: -34, y: -20)
            cardCtx.rotate(by: .degrees(-5))
            var card = Path()
            card.addRoundedRect(in: CGRect(x: -30, y: -24, width: 60, height: 48),
                                cornerSize: CGSize(width: 5, height: 5))
            cardCtx.fill(card, with: .color(paper))
            cardCtx.stroke(card, with: .color(ink), style: stroke)
            var box1 = Path()
            box1.addRoundedRect(in: CGRect(x: -22, y: -17, width: 9, height: 9),
                                cornerSize: CGSize(width: 2, height: 2))
            cardCtx.stroke(box1, with: .color(ink), style: stroke)
            var check1 = Path()
            check1.move(to: CGPoint(x: -20, y: -13))
            check1.addLine(to: CGPoint(x: -18.5, y: -10.5))
            check1.addLine(to: CGPoint(x: -14.5, y: -15.5))
            cardCtx.stroke(check1, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            var doneLine = Path()
            doneLine.move(to: CGPoint(x: -8, y: -12.5))
            doneLine.addLine(to: CGPoint(x: 20, y: -12.5))
            cardCtx.stroke(doneLine, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            var slash = Path()
            slash.move(to: CGPoint(x: -8, y: -9))
            slash.addLine(to: CGPoint(x: 20, y: -16))
            cardCtx.stroke(slash, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
            var box2 = Path()
            box2.addRoundedRect(in: CGRect(x: -22, y: -1, width: 9, height: 9),
                                cornerSize: CGSize(width: 2, height: 2))
            cardCtx.stroke(box2, with: .color(ink), style: stroke)
            var todoLine = Path()
            todoLine.move(to: CGPoint(x: -8, y: 3.5))
            todoLine.addLine(to: CGPoint(x: 12, y: 3.5))
            cardCtx.stroke(todoLine, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

            // —— 摊开的笔记本（最前的大件，遮挡卡片下缘）——
            var book = Path()
            book.move(to: CGPoint(x: -52, y: 26))
            book.addLine(to: CGPoint(x: -52, y: -16))
            book.addCurve(to: CGPoint(x: 0, y: -10),
                          control1: CGPoint(x: -32, y: -26),
                          control2: CGPoint(x: -16, y: -18))
            book.addCurve(to: CGPoint(x: 52, y: -16),
                          control1: CGPoint(x: 16, y: -18),
                          control2: CGPoint(x: 32, y: -26))
            book.addLine(to: CGPoint(x: 52, y: 26))
            book.addLine(to: CGPoint(x: 0, y: 16))
            book.closeSubpath()
            context.fill(book, with: .color(paper))
            context.stroke(book, with: .color(ink), style: stroke)
            var spine = Path()
            spine.move(to: CGPoint(x: 0, y: -10))
            spine.addLine(to: CGPoint(x: 0, y: 16))
            context.stroke(spine, with: .color(ink), style: stroke)
            for line in [CGPoint(x: -42, y: -1), CGPoint(x: -42, y: 7)] {
                var text = Path()
                text.move(to: line)
                text.addLine(to: CGPoint(x: line.x + 28, y: line.y))
                context.stroke(text, with: .color(ink),
                               style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
            var rbox = Path()
            rbox.addRoundedRect(in: CGRect(x: 12, y: -5, width: 10, height: 10),
                                cornerSize: CGSize(width: 2, height: 2))
            context.stroke(rbox, with: .color(ink), style: stroke)
            var rcheck = Path()
            rcheck.move(to: CGPoint(x: 14.5, y: 0))
            rcheck.addLine(to: CGPoint(x: 16.5, y: 2.5))
            rcheck.addLine(to: CGPoint(x: 20.5, y: -3))
            context.stroke(rcheck, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            var rline = Path()
            rline.move(to: CGPoint(x: 28, y: 0))
            rline.addLine(to: CGPoint(x: 44, y: 0))
            context.stroke(rline, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

            // —— 咖啡杯（左前）：杯体 + 把手 + 杯托 + 热气 ——
            var cup = Path()
            cup.move(to: CGPoint(x: -48, y: 8))
            cup.addLine(to: CGPoint(x: -48, y: 22))
            cup.addCurve(to: CGPoint(x: -30, y: 22),
                         control1: CGPoint(x: -48, y: 31),
                         control2: CGPoint(x: -30, y: 31))
            cup.addLine(to: CGPoint(x: -30, y: 8))
            context.fill(cup, with: .color(paper))
            context.stroke(cup, with: .color(ink), style: stroke)
            var rim = Path()
            rim.move(to: CGPoint(x: -48, y: 8))
            rim.addLine(to: CGPoint(x: -30, y: 8))
            context.stroke(rim, with: .color(ink), style: stroke)
            var handle = Path()
            handle.move(to: CGPoint(x: -48, y: 11))
            handle.addQuadCurve(to: CGPoint(x: -55, y: 14), control: CGPoint(x: -57, y: 11))
            handle.addQuadCurve(to: CGPoint(x: -48, y: 19), control: CGPoint(x: -57, y: 18))
            context.stroke(handle, with: .color(ink), style: stroke)
            var saucer = Path()
            saucer.move(to: CGPoint(x: -54, y: 27))
            saucer.addLine(to: CGPoint(x: -24, y: 27))
            context.stroke(saucer, with: .color(ink), style: stroke)
            var steam = Path()
            steam.move(to: CGPoint(x: -39, y: 0))
            steam.addQuadCurve(to: CGPoint(x: -39, y: -9), control: CGPoint(x: -45, y: -4))
            context.stroke(steam, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.1, lineCap: .round))

            // —— 铅笔（右前，斜插构图）：笔杆先填底色遮挡本子线条再描边 ——
            var pencil = context
            pencil.translateBy(x: 56, y: 4)
            pencil.rotate(by: .degrees(-55))
            var bodyFill = Path()
            bodyFill.addRect(CGRect(x: -4, y: -18, width: 8, height: 34))
            pencil.fill(bodyFill, with: .color(paper))
            var body1 = Path()
            body1.move(to: CGPoint(x: -4, y: -18))
            body1.addLine(to: CGPoint(x: -4, y: 16))
            body1.move(to: CGPoint(x: 4, y: -18))
            body1.addLine(to: CGPoint(x: 4, y: 16))
            pencil.stroke(body1, with: .color(ink), style: stroke)
            var tip = Path()
            tip.move(to: CGPoint(x: -4, y: -18))
            tip.addLine(to: CGPoint(x: 0, y: -27))
            tip.addLine(to: CGPoint(x: 4, y: -18))
            pencil.stroke(tip, with: .color(ink), style: stroke)
            var band = Path()
            band.move(to: CGPoint(x: -4, y: 10))
            band.addLine(to: CGPoint(x: 4, y: 10))
            band.move(to: CGPoint(x: -4, y: 16))
            band.addLine(to: CGPoint(x: 4, y: 16))
            pencil.stroke(band, with: .color(ink), style: stroke)

            // —— 稀疏星点 ——
            for center in [CGPoint(x: -70, y: -44), CGPoint(x: 54, y: -40)] {
                var sparkle = Path()
                sparkle.move(to: CGPoint(x: center.x - 4, y: center.y))
                sparkle.addLine(to: CGPoint(x: center.x + 4, y: center.y))
                sparkle.move(to: CGPoint(x: center.x, y: center.y - 4.5))
                sparkle.addLine(to: CGPoint(x: center.x, y: center.y + 4.5))
                context.stroke(sparkle, with: .color(ink), style: stroke)
            }
            var dot = Path()
            dot.addEllipse(in: CGRect(x: 12, y: -52, width: 2.4, height: 2.4))
            context.fill(dot, with: .color(ink))
        }
    }
}
