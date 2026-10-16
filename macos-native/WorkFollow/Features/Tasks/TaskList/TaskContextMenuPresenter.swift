import AppKit
import SwiftUI

/// A cursor-anchored borderless card. Child menus own independent windows
/// and never contribute to the main menu's fitting size.
@MainActor
enum TaskContextMenuPresenter {
    private(set) static var activeSession: Session?

    static func show(in rowView: NSView, at point: CGPoint,
                     environment: AppEnvironment, workspace: TaskWorkspaceModel,
                     task: Task, onCustomDate: @escaping () -> Void) {
        activeSession?.close()
        guard let owner = rowView.window else { return }
        let session = Session(in: rowView, at: point)
        activeSession = session
        let presenter = PopupPresentingWindow()
        presenter.window = owner
        session.coordinator.presentingWindow = presenter
        session.coordinator.root = AnyView(TaskContextMenuPopover(
            workspace: workspace,
            isPresented: Binding(get: { [weak session] in session?.coordinator.presented == true },
                                 set: { [weak session] value in if !value { session?.close() } }),
            task: task,
            onCustomDate: { [weak session] in
                session?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onCustomDate() }
            },
            onChooseParent: { [weak session] in
                DispatchQueue.main.async {
                    session?.showParentPicker(taskID: task.id, workspace: workspace,
                                              environment: environment)
                }
            })
            .environmentObject(environment)
            .environment(\.popupPresentingWindow, presenter))
        session.coordinator.update()
    }

    @MainActor final class Session {
        typealias Adapter = AnchoredPropertyPanel<AnyView>
        let coordinator = Adapter.Coordinator()
        let anchor: Adapter.AnchorView

        init(in rowView: NSView, at point: CGPoint) {
            anchor = Adapter.AnchorView(frame: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
            rowView.addSubview(anchor)
            coordinator.anchor = anchor
            coordinator.width = TaskContextMenuPopover.menuWidth
            coordinator.escapeDepth = 1
            coordinator.title = "任务右键菜单"
            coordinator.presented = true
            coordinator.dismiss = { [weak self] in self?.close() }
            anchor.moved = { [weak self] in
                guard let self else { return }
                if self.anchor.window == nil { self.close() }
                else { self.coordinator.update() }
            }
        }

        func showParentPicker(taskID: UUID, workspace: TaskWorkspaceModel,
                              environment: AppEnvironment) {
            guard coordinator.presented else { return }
            // 换成独立选择面板，保留原鼠标锚点和同一个关闭生命周期。
            coordinator.close()
            coordinator.width = 280
            coordinator.title = "关联主任务"
            coordinator.focusPolicy = .panel
            coordinator.root = AnyView(TaskParentPicker(taskID: taskID, workspace: workspace) { [weak self] in
                self?.close()
            }.environmentObject(environment))
            coordinator.update()
        }

        func close() {
            coordinator.presented = false
            coordinator.close()
            anchor.moved = nil
            anchor.removeFromSuperview()
            if TaskContextMenuPresenter.activeSession === self { TaskContextMenuPresenter.activeSession = nil }
        }
    }
}
