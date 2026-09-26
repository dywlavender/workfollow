import AppKit
import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var quickAdd: GlobalQuickAddController
    @AppStorage("globalQuickAddEnabled") private var globalQuickAddEnabled = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建任务") { environment.newTask() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("查找正文…") {
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)),
                                 to: nil, from: item)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu("导航") {
            Button("快速打开…") { environment.commandPalettePresented = true }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Toggle("启用全局快速添加（⌘⇧A）", isOn: $globalQuickAddEnabled)
                .onChange(of: globalQuickAddEnabled) { _, enabled in
                    quickAdd.setEnabled(enabled)
                }
            Divider()
            Button("今天") { environment.navigate(to: .today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("收集箱") { environment.navigate(to: .inbox) }
                .keyboardShortcut("2", modifiers: .command)
        }
    }
}
