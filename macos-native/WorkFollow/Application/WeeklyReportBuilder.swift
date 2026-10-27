import Foundation

struct WeeklyReport {
    struct Adjustment: Identifiable {
        let task: Task
        let destinationWeek: String
        var id: UUID { task.id }
    }
    struct Progress: Identifiable {
        let task: Task
        let completedChildren: [Task]
        let totalChildren: Int
        var id: UUID { task.id }
    }
    let weekStart: Date
    let title: String
    let planned: [Task]
    let completed: [Task]
    let pending: [Task]
    let carried: [Adjustment]
    let abandoned: [Task]
    let added: [Task]
    let rescheduled: [Task]
    let progress: [Progress]
    let nextWeek: [Task]
    let focusSeconds: Int
    let range: SummaryDateRange
    let tasksByID: [UUID: Task]
    let facts: [UUID: SummaryTaskFacts]
    let filteredTaskIDs: Set<UUID>
    let listFolders: [String: String]
}

struct WeeklyReportBuilder {
    let calendar: Calendar

    func report(tasks: [Task], weekOf: Date, listName: String? = nil,
                filter: SummaryFilter = .all, tagDirectory: [TaskTag] = [],
                focusRecords: [PomodoroRecord] = [], range selectedRange: SummaryDateRange? = nil,
                listNames: Set<String> = [], startedTaskIDs: Set<UUID> = [],
                listFolders: [String: String] = [:]) -> WeeklyReport {
        let range = selectedRange ?? .week(containing: weekOf, calendar: calendar)
        let start = range.start
        let projection = WeeklyPlanProjection(weekStart: start, calendar: calendar)
        let scopeList = listName ?? filter.listName
        let scopeLists = listNames.isEmpty ? scopeList.map { Set([$0]) } ?? [] : listNames
        let matchingTags = filter.tagName.map { TaskTagHierarchy(tagDirectory).names(includingDescendantsOf: $0) }
        let available = tasks.filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted }
        let facts = SummaryTaskFacts.index(tasks: available, focusRecords: focusRecords, range: range, startedTaskIDs: startedTaskIDs)
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let valid = available.filter {
            (scopeLists.isEmpty || scopeLists.contains($0.list.name))
                && (matchingTags == nil || !matchingTags!.isDisjoint(with: $0.tags))
                && (filter.priority == nil || $0.priority == filter.priority)
                && (filter.status == .all || facts[$0.id]?.status == filter.status)
        }
        func topLevel(_ values: [Task]) -> [Task] {
            let ids = Set(values.map(\.id))
            return values.filter { $0.parentID.map { !ids.contains($0) } ?? true }
        }
        func includes(_ task: Task, in period: SummaryDateRange) -> Bool {
            if period.kind == .week {
                return WeeklyPlanProjection(weekStart: period.start, calendar: calendar).includes(task)
            }
            if let due = task.schedule.dueAt {
                return due < period.end && (task.schedule.dueEndAt ?? due) >= period.start
            }
            // A weekly plan has no invented day. It can participate in a month
            // or custom range containing its week, but not in a single-day report.
            guard period.kind != .day, let key = task.weeklyPlanning?.currentWeek,
                  let week = SummaryStore.date(fromDayKey: key, calendar: calendar) else { return false }
            return period.contains(week)
        }
        func history(_ task: Task) -> TaskWeeklyPlanning.Entry? {
            if range.kind == .week {
                return task.weeklyPlanning?.history.first { $0.weekKey == projection.weekKey }
            }
            return task.weeklyPlanning?.history.first { $0.movedAt.map(range.contains) == true }
        }
        let participated = valid.filter { includes($0, in: range) || history($0) != nil }
        let actualCompleted = valid.filter { $0.status == .completed && $0.completedAt.map(range.contains) == true }
        let validIDs = Set(valid.map(\.id))
        let outcomes = topLevel(actualCompleted).filter { task in
            task.parentID.flatMap { byID[$0] }.map { $0.isClosed || !validIDs.contains($0.id) } ?? true
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let children = Dictionary(grouping: available.filter { $0.parentID != nil && !$0.isAbandoned }, by: { $0.parentID! })
        let progresses = valid.filter { !$0.isClosed }.compactMap { parent -> WeeklyReport.Progress? in
            let all = children[parent.id] ?? []
            let done = all.filter { $0.status == .completed && $0.completedAt.map(range.contains) == true }
            return done.isEmpty ? nil : .init(task: parent, completedChildren: done, totalChildren: all.count)
        }.sorted { $0.task.title < $1.task.title }
        let moved = topLevel(participated.filter { history($0)?.movedToWeek != nil }).compactMap { task -> WeeklyReport.Adjustment? in
            guard let target = history(task)?.movedToWeek else { return nil }
            return .init(task: task, destinationWeek: target)
        }
        let next = range.next(calendar: calendar)
        let scopeIDs = Set(valid.map(\.id))
        let seconds = focusRecords.filter {
            range.contains($0.startedAt)
                && ((scopeLists.isEmpty && matchingTags == nil && filter.priority == nil && filter.status == .all)
                    || $0.taskID.map { scopeIDs.contains($0) } == true)
        }.reduce(0) { $0 + $1.activeSeconds }
        return WeeklyReport(weekStart: start, title: range.title(calendar: calendar),
            planned: topLevel(participated), completed: outcomes,
            pending: topLevel(valid.filter { !$0.isClosed && includes($0, in: range) }), carried: moved,
            abandoned: topLevel(valid.filter { $0.status != .completed && $0.isAbandoned && $0.abandonedAt.map(range.contains) == true }),
            added: topLevel(participated.filter { range.contains($0.createdAt) }),
            rescheduled: topLevel(participated.filter { task in
                guard range.kind == .week, projection.includes(task), let entry = history(task) else { return false }
                return entry.schedule != task.schedule
            }), progress: progresses,
            nextWeek: topLevel(valid.filter { !$0.isClosed && includes($0, in: next) }), focusSeconds: seconds,
            range: range, tasksByID: byID, facts: facts, filteredTaskIDs: validIDs,
            listFolders: listFolders)
    }

    func document(for report: WeeklyReport, options: SummaryDocumentOptions = .standard,
                  preserving existing: NativeDocument? = nil) -> NativeDocument {
        struct Row { let task: Task; var suffix = "" }
        let isWeek = report.range.kind == .week
        let reviewTitle = isWeek ? "本周复盘" : "本期复盘"
        let nextTitle = isWeek ? "下周重点" : "下一周期任务"
        var blocks = [DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: report.title)])]
        func heading(_ text: String, level: Int = 2) {
            blocks.append(DocumentBlock(kind: .heading(level), runs: [DocumentRun(text: text)]))
        }
        func paragraph(_ text: String) { blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: text)])) }
        func date(_ value: Date, time: Bool = false) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = time ? "M月d日 HH:mm" : "M月d日"
            return formatter.string(from: value)
        }
        func appendRow(_ row: Row) {
            let task = row.task, fields = options.content, fact = report.facts[task.id]
            let styles = options.contentStyles
            let order = options.contentOrder.isEmpty ? SummaryContentField.inlineOrder : options.contentOrder
            var prefix: String?
            var parts: [(text: String, link: UUID?)] = []
            func add(_ text: String, link: UUID? = nil) { parts.append((text, link)) }
            if fields.contains(.completedTime) {
                let stamp = task.status == .completed ? task.completedAt
                    : (task.isAbandoned ? task.abandonedAt : nil)
                if let stamp {
                    prefix = "[" + date(stamp, time: styles.completedTime == .dateTime) + "]"
                }
            }
            for field in order where fields.contains(field) {
                switch field {
                case .taskName:
                    add(task.title, link: task.id)
                case .status:
                    if let status = fact?.status { add(status.rawValue) }
                case .progress:
                    if let fact, fact.totalSteps > 0 {
                        add("进度 \(fact.completedSteps)/\(fact.totalSteps)")
                    }
                case .taskTime:
                    if let due = task.schedule.dueAt {
                        let time = styles.taskTime == .dateTime && task.schedule.hasTime
                        var schedule = date(due, time: time)
                        if let end = task.schedule.dueEndAt {
                            schedule += "–" + date(end, time: time)
                        }
                        add("任务时间 " + schedule)
                    } else {
                        add("未安排日期")
                    }
                case .parentTask:
                    if let parent = task.parentID.flatMap({ report.tasksByID[$0] }) {
                        add("主任务：" + parent.title, link: parent.id)
                    }
                case .tags:
                    if !task.tags.isEmpty {
                        add(task.tags.map { "#" + $0 }.joined(separator: " "))
                    }
                case .focus:
                    if let fact {
                        add("专注 \(fact.focusSeconds / 60)分\(fact.focusSeconds % 60)秒 / \(fact.pomodoros)个番茄")
                    }
                case .list:
                    let folder = report.listFolders[task.list.name]?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if styles.list == .listGroup, let folder, !folder.isEmpty {
                        add("（\(task.list.name) / \(folder)）")
                    } else {
                        add("（\(task.list.name)）")
                    }
                case .completedTime, .detail:
                    break
                }
            }
            if !row.suffix.isEmpty { add(row.suffix) }
            let hasHeader = prefix != nil || !parts.isEmpty
            if hasHeader {
                var runs: [DocumentRun] = []
                if let prefix { runs.append(DocumentRun(text: parts.isEmpty ? prefix : prefix + " ")) }
                for (index, part) in parts.enumerated() {
                    if index > 0 { runs.append(DocumentRun(text: " · ")) }
                    runs.append(DocumentRun(text: part.text,
                        marks: part.link.map { [.link(NativeResourceLink.task($0).url.absoluteString)] } ?? []))
                }
                // Keep the source reachable when its name is hidden.
                if !fields.contains(.taskName), !runs.isEmpty {
                    runs[0].marks.insert(.link(NativeResourceLink.task(task.id).url.absoluteString))
                }
                blocks.append(DocumentBlock(kind: .bullet, runs: runs))
            }
            if fields.contains(.detail) {
                let detailBlocks: [DocumentBlock]
                switch styles.detail {
                case .formatted:
                    detailBlocks = task.document.blocks
                        .filter { !$0.plainText.isEmpty || $0.runs.contains(where: { $0.attachment != nil }) }
                        .map { DocumentBlock(kind: .quote, runs: $0.runs) }
                case .plain:
                    detailBlocks = task.document.blocks.compactMap { block in
                        let text = block.plainText
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        return DocumentBlock(kind: .quote, runs: [DocumentRun(text: text)])
                    }
                }
                let hasDetailContent = styles.detail == .plain ? !detailBlocks.isEmpty : !task.document.isEmpty
                if !hasHeader && hasDetailContent {
                    blocks.append(DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "任务详情",
                        marks: [.link(NativeResourceLink.task(task.id).url.absoluteString)])]))
                }
                blocks += detailBlocks
            }
        }
        var rows = report.completed.map { Row(task: $0) }
        let progressIDs = Set(report.progress.map(\.id))
        let movedIDs = Set(report.carried.map(\.id))
        rows += report.progress.flatMap { progress in
            progress.completedChildren.filter { report.filteredTaskIDs.contains($0.id) }.map { Row(task: $0) }
        }
        rows += report.progress.map { Row(task: $0.task) }
        rows += report.pending.filter { !progressIDs.contains($0.id) && !movedIDs.contains($0.id) }
            .map { Row(task: $0) }
        rows += report.abandoned.map { Row(task: $0) }
        rows += report.carried.map { move in
            let range = SummaryStore.date(fromDayKey: move.destinationWeek, calendar: calendar)
                .map { SummaryReviewBuilder.weekTitle(for: $0, calendar: calendar) } ?? move.destinationWeek
            return Row(task: move.task, suffix: "已结转到 " + range)
        }
        var seen = Set<UUID>()
        rows = rows.filter { seen.insert($0.task.id).inserted }

        var sections: [(String, [Row])] = []
        if options.grouping == .completion {
            var buckets: [String: [Row]] = [:]
            for row in rows {
                let key: String
                switch report.facts[row.task.id]?.status {
                case .completed: key = "已完成"
                case .abandoned: key = "已放弃"
                case .inProgress, .uncompleted, .all, .none: key = "未完成"
                }
                buckets[key, default: []].append(row)
            }
            sections = ["已完成", "已放弃", "未完成"].compactMap { key in
                buckets[key].map { (key, $0) }
            }
        } else {
            var buckets: [String: [Row]] = [:]
            for row in rows {
                let task = row.task
                let keys: [String]
                switch options.grouping {
                case .completion: keys = []
                case .list: keys = [task.list.name]
                case .priority: keys = [task.priority.title]
                case .tag: keys = task.tags.isEmpty ? ["无标签"] : task.tags
                case .completedTime: keys = [task.status == .completed ? task.completedAt.map { date($0) } ?? "无完成时间" : "无完成时间"]
                case .taskTime: keys = [task.schedule.dueAt.map { date($0) } ?? "无任务时间"]
                case .assignee: keys = ["未指派"]
                }
                for key in keys { buckets[key, default: []].append(row) }
            }
            let keys: [String]
            if options.grouping == .priority {
                keys = TaskPriority.menuOrder.map(\.title).filter { buckets[$0] != nil }
            } else if options.grouping == .completedTime || options.grouping == .taskTime {
                keys = buckets.keys.sorted { first, second in
                    func anchor(_ key: String) -> Date {
                        let values = buckets[key] ?? []
                        return values.compactMap { options.grouping == .completedTime ? $0.task.completedAt : $0.task.schedule.dueAt }.min() ?? .distantFuture
                    }
                    return anchor(first) < anchor(second)
                }
            } else { keys = buckets.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
            sections = keys.map { ($0, buckets[$0] ?? []) }
        }

        if options.content.isEmpty {
            paragraph("未选择显示内容，请在“显示内容”中勾选需要的项目。")
        } else {
            for section in sections {
                heading(section.0)
                section.1.forEach(appendRow)
            }
        }
        let reflection = Self.reflection(in: existing)
        if !reflection.isEmpty {
            heading(reviewTitle)
            blocks += reflection
        }
        if options.includesNextWeek {
            heading(nextTitle)
            if report.nextWeek.isEmpty {
                paragraph("下一周期暂无任务")
            } else if options.content.isEmpty {
                paragraph("未选择显示内容")
            } else {
                report.nextWeek.map { Row(task: $0) }.forEach(appendRow)
            }
        }
        if blocks.count == 1 {
            paragraph("当前范围内没有符合条件的任务")
        }
        return NativeDocument(blocks: blocks)
    }

    static func reflection(in document: NativeDocument?) -> [DocumentBlock] {
        guard let document, !document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if document.blocks.count == 2, document.blocks.first?.kind == .heading(1),
           document.blocks.last?.plainText == "当前范围内没有符合条件的任务" { return [] }
        if let index = document.blocks.firstIndex(where: { $0.kind == .heading(2) && ["本周复盘", "本期复盘"].contains($0.plainText) }) {
            return Array(document.blocks.dropFirst(index + 1).prefix { $0.kind != .heading(2) })
        }
        // A generated summary has its own section headings; don't re-append it
        // wholesale as "原有记录" on every refresh. Purely hand-written
        // documents still ride along so nothing written by the user is lost.
        let generated: Set<String> = ["已完成", "已放弃", "未完成", "本周成果", "本期成果",
                                      "进展与调整", "下周重点", "下一周期任务"]
        let hasGeneratedSections = document.blocks.contains { block in
            if case .heading(let level) = block.kind, level >= 2 { return generated.contains(block.plainText) }
            return false
        }
        guard !hasGeneratedSections else { return [] }
        return [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "原有记录：")])] + document.blocks
    }

    static func aiDocument(text: String, title: String) -> NativeDocument {
        let knownSections: Set<String> = ["已完成", "已放弃", "未完成", "本周成果", "本期成果",
                                          "进展与调整", "本周复盘", "本期复盘", "下周重点", "下一周期任务"]
        var blocks = [DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: title)])]
        func appendHeading(_ text: String, level: Int) {
            guard text != title else { return }
            let clamped = min(max(level, 2), 3)
            blocks.append(DocumentBlock(kind: .heading(clamped), runs: [DocumentRun(text: text)]))
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let depth = line.prefix { $0 == "#" }.count
                let text = String(line.dropFirst(depth)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { appendHeading(text, level: depth) }
                continue
            }
            let candidate = line.trimmingCharacters(in: CharacterSet(charactersIn: "* ").union(.whitespaces))
            guard !candidate.isEmpty, candidate != title else { continue }
            if knownSections.contains(candidate) {
                appendHeading(candidate, level: 2)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { blocks.append(DocumentBlock(kind: .bullet, runs: [DocumentRun(text: item)])) }
            } else {
                blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: line)]))
            }
        }
        return NativeDocument(blocks: blocks)
    }
}
