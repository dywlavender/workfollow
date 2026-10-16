import AppKit
import Combine

/// 菜单栏状态图标：专注倒计时 / 快速录入 / 显示打勾 / 退出打勾。
/// 专注进行中按钮变成剩余时间，菜单提供暂停/继续、完成与放弃（对齐滴答
/// 「从任务列表、任务详情和 Mini 窗口开始专注」的 Mini 语义）；空闲恢复默认图标。
@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private enum FocusAction: Int {
        case start, pause, resume, end, abandon, startBreak, skipBreak, openFocus
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
        if focusStore.phase == .idle && focusStore.completionContext?.extraTimeStartedAt == nil {
            button.title = ""
            button.image = NSImage(systemSymbolName: "checkmark.circle",
                                   accessibilityDescription: "打勾菜单栏")
        } else {
            button.image = nil
            button.title = FocusViewLogic.clockText(focusStore.presentation.displaySeconds)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        if focusStore.phase != .idle || focusStore.pendingBreak || focusStore.completionContext?.extraTimeStartedAt != nil {
            let presentation = focusStore.presentation
            let entry = menu.addItem(withTitle: presentation.phaseTitle, action: nil, keyEquivalent: "")
            entry.isEnabled = false
            for command in presentation.availableActions {
                if let action = focusAction(command) { menu.addItem(actionItem(command.title, action)) }
            }
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
        case .openFocus: onOpenFocus()
        default:
            if let command = FocusCommand(rawValue: String(describing: action)) { _ = focusStore.perform(command) }
        }
    }

    private func focusAction(_ command: FocusCommand) -> FocusAction? {
        switch command {
        case .start: .start; case .pause: .pause; case .resume: .resume; case .end: .end
        case .abandon: .abandon; case .startBreak: .startBreak; case .skipBreak: .skipBreak
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
