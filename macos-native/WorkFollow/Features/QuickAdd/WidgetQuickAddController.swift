import AppKit
import SwiftUI

/// The desktop widget uses the calendar's small creation card without opening
/// or changing the main workspace. Only one draft card is visible at a time.
@MainActor
final class WidgetQuickAddController {
    static let title = "快速新增任务"
    private let workspace: TaskWorkspaceModel
    private let appearance: () -> NativeAppearance
    private(set) var panel: NSPanel?
    private var interaction: UUID?

    init(workspace: TaskWorkspaceModel, appearance: @escaping () -> NativeAppearance = { .system }) {
        self.workspace = workspace
        self.appearance = appearance
    }

    func present() {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let size = CGSize(width: WFPlanningOverlayMetrics.composerWidth,
                          height: WFPlanningOverlayMetrics.composerHeight)
        let panel = CapturePanel(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.title = Self.title
        panel.identifier = NSUserInterfaceItemIdentifier("WorkFollowWidgetQuickAdd")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let style = appearance()
        panel.appearance = style == .system ? nil : NSAppearance(named: style == .dark ? .darkAqua : .aqua)
        let schedule = TaskSchedule(dueAt: workspace.calendar.startOfDay(for: workspace.clock()))
        let card = TaskQuickComposer(workspace: workspace, fallbackSchedule: schedule,
            presetSchedule: schedule, presetPriority: .none,
            presetList: TaskList(name: workspace.defaultListName), selectsCreatedTask: false,
            requestClose: { [weak self] in self?.dismiss() })
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).strokeBorder(WFColors.overlayBorder))
            .background(PopupEscapeRouter { [weak self] in self?.dismiss() })
            .preferredColorScheme(style.colorScheme)
        let host = NSHostingView(rootView: card)
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        self.panel = panel
        let point = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            panel.setFrame(AnchoredPropertyPanelGeometry.frame(
                row: CGRect(origin: point, size: CGSize(width: 1, height: 1)),
                size: size, screen: screen.visibleFrame, gap: WFPlanningOverlayMetrics.gap), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        interaction = PopupInteractionRegistry.shared.register(window: panel, contains: { [weak panel] event in
            guard let panel else { return false }
            var current = event.window
            while let window = current {
                if window === panel { return true }
                current = window.parent
            }
            return false
        }, dismiss: { [weak self] in self?.dismiss() })
        DispatchQueue.main.async { [weak self, weak panel, weak host] in
            guard let self, let panel, self.panel === panel, panel.isVisible, let host else { return }
            host.layoutSubtreeIfNeeded()
            if let field = Self.titleField(in: host) { panel.makeFirstResponder(field) }
        }
    }

    func dismiss() {
        if let interaction { PopupInteractionRegistry.shared.unregister(interaction) }
        interaction = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private static func titleField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { titleField(in: $0) }.first
    }

    private final class CapturePanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) {
            if !PopupEscapeRegistry.shared.route(eventWindow: self) { super.cancelOperation(sender) }
        }
    }
}
