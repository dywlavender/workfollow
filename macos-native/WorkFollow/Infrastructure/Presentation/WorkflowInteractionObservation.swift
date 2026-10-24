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
        view.report = { [weak view] in if let view { observation?(identifier, view) } }
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
