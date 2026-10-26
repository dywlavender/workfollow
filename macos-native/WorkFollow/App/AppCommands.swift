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
            Button("新建悬浮笔记") { environment.newFloatingNote() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销") { routeHistory(redo: false) }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!canUndo)
            Button("重做") { routeHistory(redo: true) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!canRedo)
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
            Button("本周计划") { environment.navigate(to: .weekPlan) }
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
                .keyboardShortcut("0", modifiers: [.command, .shift])
            // 滴答同款三档快设日期（滴答用 ⌘1/2/3；这里 ⌘1/2 已是视图导航，
            // 挪到 ⌘⇧ 档，语义不变：选中任务后一键改期）。
            Button("设为今天") { setDayOffset(0) }
                .disabled(!hasSelectedTask)
                .keyboardShortcut("1", modifiers: [.command, .shift])
            Button("设为明天") { setDayOffset(1) }
                .disabled(!hasSelectedTask)
                .keyboardShortcut("2", modifiers: [.command, .shift])
            Button("设为下周") { setNextWeek() }
                .disabled(!hasSelectedTask)
                .keyboardShortcut("3", modifiers: [.command, .shift])
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
        textUndoManager?.canUndo ?? environment.taskWorkspace.canUndo
    }
    private var canRedo: Bool {
        textUndoManager?.canRedo ?? environment.taskWorkspace.canRedo
    }

    private func routeHistory(redo: Bool) {
        if let editor = NSApp.keyWindow?.firstResponder as? NativeTextView {
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
