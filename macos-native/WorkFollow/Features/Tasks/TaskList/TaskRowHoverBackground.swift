import AppKit
import SwiftUI

/// Only the drag handle observes pointer changes; the task's controls do not.
@MainActor
final class TaskRowPointerState: ObservableObject {
    @Published private(set) var inside = false
    func update(_ value: Bool) {
        if inside != value { inside = value }
    }
}

struct TaskRowHoverBackground: NSViewRepresentable {
    let selected: Bool
    let pointer: TaskRowPointerState

    func makeNSView(context: Context) -> TaskRowHoverView { TaskRowHoverView() }
    func updateNSView(_ view: TaskRowHoverView, context: Context) {
        view.onHover = { pointer.update($0) }
        view.setSelected(selected)
    }
}

/// Paint on the native pointer event, without rebuilding title fields, date
/// controls or the row's context menu and without a Core Animation fade.
final class TaskRowHoverView: NSView {
    private var pointerArea: NSTrackingArea?
    private var selected = false
    private(set) var hovered = false
    var onHover: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = WFMetrics.corner
        paint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }
    func setSelected(_ value: Bool) {
        guard selected != value else { return }
        selected = value
        paint()
    }
    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        paint()
        onHover?(value)
    }
    private func paint() {
        let color = selected ? NSColor(WFColors.listSelection)
            : hovered ? NSColor(WFColors.hover) : .clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = color.cgColor
            CATransaction.commit()
        }
    }
}

struct TaskRowReorderHandle: View {
    let taskID: UUID
    let title: String
    @ObservedObject var pointer: TaskRowPointerState
    @State private var hovering = false

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(WFColors.secondaryText)
            .frame(width: 16, height: 18)
            .contentShape(Rectangle())
            .opacity(pointer.inside || hovering ? 1 : 0)
            .onHover { hovering = $0 }
            .help("拖动调整任务顺序")
            .accessibilityLabel("拖动调整任务顺序")
            .draggable(taskID.uuidString) { TaskDragPreview(title: title) }
            .modifier(TaskReorderDragPolicy())
            .transaction { $0.animation = nil }
    }
}
