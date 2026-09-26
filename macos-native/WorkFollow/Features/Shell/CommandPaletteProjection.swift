import Foundation

enum CommandPaletteAction: Equatable {
    case createTask(String)
    case openTask(UUID)
    case openNote(UUID)
    case navigate(NativeDestination)
    case toggleAppearance
}

struct CommandPaletteEntry: Identifiable {
    /// 区分首项"新建任务"（视图渲染高亮）与任务/笔记/命令结果。
    enum Kind: Equatable { case createTask, task, note, command }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let symbol: String
    let action: CommandPaletteAction
}

enum CommandPaletteProjection {
    static func entries(query rawQuery: String,
                        tasks: [Task],
                        notes: [Note],
                        creationList: String,
                        schedulesForToday: Bool,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> [CommandPaletteEntry] {
        let commands = commandEntries()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // 首项恒为"新建任务"：无论是否输入了 query，都提供把当前输入落到
        // 当前上下文的入口（Flutter 对齐：有 query 显示「query」，空 query
        // 显示"新建任务"，命令面板从不发明"未命名任务"去追赶用户）。
        let create = CommandPaletteEntry(
            id: "create-task",
            kind: .createTask,
            title: query.isEmpty ? "新建任务" : "新建任务「\(query)」",
            subtitle: "保存到\(creationList)\(schedulesForToday ? " · 安排到今天" : "")",
            symbol: "plus",
            action: .createTask(query))

        guard !query.isEmpty else { return [create] + commands }

        let loweredQuery = query.lowercased()
        let taskResults = tasks.lazy
            .filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned && !$0.isConverted }
            .filter {
                ($0.title + " " + $0.list.name + " " + $0.document.plainText + " " + $0.tags.joined(separator: " "))
                    .localizedLowercase.contains(loweredQuery)
            }
            .prefix(7)
            .map { task in
                let time = taskTimeLabel(for: task, now: now, calendar: calendar) ?? "未安排"
                return CommandPaletteEntry(
                    id: "task-\(task.id.uuidString)",
                    kind: .task,
                    title: task.title.isEmpty ? "无标题" : task.title,
                    subtitle: "\(task.list.name) · \(time)",
                    symbol: task.isClosed ? "checkmark.square.fill" : "square",
                    action: .openTask(task.id))
            }

        let noteResults = notes.lazy
            .filter { $0.deletedAt == nil }
            .filter {
                ($0.title + " " + $0.document.plainText + " " + $0.folder)
                    .localizedLowercase.contains(loweredQuery)
            }
            .prefix(5)
            .map { note in
                CommandPaletteEntry(
                    id: "note-\(note.id.uuidString)",
                    kind: .note,
                    title: note.title.isEmpty ? "未命名笔记" : note.title,
                    subtitle: "笔记 · \(note.folder)",
                    symbol: "text.alignleft",
                    action: .openNote(note.id))
            }

        let matchingCommands = commands.filter {
            ($0.title + " " + $0.subtitle).localizedLowercase.contains(loweredQuery)
        }
        return [create] + taskResults + noteResults + matchingCommands
    }

    /// "切换外观"命令的轮换顺序：跟随系统 → 浅色 → 深色 → 跟随系统。
    /// 经 AppEnvironment.appearance 通道生效（视图层执行赋值）。
    static func nextAppearance(after current: NativeAppearance) -> NativeAppearance {
        let all = NativeAppearance.allCases
        guard let index = all.firstIndex(of: current) else { return .system }
        return all[(index + 1) % all.count]
    }

    @MainActor
    @discardableResult
    static func openTask(_ id: UUID, workspace: TaskWorkspaceModel,
                         navigation: AppNavigation) -> Bool {
        guard let task = workspace.task(for: id), task.deletedAt == nil,
              task.skippedAt == nil, !task.isAbandoned, !task.isConverted else { return false }
        workspace.activeList = nil
        workspace.activeTag = nil
        let listName = task.list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination: NativeDestination
        if listName == TaskList.inbox.name {
            destination = .inbox
        } else {
            destination = .allTasks
            if !listName.isEmpty { workspace.activeList = listName }
        }
        navigation.taskSelectionToPreserveOnNextNavigation = navigation.destination == destination ? nil : id
        navigation.destination = destination
        workspace.select(id)
        return true
    }

    @MainActor
    @discardableResult
    static func openNote(_ id: UUID, workspace: NotesWorkspaceModel,
                         taskWorkspace: TaskWorkspaceModel,
                         navigation: AppNavigation) -> Bool {
        guard workspace.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return false }
        taskWorkspace.activeList = nil
        taskWorkspace.activeTag = nil
        taskWorkspace.select(nil)
        navigation.destination = .notes
        workspace.selectedID = id
        return true
    }

    @MainActor
    @discardableResult
    static func createTask(_ title: String, workspace: TaskWorkspaceModel,
                           navigation: AppNavigation) -> TaskActionResult {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = workspace.activeList ?? TaskList.inbox.name
        let dueAt = navigation.destination == .today
            ? workspace.calendar.startOfDay(for: workspace.clock()) : nil
        // 空标题（空 query 的"新建任务"首项）落一个"无标题"任务，仍进当前上下文；
        // 行渲染对空标题本就显示"无标题"。
        return workspace.createDraft(
            title: title.isEmpty ? "无标题" : title,
            list: list,
            schedule: TaskSchedule(dueAt: dueAt),
            priority: .none,
            tags: [],
            reminder: nil,
            repeatFrequency: .never)
    }

    private static func commandEntries() -> [CommandPaletteEntry] {
        [
            command("打开最近 7 天", "查看逾期与未来七天", "calendar.badge.clock", .navigate(.nextSevenDays)),
            command("打开今天", "查看现在最重要的事", "sun.max", .navigate(.today)),
            command("打开收集箱", "稍后再安排", "tray", .navigate(.inbox)),
            command("打开所有任务", "按日期查看全部任务", "list.bullet.rectangle", .navigate(.allTasks)),
            command("打开日历", "按日期查看任务", "calendar", .navigate(.calendar)),
            command("打开笔记", "继续写下刚才的想法", "text.alignleft", .navigate(.notes)),
            command("打开任务垃圾桶", "恢复或彻底删除已移除的任务", "trash", .navigate(.trash)),
            command("打开笔记垃圾桶", "恢复或彻底删除已移除的笔记", "trash", .navigate(.notesTrash)),
            command("切换外观", "在浅色、深色和跟随系统之间轮换", "moon", .toggleAppearance)
        ]
    }

    private static func command(_ title: String, _ subtitle: String, _ symbol: String,
                                _ action: CommandPaletteAction) -> CommandPaletteEntry {
        CommandPaletteEntry(id: "command-\(title)", kind: .command, title: title,
                            subtitle: subtitle, symbol: symbol, action: action)
    }

    private static func taskTimeLabel(for task: Task, now: Date, calendar: Calendar) -> String? {
        guard !task.isClosed else { return "已完成" }
        guard let due = task.schedule.dueAt else { return nil }
        let dayOffset = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        let dayLabel: String
        switch dayOffset {
        case 0: dayLabel = "今天"
        case -1: dayLabel = "昨天"
        case 1: dayLabel = "明天"
        default:
            let parts = calendar.dateComponents([.month, .day], from: due)
            dayLabel = "\(parts.month ?? 0) 月 \(parts.day ?? 0) 日"
        }
        guard task.schedule.hasTime else { return dayLabel }
        let time = calendar.dateComponents([.hour, .minute], from: due)
        return "\(dayLabel) \(String(format: "%02d:%02d", time.hour ?? 0, time.minute ?? 0))"
    }
}
