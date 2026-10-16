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
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "提前结束番茄？"
        alert.informativeText = "当前番茄尚未结束，确定要提前结束并保存专注记录吗？"
        let save = alert.addButton(withTitle: "结束并保存")
        save.setAccessibilityIdentifier("focus-end-confirm-save")
        let discard = alert.addButton(withTitle: "放弃")
        discard.setAccessibilityIdentifier("focus-end-confirm-discard")
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier("focus-end-confirm-cancel")
        alert.window.appearance = NSApp.keyWindow?.effectiveAppearance
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        presentedRequestID = nil
        guard store.pendingEndConfirmation?.id == request.id else { return }
        let choice: FocusEndConfirmationChoice
        switch response {
        case .alertFirstButtonReturn: choice = .save
        case .alertSecondButtonReturn: choice = .discard
        default: choice = .cancel
        }
        _ = store.resolveEndConfirmation(choice)
    }
}
