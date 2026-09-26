import AppKit

/// 菜单栏状态图标：快速录入 / 显示打勾 / 退出打勾。
/// 对齐 Flutter `installStatusItem`；只创建一次，由 WorkFollowApp 持有，随应用生命周期存活。
@MainActor
final class StatusItemController: NSObject, ObservableObject {
    private let quickAdd: GlobalQuickAddController
    private var statusItem: NSStatusItem?

    init(quickAdd: GlobalQuickAddController) {
        self.quickAdd = quickAdd
        super.init()
        install()
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle",
                                     accessibilityDescription: "打勾菜单栏")
        let menu = NSMenu()

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
        statusItem = item
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
