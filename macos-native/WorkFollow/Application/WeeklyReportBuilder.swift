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
    /// 滴答摘要的取样结果：计划在本期，或完成时间在本期。
    let summaryTaskIDs: Set<UUID>
    let listFolders: [String: String]
    let listMetas: [String: TaskListMeta]
    let tagColors: [String: UInt32]
}

struct WeeklyReportBuilder {
    let calendar: Calendar

    func report(tasks: [Task], weekOf: Date, listName: String? = nil,
                filter: SummaryFilter = .all, tagDirectory: [TaskTag] = [],
                focusRecords: [PomodoroRecord] = [], range selectedRange: SummaryDateRange? = nil,
                listNames: Set<String> = [],
                listFolders: [String: String] = [:], listMetas: [TaskListMeta] = []) -> WeeklyReport {
        let range = selectedRange ?? .week(containing: weekOf, calendar: calendar)
        let start = range.start
        let projection = WeeklyPlanProjection(weekStart: start, calendar: calendar)
        let scopeList = listName ?? filter.listName
        let scopeLists = listNames.isEmpty ? scopeList.map { Set([$0]) } ?? [] : listNames
        let matchingTags = filter.tagName.map { TaskTagHierarchy(tagDirectory).names(includingDescendantsOf: $0) }
        let available = tasks.filter { $0.deletedAt == nil && $0.skippedAt == nil && !$0.isConverted }
        let facts = SummaryTaskFacts.index(tasks: available, focusRecords: focusRecords, range: range)
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
        func movedOut(_ task: Task) -> Bool {
            guard range.kind == .week, !task.isClosed,
                  let current = task.weeklyPlanning?.currentWeek else { return false }
            return current != projection.weekKey
        }
        // 滴答按「计划日期或完成时间在本期」取样；已移出本周的开放任务留给下一期。
        let summaryTasks = valid.filter { task in
            guard !movedOut(task) else { return false }
            if task.status == .completed {
                return includes(task, in: range) || task.completedAt.map(range.contains) == true
            }
            return includes(task, in: range)
        }
        let summaryIDs = Set(summaryTasks.map(\.id))
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
            summaryTaskIDs: summaryIDs, listFolders: listFolders,
            listMetas: Dictionary(listMetas.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }),
            tagColors: Dictionary(tagDirectory.compactMap { tag in tag.colorARGB.map { (tag.name, $0) } },
                uniquingKeysWith: { first, _ in first }))
    }

    func document(for report: WeeklyReport, options: SummaryDocumentOptions = .standard,
                  now: Date = Date()) -> NativeDocument {
        struct Row { let task: Task; var indent = 0 }
        let isWeek = report.range.kind == .week
        let nextTitle = isWeek ? "下周重点" : "下一周期任务"
        var blocks = [DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: report.title)])]
        func heading(_ text: String, level: Int = 2) {
            if level == 2, !blocks.isEmpty { paragraph("") }
            blocks.append(DocumentBlock(kind: .heading(level), runs: [DocumentRun(text: text)]))
        }
        func paragraph(_ text: String) { blocks.append(DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: text)])) }
        func date(_ value: Date, time: Bool = false) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = time ? "M月d日 HH:mm" : "M月d日"
            return formatter.string(from: value)
        }
        func progressPercent(_ fact: SummaryTaskFacts?) -> Int {
            guard let fact, fact.totalSteps > 0 else { return 0 }
            return Int((Double(fact.completedSteps) / Double(fact.totalSteps) * 100).rounded())
        }
        func scheduleDate(_ task: Task) -> Date? {
            task.schedule.dueAt ?? task.schedule.dueEndAt
        }
        func durationText(_ seconds: Int) -> String {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if hours > 0 && minutes > 0 { return "\(hours)h\(minutes)m" }
            if hours > 0 { return "\(hours)h" }
            return "\(minutes)m"
        }
        func focusText(_ fact: SummaryTaskFacts) -> String {
            if fact.pomodoros > 0 {
                return fact.focusSeconds > 0
                    ? "\(durationText(fact.focusSeconds))/\(fact.pomodoros)番茄"
                    : "\(fact.pomodoros)番茄"
            }
            if fact.focusSeconds > 120 { return durationText(fact.focusSeconds) }
            return ""
        }
        func comesBefore(_ lhs: Task, _ rhs: Task, status: SummaryFilter.Status) -> Bool {
            switch status {
            case .completed:
                let left = lhs.completedAt ?? .distantPast
                let right = rhs.completedAt ?? .distantPast
                if left != right { return left > right }
            case .inProgress:
                let left = progressPercent(report.facts[lhs.id])
                let right = progressPercent(report.facts[rhs.id])
                if left != right { return left > right }
            case .abandoned, .uncompleted:
                let left = scheduleDate(lhs)
                let right = scheduleDate(rhs)
                switch (left, right) {
                case (nil, nil): break
                case (nil, _): return false
                case (_, nil): return true
                case let (left?, right?) where left != right: return left < right
                default: break
                }
            case .all:
                break
            }
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            if lhs.list.name != rhs.list.name {
                return lhs.list.name.localizedStandardCompare(rhs.list.name) == .orderedAscending
            }
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        func sortedTasks(_ tasks: [Task], status: SummaryFilter.Status) -> [Task] {
            tasks.sorted { comesBefore($0, $1, status: status) }
        }
        func appendRow(_ row: Row) {
            let task = row.task, fields = options.content, fact = report.facts[task.id]
            let styles = options.contentStyles
            let order = options.contentOrder.isEmpty ? SummaryContentField.inlineOrder : options.contentOrder
            let annotation: Set<DocumentMark> = [.caption, .muted]
            var metadata: [DocumentRun] = []
            func add(_ symbol: DocumentInlineSymbol, _ text: String, link: UUID? = nil,
                     ink: DocumentInk? = nil, icon: String? = nil, spacing: String = " ") {
                guard !text.isEmpty else { return }
                if !metadata.isEmpty { metadata.append(DocumentRun(text: "   ·   ", marks: annotation)) }
                let marks = annotation.union(ink.map { [.ink($0)] } ?? [])
                metadata.append(DocumentRun(text: icon ?? symbol.textFallback,
                    marks: icon == nil ? marks.union([.symbol(symbol)]) : marks))
                let links: Set<DocumentMark> = link.map { [.link(NativeResourceLink.task($0).url.absoluteString)] } ?? []
                metadata.append(DocumentRun(text: spacing + text, marks: marks.union(links)))
            }
            func status() {
                switch fact?.status ?? (task.status == .completed ? .completed : task.isAbandoned ? .abandoned : .uncompleted) {
                case .completed: add(.completed, "已完成")
                case .inProgress: add(.inProgress, "进行中")
                case .abandoned: add(.abandoned, "已放弃")
                case .uncompleted, .all: add(.pending, "未完成")
                }
            }
            var prefix = ""
            if fields.contains(.completedTime), task.status == .completed,
               options.grouping != .completedTime, let stamp = task.completedAt {
                prefix = "[\(date(stamp, time: styles.completedTime == .dateTime && task.schedule.hasTime))] "
            }
            if fields.contains(.progress), fact?.status == .inProgress {
                let percent = progressPercent(fact)
                if percent > 0 { prefix += "\(percent)% " }
            }
            for field in order where fields.contains(field) {
                switch field {
                case .taskName, .progress: break
                case .status:
                    if options.grouping != .completion { status() }
                case .taskTime:
                    guard options.grouping != .taskTime, let due = task.schedule.dueAt else { break }
                    let time = styles.taskTime == .dateTime && task.schedule.hasTime
                    var schedule = date(due, time: time)
                    if let end = task.schedule.dueEndAt { schedule += "–" + date(end, time: time) }
                    let delay = TaskInspectorSchedulePresentation.overdueDescription(
                        schedule: task.schedule, isClosed: task.isClosed, now: now, calendar: calendar)
                    if let delay { schedule += "，" + delay }
                    add(.calendar, schedule, ink: task.isClosed ? nil : delay == nil ? .accent : .danger)
                case .parentTask:
                    if let parent = task.parentID.flatMap({ report.tasksByID[$0] }) { add(.parent, parent.title, link: parent.id) }
                case .tags:
                    guard let first = task.tags.first else { break }
                    add(.tag, first, spacing: "")
                    if let color = report.tagColors[first] { metadata[metadata.count - 1].marks.insert(.ink(.argb(color))) }
                    for tag in task.tags.dropFirst() {
                        metadata.append(DocumentRun(text: "、", marks: annotation))
                        metadata.append(DocumentRun(text: tag,
                            marks: annotation.union(report.tagColors[tag].map { [.ink(.argb($0))] } ?? [])))
                    }
                case .focus:
                    if let fact { add(.focus, focusText(fact)) }
                case .list:
                    guard options.grouping != .list else { break }
                    let folder = report.listFolders[task.list.name]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = styles.list == .listGroup && folder?.isEmpty == false
                        ? folder! + " / " + task.list.name : task.list.name
                    let meta = report.listMetas[task.list.name]
                    add(task.list == .inbox ? .inbox : .list, name,
                        ink: task.list == .inbox ? nil : .argb(WFListPalette.argb(for: task.list.name, meta: meta)),
                        icon: meta?.icon?.isEmpty == false ? meta?.icon : nil)
                case .completedTime, .detail: break
                }
            }
            let showsTitle = fields.contains(.taskName)
            if metadata.isEmpty, !showsTitle, fields.contains(.status) { status() }
            var runs: [DocumentRun] = []
            if !prefix.isEmpty { runs.append(DocumentRun(text: prefix)) }
            if showsTitle {
                runs.append(DocumentRun(text: task.title.isEmpty ? "无标题" : task.title))
            }
            if !metadata.isEmpty {
                if !runs.isEmpty { runs.append(DocumentRun(text: "   ·   ", marks: annotation)) }
                runs += metadata
            }
            let hasHeader = !runs.isEmpty
            if !runs.isEmpty {
                if !showsTitle {
                    runs[0].marks.insert(.link(NativeResourceLink.task(task.id).url.absoluteString))
                }
                blocks.append(DocumentBlock(kind: .bullet, runs: runs, indentLevel: row.indent))
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

        let qualifiedTasks = report.summaryTaskIDs.compactMap { report.tasksByID[$0] }
        func nestedRows(_ sorted: [Task]) -> [Row] {
            let ids = Set(sorted.map(\.id))
            let children = Dictionary(grouping: sorted.filter { $0.parentID != nil }, by: { $0.parentID! })
            var rows: [Row] = []
            var visited = Set<UUID>()
            func append(_ task: Task, indent: Int) {
                guard visited.insert(task.id).inserted else { return }
                rows.append(Row(task: task, indent: min(indent, 8)))
                for child in children[task.id] ?? [] where !visited.contains(child.id) {
                    append(child, indent: indent + 1)
                }
            }
            for task in sorted where task.parentID.map { !ids.contains($0) } ?? true {
                append(task, indent: 0)
            }
            for task in sorted where !visited.contains(task.id) {
                append(task, indent: 0)
            }
            return rows
        }

        let sectionStatuses: [(SummaryFilter.Status, String)] = [
            (.completed, "已完成"), (.abandoned, "已放弃"),
            (.inProgress, "进行中"), (.uncompleted, "未完成"),
        ]
        var sections: [(String, [Row])] = []
        if options.grouping == .completion {
            for (status, title) in sectionStatuses {
                let tasks = sortedTasks(qualifiedTasks.filter { report.facts[$0.id]?.status == status }, status: status)
                guard !tasks.isEmpty else { continue }
                let rows = status == .completed || status == .abandoned
                    ? nestedRows(tasks) : tasks.map { Row(task: $0) }
                sections.append((title, rows))
            }
        } else {
            let ordered = sectionStatuses.flatMap { status, _ in
                sortedTasks(qualifiedTasks.filter { report.facts[$0.id]?.status == status }, status: status)
                    .map { Row(task: $0) }
            }
            var buckets: [String: [Row]] = [:]
            for row in ordered {
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
                for row in section.1 { appendRow(row) }
            }
        }

        if options.includesNextWeek {
            heading(nextTitle)
            if report.nextWeek.isEmpty {
                paragraph("下一周期暂无任务")
            } else if options.content.isEmpty {
                paragraph("未选择显示内容")
            } else {
                var wroteSection = false
                let nextStatuses: [(SummaryFilter.Status, String)] = [
                    (.inProgress, "进行中"), (.uncompleted, "未完成"),
                ]
                for (status, title) in nextStatuses {
                    let tasks = sortedTasks(report.nextWeek.filter { report.facts[$0.id]?.status == status }, status: status)
                    guard !tasks.isEmpty else { continue }
                    heading(title, level: 3)
                    tasks.forEach { appendRow(Row(task: $0)) }
                    wroteSection = true
                }
                if !wroteSection { paragraph("下一周期暂无任务") }
            }
        }
        if blocks.count == 1 {
            paragraph("当前范围内没有符合条件的任务")
        }
        return NativeDocument(blocks: blocks)
    }

    static func aiDocument(text: String, title: String) -> NativeDocument {
        let knownSections: Set<String> = ["已完成", "已放弃", "进行中", "未完成", "本周成果", "本期成果",
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
