import SwiftUI

struct TaskEmptyInspectorView: View {
    var body: some View {
        // Decorative only: no instruction, header or footer in the empty surface.
        // Exact artwork remains pending an empty-state reference screenshot.
        Canvas { context, size in
            for (center, radius) in [(CGPoint(x: 38, y: 48), 15.0),
                                     (CGPoint(x: 109, y: 20), 7.0),
                                     (CGPoint(x: 138, y: 69), 10.0)] {
                var path = Path()
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4 - .pi / 2
                    let length = index.isMultiple(of: 2) ? radius : radius * 0.35
                    let point = CGPoint(x: center.x + cos(angle) * length,
                                        y: center.y + sin(angle) * length)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.fill(path, with: .color(WFColors.tertiaryText.opacity(0.08)))
            }
        }
        .frame(width: 176, height: 96)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .inspectorRenderAnchor(.emptyContent)
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
