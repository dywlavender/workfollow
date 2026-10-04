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

        func close() {
            coordinator.presented = false
            coordinator.close()
            anchor.moved = nil
            anchor.removeFromSuperview()
            if TaskContextMenuPresenter.activeSession === self { TaskContextMenuPresenter.activeSession = nil }
        }
    }
}
