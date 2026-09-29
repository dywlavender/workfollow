import AppKit
import Combine

/// 菜单栏状态图标：专注倒计时 / 快速录入 / 显示打勾 / 退出打勾。
/// 专注进行中按钮变成剩余时间，菜单提供暂停/继续、完成与放弃（对齐滴答
/// 「从任务列表、任务详情和 Mini 窗口开始专注」的 Mini 语义）；空闲恢复默认图标。
@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private enum FocusAction: Int {
        case pauseResume, finishEarly, giveUp, openFocus
    }

    private let quickAdd: GlobalQuickAddController
    private let focusStore: FocusStore
    private let onOpenFocus: () -> Void
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

    init(quickAdd: GlobalQuickAddController, focusStore: FocusStore,
         onOpenFocus: @escaping () -> Void) {
        self.quickAdd = quickAdd
        self.focusStore = focusStore
        self.onOpenFocus = onOpenFocus
        super.init()
        install()
        // objectWillChange 是 willSet：跳一拍到主运行循环再读，拿到的才是新值。
        focusStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle",
                                     accessibilityDescription: "打勾菜单栏")
        rebuildMenu()
        statusItem = item
    }

    /// 专注进行中：按钮换成等宽剩余时间；空闲恢复默认图标。菜单随阶段重建。
    private func refresh() {
        guard let button = statusItem?.button else { return }
        if focusStore.phase == .idle {
            button.title = ""
            button.image = NSImage(systemSymbolName: "checkmark.circle",
                                   accessibilityDescription: "打勾菜单栏")
        } else {
            button.image = nil
            button.title = FocusViewLogic.clockText(focusStore.remainingSeconds)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        if focusStore.phase != .idle {
            let sessionTitle: String
            switch focusStore.phase {
            case .focusing: sessionTitle = "专注中"
            case .breaking: sessionTitle = focusStore.isLongBreak ? "长休息中" : "休息中"
            case .pausedFocus: sessionTitle = "已暂停"
            case .pausedBreak: sessionTitle = "休息已暂停"
            case .idle: sessionTitle = ""
            }
            let sessionEntry = menu.addItem(withTitle: sessionTitle, action: nil, keyEquivalent: "")
            sessionEntry.isEnabled = false
            menu.addItem(actionItem(focusStore.phase == .focusing ? "暂停" : "继续",
                                    .pauseResume))
            if focusStore.phase == .focusing {
                menu.addItem(actionItem("完成本番茄", .finishEarly))
            }
            menu.addItem(actionItem("放弃专注", .giveUp))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem("打开专注页", .openFocus))
        menu.addItem(.separator())

        let captureEntry = NSMenuItem(title: "快速录入",
                                      action: #selector(showQuickAdd),
                                      keyEquivalent: "")
        captureEntry.target = self
        menu.addItem(captureEntry)

        let openEntry = NSMenuItem(title: "显示打勾",
                                   action: #selector(showMainWindow),
                                   keyEquivalent: "")
        openEntry.target = self
        menu.addItem(openEntry)

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出打勾",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "")

        item.menu = menu
    }

    private func actionItem(_ title: String, _ action: FocusAction) -> NSMenuItem {
        let entry = NSMenuItem(title: title,
                               action: #selector(performFocusAction(_:)),
                               keyEquivalent: "")
        entry.tag = action.rawValue
        entry.target = self
        return entry
    }

    @objc private func performFocusAction(_ sender: NSMenuItem) {
        guard let action = FocusAction(rawValue: sender.tag) else { return }
        switch action {
        case .pauseResume:
            if focusStore.phase == .focusing { focusStore.pause() } else { focusStore.resume() }
        case .finishEarly:
            _ = focusStore.finishEarly()
        case .giveUp:
            _ = focusStore.giveUp()
        case .openFocus:
            onOpenFocus()
        }
    }

    /// 菜单栏录入独立于主窗口当前页面；提交沿用解析词表，
    /// 解析不到清单时进收集箱（收集箱语义由 QuickAddParser 兜底保证）。
    @objc private func showQuickAdd() {
        quickAdd.showPanel()
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }
        window?.makeKeyAndOrderFront(nil)
    }
}
