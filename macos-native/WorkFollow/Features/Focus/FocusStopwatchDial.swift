import SwiftUI

/// TickTick-style radial dial used for stopwatch sessions instead of a dashed circular stroke.
struct FocusStopwatchDial: View {
    let theme: FocusTheme

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let outerRadius = radius - FocusLayoutMetrics.stopwatchTickLineWidth / 2
            let innerRadius = outerRadius - FocusLayoutMetrics.stopwatchTickLength

            for index in 0..<FocusLayoutMetrics.stopwatchTickCount {
                let angle = Double(index) / Double(FocusLayoutMetrics.stopwatchTickCount)
                    * 2 * .pi - .pi / 2
                let direction = CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)))
                let start = CGPoint(x: center.x + direction.x * innerRadius,
                                    y: center.y + direction.y * innerRadius)
                let end = CGPoint(x: center.x + direction.x * outerRadius,
                                  y: center.y + direction.y * outerRadius)
                var tick = Path()
                tick.move(to: start)
                tick.addLine(to: end)
                context.stroke(tick, with: .color(theme.track),
                               style: StrokeStyle(lineWidth: FocusLayoutMetrics.stopwatchTickLineWidth,
                                                  lineCap: .round))
            }
        }
        .frame(width: FocusLayoutMetrics.ringSize, height: FocusLayoutMetrics.ringSize)
        .focusRenderAnchor(.focusStopwatchDial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正计时刻度表盘")
    }
}
