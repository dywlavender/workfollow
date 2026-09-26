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
        }
        // 清单菜单：智能清单导航（对齐 Flutter 清单菜单；快捷键集中在视图菜单，
        // 避免与 ⌘1…9 的键位在两个菜单间竞争）。
        CommandMenu("清单") {
            Button("最近 7 天") { environment.navigate(to: .nextSevenDays) }
            Button("今天") { environment.navigate(to: .today) }
            Button("收集箱") { environment.navigate(to: .inbox) }
            Button("所有任务") { environment.navigate(to: .allTasks) }
            Button("已完成") { environment.navigate(to: .completed) }
        }
        // 任务菜单：作用于当前选中任务；完成/恢复经 changeStatus，
        // 走与行点击相同的反馈通道（含提示音与撤销）。
        CommandMenu("任务") {
            Button("完成当前任务") { completeSelected() }
            Button("清除当前日期") { clearSelectedDate() }
            Divider()
            Button("设为高优先级") { setPriority(.high) }
            Button("设为中优先级") { setPriority(.medium) }
            Button("设为低优先级") { setPriority(.low) }
            Button("取消优先级") { setPriority(.none) }
        }
        CommandMenu("视图") {
            Button("今天") { environment.navigate(to: .today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("收集箱") { environment.navigate(to: .inbox) }
                .keyboardShortcut("2", modifiers: .command)
            Button("最近 7 天") { environment.navigate(to: .nextSevenDays) }
                .keyboardShortcut("9", modifiers: .command)
            Button("日历") { environment.navigate(to: .calendar) }
                .keyboardShortcut("4", modifiers: .command)
            Button("笔记") { environment.navigate(to: .notes) }
                .keyboardShortcut("5", modifiers: .command)
            Button("四象限") { environment.navigate(to: .matrix) }
                .keyboardShortcut("6", modifiers: .command)
            Divider()
            Button("显示或隐藏侧栏") { environment.toggleSidebar() }
                .keyboardShortcut("\\", modifiers: .command)
        }
    }

    // MARK: 任务菜单动作

    private func completeSelected() {
        guard let id = environment.taskWorkspace.selectedTaskID,
              let task = environment.taskWorkspace.task(for: id) else { return }
        _ = environment.taskWorkspace.changeStatus(task)
    }

    private func clearSelectedDate() {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        _ = environment.taskWorkspace.clearDueDate(id)
    }

    private func setPriority(_ priority: TaskPriority) {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        _ = environment.taskWorkspace.setPriority(id, priority)
    }
}
