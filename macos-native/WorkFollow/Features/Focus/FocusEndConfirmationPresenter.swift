import AppKit
import Combine

/// 一个应用级确认器订阅共享 Store，各个专注窗口只发送 .end 命令。
@MainActor
final class FocusEndConfirmationPresenter {
    private static var shared: FocusEndConfirmationPresenter?
    private weak var store: FocusStore?
    private var subscription: AnyCancellable?
    private var presentedRequestID: UUID?

    static func attach(to store: FocusStore) {
        guard shared?.store !== store else { return }
        shared = FocusEndConfirmationPresenter(store: store)
    }

    private init(store: FocusStore) {
        self.store = store
        subscription = store.$pendingEndConfirmation
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] request in self?.present(request) }
    }

    private func present(_ request: FocusEndConfirmation?) {
        guard let request, let store, presentedRequestID == nil,
              store.pendingEndConfirmation?.id == request.id else { return }
        presentedRequestID = request.id
        let response = WorkfollowDialog.runModal(
            title: "提前结束番茄？",
            message: "当前番茄尚未结束，确定要提前结束并保存专注记录吗？",
            actions: [
                .cancel("取消", id: "focus-end-confirm-cancel"),
                .destructive("放弃本次专注", id: "focus-end-confirm-discard"),
                .primary("结束并保存", id: "focus-end-confirm-save")
            ])
        presentedRequestID = nil
        guard store.pendingEndConfirmation?.id == request.id else { return }
        let choice: FocusEndConfirmationChoice
        switch response {
        case 2: choice = .save
        case 1: choice = .discard
        default: choice = .cancel
        }
        _ = store.resolveEndConfirmation(choice)
    }
}
