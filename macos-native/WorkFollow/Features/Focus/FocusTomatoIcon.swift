import SwiftUI

/// Small, font-independent tomato mark used in the active-session header.
struct FocusTomatoIcon: View {
    let color: Color

    var body: some View {
        ZStack {
            TomatoBodyShape()
                .fill(color)
                .frame(width: 18, height: 16)
                .offset(y: 2)
            TomatoCalyxShape()
                .fill(color)
                .frame(width: 12, height: 8)
                .offset(y: -5)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

private struct TomatoBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.5, 0.08))
        path.addCurve(to: point(0.19, 0.20), control1: point(0.39, 0.02),
                      control2: point(0.27, 0.04))
        path.addCurve(to: point(0.04, 0.57), control1: point(0.07, 0.27),
                      control2: point(0.00, 0.42))
        path.addCurve(to: point(0.25, 0.92), control1: point(0.04, 0.75),
                      control2: point(0.11, 0.91))
        path.addCurve(to: point(0.50, 0.99), control1: point(0.36, 0.98),
                      control2: point(0.43, 1.00))
        path.addCurve(to: point(0.75, 0.92), control1: point(0.57, 1.00),
                      control2: point(0.64, 0.98))
        path.addCurve(to: point(0.96, 0.57), control1: point(0.89, 0.91),
                      control2: point(0.96, 0.75))
        path.addCurve(to: point(0.81, 0.20), control1: point(1.00, 0.42),
                      control2: point(0.93, 0.27))
        path.addCurve(to: point(0.50, 0.08), control1: point(0.73, 0.04),
                      control2: point(0.61, 0.02))
        path.closeSubpath()
        return path
    }
}

private struct TomatoCalyxShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.5, 0.96))
        path.addCurve(to: point(0.02, 0.25), control1: point(0.25, 0.80),
                      control2: point(0.02, 0.63))
        path.addCurve(to: point(0.39, 0.44), control1: point(0.14, 0.20),
                      control2: point(0.31, 0.35))
        path.addLine(to: point(0.27, 0.03))
        path.addCurve(to: point(0.53, 0.42), control1: point(0.37, 0.20),
                      control2: point(0.45, 0.33))
        path.addLine(to: point(0.75, 0.02))
        path.addCurve(to: point(0.66, 0.43), control1: point(0.68, 0.22),
                      control2: point(0.64, 0.33))
        path.addCurve(to: point(0.98, 0.25), control1: point(0.80, 0.34),
                      control2: point(0.92, 0.19))
        path.addCurve(to: point(0.5, 0.96), control1: point(0.98, 0.62),
                      control2: point(0.76, 0.82))
        path.closeSubpath()
        return path
    }
}
