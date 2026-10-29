import AppKit
import SwiftUI

/// Only the tooltip layer observes pointer changes; hovering does not rebuild pages.
@MainActor
final class RailTooltipState: ObservableObject {
    struct Target: Equatable {
        let title: String
        let frame: CGRect
    }

    @Published private(set) var active: Target?
    private var frames: [String: CGRect] = [:]

    func updateFrame(_ frame: CGRect, for title: String) {
        frames[title] = frame
        if active?.title == title { active = Target(title: title, frame: frame) }
    }

    func enter(_ title: String) {
        guard let frame = frames[title] else { return }
        active = Target(title: title, frame: frame)
    }

    func leave(_ title: String) {
        if active?.title == title { dismiss() }
    }

    func dismiss() { if active != nil { active = nil } }
}

struct RailTooltipOverlay: View {
    static let space = "rail-tooltip"
    @ObservedObject var state: RailTooltipState

    var body: some View {
        if let target = state.active {
            HoverTipCard(title: target.title)
                .offset(x: target.frame.maxX + HoverTipMetrics.gap,
                        y: target.frame.midY - HoverTipMetrics.height / 2)
                .transition(.identity)
        }
    }
}

private struct RailTooltipTarget: ViewModifier {
    let title: String
    let state: RailTooltipState

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .named(RailTooltipOverlay.space))
                    RowHoverBackground(hoverFill: .clear, onHoverChanged: { inside in
                        if inside { state.enter(title) } else { state.leave(title) }
                    })
                    .onAppear { state.updateFrame(frame, for: title) }
                    .onChange(of: frame) { _, value in state.updateFrame(value, for: title) }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { state.dismiss() })
            .onDisappear { state.leave(title) }
    }
}

extension View {
    func railTooltip(_ title: String, state: RailTooltipState) -> some View {
        modifier(RailTooltipTarget(title: title, state: state))
    }
}
