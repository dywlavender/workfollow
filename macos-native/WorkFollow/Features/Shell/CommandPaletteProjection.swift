import Foundation

enum CommandPaletteAction: Equatable {
    case createTask(String)
    case openTask(UUID)
    case openNote(UUID)
    case navigate(NativeDestination)
    case toggleAppearance
}

struct CommandPaletteEntry: Identifiable {
    /// 搜索结果优先；创建入口使用独立快捷键。
    enum Kind: Equatable { case createTask, task, note, command }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let symbol: String
    let action: CommandPaletteAction
    var snippet: String? = nil
    var relevance: Int = 0
}

enum CommandPaletteProjection {
    static func entries(query rawQuery: String,
                        tasks: [Task],
                        notes: [Note],
                        creationList: String,
                        schedulesForToday: Bool,
                        now: Date = Date(),
                        calendar: Calendar = .current,
                        taskLimit: Int = 7, noteLimit: Int = 5,
                        includeAllWhenEmpty: Bool = false) -> [CommandPaletteEntry] {
        let commands = commandEntries()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // 没有搜索词时保留快速新建；有搜索词时先打开已有内容，避免回车误建。
        let create = CommandPaletteEntry(
            id: "create-task",
            kind: .createTask,
            title: query.isEmpty ? "新建任务" : "新建任务「\(query)」",
            subtitle: "保存到\(creationList)\(schedulesForToday ? " · 安排到今天" : "")",
            symbol: "plus",
            action: .createTask(query))

        if query.isEmpty && !includeAllWhenEmpty { return [create] + commands }

        let loweredQuery = query.lowercased()
        let taskResults = tasks
            .filter { !$0.isNoteTask && $0.deletedAt == nil && $0.skippedAt == nil && !$0.isAbandoned && !$0.isConverted }
            .filter {
                $0.document.matches(loweredQuery, prefix: $0.title + " " + $0.list.name + " ",
                                    suffix: " " + $0.tags.joined(separator: " "), lowercase: true)
            }
            .enumerated().sorted { left, right in
                let lhs = relevance(query: loweredQuery, title: left.element.title,
                    metadata: left.element.list.name + " " + left.element.tags.joined(separator: " "))
                let rhs = relevance(query: loweredQuery, title: right.element.title,
                    metadata: right.element.list.name + " " + right.element.tags.joined(separator: " "))
                return lhs == rhs ? left.offset < right.offset : lhs < rhs
            }.prefix(taskLimit).map(\.element)
            .map { task in
                let time = taskTimeLabel(for: task, now: now, calendar: calendar) ?? "未安排"
                return CommandPaletteEntry(
                    id: "task-\(task.id.uuidString)",
                    kind: .task,
                    title: task.title.isEmpty ? "无标题" : task.title,
                    subtitle: "\(task.list.name) · \(time)",
                    symbol: task.isClosed ? "checkmark.square.fill" : "square",
                    action: .openTask(task.id),
                    snippet: matchingSnippet(in: task.document, query: query),
                    relevance: relevance(query: loweredQuery, title: task.title,
                        metadata: task.list.name + " " + task.tags.joined(separator: " ")))
            }

        let noteResults = notes
            .filter { $0.deletedAt == nil }
            .filter {
                $0.document.matches(loweredQuery, prefix: $0.title + " ", suffix: " " + $0.folder, lowercase: true)
            }
            .enumerated().sorted { left, right in
                let lhs = relevance(query: loweredQuery, title: left.element.title, metadata: left.element.folder)
                let rhs = relevance(query: loweredQuery, title: right.element.title, metadata: right.element.folder)
                return lhs == rhs ? left.offset < right.offset : lhs < rhs
            }.prefix(noteLimit).map(\.element)
            .map { note in
                CommandPaletteEntry(
                    id: "note-\(note.id.uuidString)",
                    kind: .note,
                    title: note.title.isEmpty ? "未命名笔记" : note.title,
                    subtitle: "笔记 · \(note.folder)",
                    symbol: "text.alignleft",
                    action: .openNote(note.id),
                    snippet: matchingSnippet(in: note.document, query: query),
                    relevance: relevance(query: loweredQuery, title: note.title, metadata: note.folder))
            }

        let matchingCommands = commands.filter {
            ($0.title + " " + $0.subtitle).localizedLowercase.contains(loweredQuery)
        }
        let results = (taskResults + noteResults).enumerated().sorted { left, right in
            left.element.relevance == right.element.relevance
                ? left.offset < right.offset : left.element.relevance < right.element.relevance
        }.map(\.element)
        return results + matchingCommands + [create]
    }

    private static func relevance(query: String, title: String, metadata: String) -> Int {
        let title = title.localizedLowercase
        if title == query { return 0 }
        if title.hasPrefix(query) { return 1 }
        if title.contains(query) { return 2 }
        return metadata.localizedLowercase.contains(query) ? 3 : 4
    }

    /// 只为截取后的结果读取正文，避免搜索时展开全部文档。
    ///
    /// 延迟文档连「截取后的结果」也不水合：只读摘要里的头/尾（各 160 字），
    /// 命中在正文中段时退化成首行。搜索是高频操作，一旦为片段 resolve，
    /// 命中 N 条就要读 N 篇正文——这正是延迟加载要避免的。
    private static func matchingSnippet(in document: NativeDocument, query: String) -> String? {
        if let summary = document.deferredSummary {
            for candidate in [summary.head, summary.tail] {
                if let snippet = snippet(in: candidate, query: query) { return snippet }
            }
            return summary.firstLine
        }
        let text = document.plainText
        return snippet(in: text, query: query)
    }

    /// 命中词前后各取一段，压缩成一行。
    private static func snippet(in text: String, query: String) -> String? {
        guard let match = text.range(of: query, options: .caseInsensitive) else { return nil }
        let start = text.index(match.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 70, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "")
            + text[start..<end].replacingOccurrences(of: "\n", with: " ")
            + (end < text.endIndex ? "…" : "")
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
        workspace.openFilter(nil)
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
        navigation.destination = .notes
        taskWorkspace.activeList = nil
        taskWorkspace.activeTag = nil
        taskWorkspace.select(nil)
        workspace.selectedID = id
        return true
    }

    @MainActor
    @discardableResult
    static func createTask(_ title: String, workspace: TaskWorkspaceModel,
                           navigation: AppNavigation) -> TaskActionResult {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = workspace.activeList ?? TaskList.inbox.name
        let base = workspace.calendar.startOfDay(for: workspace.clock())
        let dueAt: Date?
        switch navigation.destination {
        case .today: dueAt = base
        case .tomorrow: dueAt = workspace.calendar.date(byAdding: .day, value: 1, to: base)
        default: dueAt = nil
        }
        // 空标题（空 query 的"新建任务"首项）落一个"无标题"任务，仍进当前上下文；
        // 行渲染对空标题本就显示"无标题"。
        return workspace.createDraft(
            title: title.isEmpty ? "无标题" : title,
            list: list,
            schedule: TaskSchedule(dueAt: dueAt),
            priority: .none,
            tags: [],
            reminder: nil,
            repeatFrequency: .never,
            // 空查询创建 = 标题还没起过，直接把焦点给标题（滴答 `focusOnTaskTitle`）。
            focusTitle: title.isEmpty)
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
