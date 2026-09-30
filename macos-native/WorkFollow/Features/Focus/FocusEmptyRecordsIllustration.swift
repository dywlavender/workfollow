import SwiftUI

/// Small native vector artwork for the empty Focus records state.
struct FocusEmptyRecordsIllustration: View {
    let theme: FocusTheme

    private let tomatoTop = Color(red: 1.0, green: 0.49, blue: 0.36)
    private let tomatoBottom = Color(red: 0.91, green: 0.24, blue: 0.28)
    private let leaf = Color(red: 0.23, green: 0.66, blue: 0.43)

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.accent.opacity(0.07))
                .frame(width: 82, height: 82)
                .offset(y: 3)

            TomatoBodyShape()
                .fill(LinearGradient(colors: [tomatoTop, tomatoBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 68, height: 62)
                .offset(y: 8)

            TomatoLeafShape()
                .fill(leaf)
                .frame(width: 42, height: 24)
                .offset(y: -19)

            Capsule()
                .fill(leaf.opacity(0.9))
                .frame(width: 7, height: 15)
                .rotationEffect(.degrees(-12))
                .offset(x: 1, y: -31)

            Circle()
                .fill(theme.canvas)
                .frame(width: 25, height: 25)
                .overlay {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                .overlay(Circle().stroke(theme.canvas, lineWidth: 2))
                .offset(x: 31, y: 20)
        }
        .frame(width: FocusLayoutMetrics.recordEmptyIllustrationWidth,
               height: FocusLayoutMetrics.recordEmptyIllustrationHeight)
        .accessibilityHidden(true)
    }
}

private struct TomatoBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.50, 0.19))
        path.addCurve(to: point(0.15, 0.30), control1: point(0.39, 0.12), control2: point(0.22, 0.13))
        path.addCurve(to: point(0.10, 0.60), control1: point(0.14, 0.39), control2: point(0.02, 0.45))
        path.addCurve(to: point(0.28, 0.90), control1: point(0.08, 0.76), control2: point(0.15, 0.88))
        path.addCurve(to: point(0.50, 0.96), control1: point(0.36, 0.98), control2: point(0.43, 1.00))
        path.addCurve(to: point(0.72, 0.90), control1: point(0.57, 1.00), control2: point(0.65, 0.97))
        path.addCurve(to: point(0.90, 0.60), control1: point(0.85, 0.88), control2: point(0.92, 0.76))
        path.addCurve(to: point(0.85, 0.30), control1: point(0.98, 0.45), control2: point(0.86, 0.39))
        path.addCurve(to: point(0.50, 0.19), control1: point(0.78, 0.13), control2: point(0.62, 0.13))
        path.closeSubpath()
        return path
    }
}

private struct TomatoLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.50, 0.98))
        path.addCurve(to: point(0.18, 0.43), control1: point(0.20, 0.91), control2: point(0.08, 0.58))
        path.addCurve(to: point(0.46, 0.72), control1: point(0.24, 0.69), control2: point(0.39, 0.64))
        path.addCurve(to: point(0.51, 0.06), control1: point(0.48, 0.45), control2: point(0.47, 0.18))
        path.addCurve(to: point(0.61, 0.71), control1: point(0.58, 0.22), control2: point(0.61, 0.52))
        path.addCurve(to: point(0.88, 0.41), control1: point(0.75, 0.63), control2: point(0.84, 0.55))
        path.addCurve(to: point(0.50, 0.98), control1: point(0.82, 0.79), control2: point(0.63, 0.92))
        path.closeSubpath()
        return path
    }
}
