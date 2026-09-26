import AppKit
import SwiftUI

/// 以光标为锚呈现任务右键菜单，对齐 Flutter bottomStart 定位：面板顶部在
/// 光标下方、左缘对齐光标。锚框中心放在光标右移半个面板宽处，NSPopover
/// 在锚框下方水平居中，面板左缘即落在光标上；贴近屏幕边缘时自动翻转。
@MainActor
enum TaskContextMenuPresenter {
    static func show(in rowView: NSView, at point: CGPoint,
                     environment: AppEnvironment, workspace: TaskWorkspaceModel,
                     task: Task, onCustomDate: @escaping () -> Void) {
        let popover = NSPopover()
        popover.behavior = .transient
        // 菜单自身不再持有呈现状态：任何"关闭"动作都落到弹窗本身。
        let isPresented = Binding<Bool>(
            get: { false },
            set: { _ in popover.performClose(nil) })
        let host = NSHostingController(rootView: TaskContextMenuPopover(
            workspace: workspace,
            isPresented: isPresented,
            task: task,
            onCustomDate: {
                popover.performClose(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onCustomDate() }
            })
            .environmentObject(environment))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        // 锚框宽 = 面板宽：面板在锚框下方居中后，左缘正好落在光标上；
        // 锚框抬到光标上方 8pt，抵消箭头高度，面板顶缘落在光标下方约 6pt。
        let anchor = NSView(frame: NSRect(
            x: point.x + TaskContextMenuPopover.menuWidth / 2,
            y: point.y + 8, width: 2, height: 2))
        rowView.addSubview(anchor)
        let delegate = CloseDelegate(anchor: anchor)
        popover.delegate = delegate
        objc_setAssociatedObject(popover, "wf-close-delegate", delegate,
                                 .OBJC_ASSOCIATION_RETAIN)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// 关闭后释放锚点视图，避免每次右键都在行上残留子视图。
    private final class CloseDelegate: NSObject, NSPopoverDelegate {
        let anchor: NSView
        init(anchor: NSView) { self.anchor = anchor }
        func popoverDidClose(_ notification: Notification) {
            anchor.removeFromSuperview()
        }
    }
}
