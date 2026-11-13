import AppKit
import SwiftUI

struct AppCommands: Commands {
    @ObservedObject private var editorSession = MilkdownEditorRegistry.shared
    @ObservedObject private var shortcuts = AppShortcutStore.shared
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var quickAdd: GlobalQuickAddController

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            SettingsLink { Text("设置…") }
                .keyboardShortcut(shortcuts.chord(for: .openSettings).swiftUIShortcut)
        }
        CommandGroup(replacing: .newItem) {
            Button("新建任务") { environment.newTask() }
                .keyboardShortcut(shortcuts.chord(for: .newTask).swiftUIShortcut)
            Button("新建悬浮笔记") { environment.newFloatingNote() }
                .keyboardShortcut(shortcuts.chord(for: .newFloatingNote).swiftUIShortcut)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { routeHistory(redo: false) }
                .keyboardShortcut(shortcuts.chord(for: .undo).swiftUIShortcut)
                .disabled(!canUndo)
            Button("重做") { routeHistory(redo: true) }
                .keyboardShortcut(shortcuts.chord(for: .redo).swiftUIShortcut)
                .disabled(!canRedo)
        }
        CommandGroup(after: .textEditing) {
            Button("查找正文…") {
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)),
                                 to: nil, from: item)
            }
            .keyboardShortcut(shortcuts.chord(for: .findBody).swiftUIShortcut)
        }
        CommandMenu("导航") {
            Button("快速打开…") { environment.commandPalettePresented = true }
                .keyboardShortcut(shortcuts.chord(for: .quickOpen).swiftUIShortcut)
            Divider()
            Toggle("启用全局快速添加（\(shortcuts.chord(for: .globalQuickAdd).label)）",
                   isOn: Binding(get: { quickAdd.isEnabled }, set: { enabled in
                if !quickAdd.setEnabled(enabled) {
                    environment.feedback.show(FeedbackEvent(kind: .error,
                        message: AppShortcutError.globalUnavailable.localizedDescription))
                }
            }))
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
            // 任务 → 分组归属（滴答：分组是任务的**结构性归属**）。
            //
            // 分组此前只有"添加/重命名/删除/排序"，唯独缺"把任务放进分组"——
            // 数据层 `setTaskSection` 早已就绪，这里补上入口。
            // 行内右键与"拖到分组之间"是滴答的主手势，登记为下一步（本轮先给可用入口）。
            if let list = environment.taskWorkspace.activeList,
               let taskID = environment.taskWorkspace.selectedTaskID {
                let sections = environment.taskWorkspace.listSections(forList: list)
                if !sections.isEmpty {
                    Menu("移动到分组") {
                        Button("未分组") {
                            _ = environment.taskWorkspace.setTaskSection(taskID, sectionID: nil)
                        }
                        Divider()
                        ForEach(sections) { section in
                            Button(section.title) {
                                _ = environment.taskWorkspace.setTaskSection(taskID, sectionID: section.id)
                            }
                        }
                    }
                }
            }
            Button("完成当前任务") { completeSelected() }
                .disabled(!hasSelectedTask)
            Button("清除当前日期") { clearSelectedDate() }
                .disabled(!hasSelectedTask)
                .keyboardShortcut(shortcuts.chord(for: .clearTaskDate).swiftUIShortcut)
            // 滴答同款三档快设日期（滴答用 ⌘1/2/3；这里 ⌘1/2 已是视图导航，
            // 挪到 ⌘⇧ 档，语义不变：选中任务后一键改期）。
            Button("设为今天") { setDayOffset(0) }
                .disabled(!hasSelectedTask)
                .keyboardShortcut(shortcuts.chord(for: .taskToday).swiftUIShortcut)
            Button("设为明天") { setDayOffset(1) }
                .disabled(!hasSelectedTask)
                .keyboardShortcut(shortcuts.chord(for: .taskTomorrow).swiftUIShortcut)
            Button("设为下周") { setNextWeek() }
                .disabled(!hasSelectedTask)
                .keyboardShortcut(shortcuts.chord(for: .taskNextWeek).swiftUIShortcut)
            Divider()
            Button("设为高优先级") { setPriority(.high) }
            Button("设为中优先级") { setPriority(.medium) }
            Button("设为低优先级") { setPriority(.low) }
            Button("取消优先级") { setPriority(.none) }
        }
        CommandMenu("视图") {
            Button("今天") { environment.navigate(to: .today) }
                .keyboardShortcut(shortcuts.chord(for: .today).swiftUIShortcut)
            Button("收集箱") { environment.navigate(to: .inbox) }
                .keyboardShortcut(shortcuts.chord(for: .inbox).swiftUIShortcut)
            Button("最近 7 天") { environment.navigate(to: .nextSevenDays) }
                .keyboardShortcut(shortcuts.chord(for: .nextSevenDays).swiftUIShortcut)
            Button("日历") { environment.navigate(to: .calendar) }
                .keyboardShortcut(shortcuts.chord(for: .calendar).swiftUIShortcut)
            Button("笔记") { environment.navigate(to: .notes) }
                .keyboardShortcut(shortcuts.chord(for: .notes).swiftUIShortcut)
            Button("四象限") { environment.navigate(to: .matrix) }
                .keyboardShortcut(shortcuts.chord(for: .matrix).swiftUIShortcut)
            Divider()
            Button("显示或隐藏侧栏") { environment.toggleSidebar() }
                .keyboardShortcut(shortcuts.chord(for: .toggleSidebar).swiftUIShortcut)
        }
        CommandGroup(after: .help) {
            Divider()
            Button("新手引导") { environment.showWelcomeGuide() }
            Button("重置新手引导…") { environment.resetWelcomeGuide() }
        }
        #if DEBUG
        // 编辑器内核切换的 P0 骨架验收入口（验收后随正式组件移除）。
        CommandMenu("调试") {
            Button("Quill 内核 Spike") {
                quillSpike.presentWindow()
            }
            Button("Quill 探针：注入文本") {
                NotificationCenter.default.post(name: .quillProbeInsert, object: nil)
            }
        }
        #endif
    }

    #if DEBUG
    private let quillSpike = QuillSpikeWindowController()
    #endif

    /// Text first responders keep their native history; business commands use
    /// the workspace history only after editing has ended.
    private var textUndoManager: UndoManager? {
        guard let responder = NSApp.keyWindow?.firstResponder,
              responder is NSTextView || responder is NSTextField else { return nil }
        return responder.undoManager
    }

    private var canUndo: Bool {
        if let editor = editorSession.focusedEditor { return editor.canUndo }
        return textUndoManager?.canUndo ?? environment.taskWorkspace.canUndo
    }
    private var canRedo: Bool {
        if let editor = editorSession.focusedEditor { return editor.canRedo }
        return textUndoManager?.canRedo ?? environment.taskWorkspace.canRedo
    }

    private func routeHistory(redo: Bool) {
        if let editor = editorSession.focusedEditor { editor.perform(redo ? "redo" : "undo") }
        else if let editor = NSApp.keyWindow?.firstResponder as? NativeTextView {
            if redo { editor.redo(nil) } else { editor.undo(nil) }
        } else if let manager = textUndoManager {
            if redo { manager.redo() } else { manager.undo() }
        } else if redo { environment.taskWorkspace.redo() }
        else { environment.taskWorkspace.undo() }
    }

    // MARK: 任务菜单动作

    private var hasSelectedTask: Bool { environment.taskWorkspace.selectedTaskID != nil }

    private func completeSelected() {
        guard let id = environment.taskWorkspace.selectedTaskID,
              let task = environment.taskWorkspace.task(for: id) else { return }
        _ = environment.taskWorkspace.changeStatus(task)
    }

    private func clearSelectedDate() {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        _ = environment.taskWorkspace.clearDueDate(id)
    }

    private func setDayOffset(_ offset: Int) {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        _ = environment.taskWorkspace.moveDueDate(id, to: environment.taskWorkspace.dateFromToday(offset))
    }

    /// 「下周」= 下周一（跨年也由 yearForWeekOfYear 兜住）。
    private func setNextWeek() {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        let calendar = environment.taskWorkspace.calendar
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear],
                                            from: environment.taskWorkspace.clock())
        comps.weekOfYear = (comps.weekOfYear ?? 0) + 1
        comps.weekday = 2
        guard let nextMonday = calendar.date(from: comps) else { return }
        _ = environment.taskWorkspace.moveDueDate(id, to: nextMonday)
    }

    private func setPriority(_ priority: TaskPriority) {
        guard let id = environment.taskWorkspace.selectedTaskID else { return }
        _ = environment.taskWorkspace.setPriority(id, priority)
    }
}
