import AppKit
import SwiftUI

/// 「在独立窗口打开」的详情窗口（TI2-17）。
///
/// 滴答的容器切换是 `TTTaskDetailTopView` 的 `containerType`（`detail_side_peek` /
/// `detail_popup`）。本地实现成真正的独立 NSWindow：复用同一个 `TaskInspectorShell`
/// 与同一个工作区，主窗口切任务时它跟着变；重复点击只前置，不会开第二个。
@MainActor
final class TaskDetailWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TaskDetailWindowController()

    private var hosting: NSHostingController<AnyView>?
    /// 测试用：当前是否已有一个可见的详情窗口。
    var isShowing: Bool { window?.isVisible == true }

    func show(workspace: TaskWorkspaceModel, environment: AppEnvironment) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = TaskInspectorShell(workspace: workspace, showBack: false,
                                      commentStore: environment.taskCommentStore)
            .frame(minWidth: 560, minHeight: 560)
            .environmentObject(environment)
        let controller = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(contentViewController: controller)
        window.title = "任务详情"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 640))
        window.delegate = self
        window.center()
        self.window = window
        hosting = controller
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        hosting = nil
        window = nil
    }
}
