import AppKit
import SwiftUI

#if DEBUG
private struct WorkflowActionObservationKey: EnvironmentKey {
    static let defaultValue: ((String, NSView) -> Void)? = nil
}
extension EnvironmentValues {
    var workflowActionObservation: ((String, NSView) -> Void)? {
        get { self[WorkflowActionObservationKey.self] }
        set { self[WorkflowActionObservationKey.self] = newValue }
    }
}
private struct WorkflowActionAnchor: NSViewRepresentable {
    let identifier: String
    @Environment(\.workflowActionObservation) private var observation
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.report = { [weak view] in
            // 只上报**挂在窗口上**的锚点。`ViewThatFits` 会同时实例化两个候选，
            // 被丢弃的那个分支里的 NSViewRepresentable 也会跑 updateNSView 并
            // 异步上报，而它永远没有 window——后到的 nil-window 记录会覆盖掉
            // 真正在屏幕上的那个，测试随后读到「Anchor is not attached to a window」。
            guard let view, view.window != nil else { return }
            observation?(identifier, view)
        }
        DispatchQueue.main.async { [weak view] in view?.report?() }
    }
    final class Anchor: NSView {
        var report: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() { super.layout(); report?() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report?() }
    }
}
#endif

extension View {
    /// Debug builds report geometry only; tests still send native mouse events.
    @ViewBuilder
    func workflowActionAnchor(_ identifier: String) -> some View {
        #if DEBUG
        if identifier.isEmpty { self }
        else { background(WorkflowActionAnchor(identifier: identifier)) }
        #else
        self
        #endif
    }
}
