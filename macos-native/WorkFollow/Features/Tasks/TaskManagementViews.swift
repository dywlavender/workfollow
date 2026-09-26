import SwiftUI
import AppKit

@MainActor
enum TaskNamePrompt {
    static func ask(_ title: String, value: String = "", confirm: String = "确定") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: confirm); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func confirm(_ title: String, message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    static func invalidName() {
        let alert = NSAlert(); alert.messageText = "名称为空或已存在"; alert.runModal()
    }
}

struct TaskCollectionsView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("清单").foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let value = TaskNamePrompt.ask("新建清单") {
                        if workspace.saveList(value) { openList(value) } else { TaskNamePrompt.invalidName() }
                    }
                } label: { Image(systemName: "plus") }.help("新建清单")
            }.padding(.top, 18)
            ForEach(workspace.listNames, id: \.self) { name in
                Button { openList(name) } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(name).lineLimit(1)
                        Spacer()
                        Text("\(workspace.allTasks.filter { $0.list.name == name && !$0.isClosed && $0.deletedAt == nil && $0.skippedAt == nil }.count)")
                            .foregroundStyle(.secondary)
                    }.padding(7).background(workspace.activeList == name ? WFColors.selection : .clear,
                                             in: RoundedRectangle(cornerRadius: 6))
                }.contextMenu {
                    Button("重命名") {
                        if let value = TaskNamePrompt.ask("重命名清单", value: name), !workspace.saveList(value, replacing: name) { TaskNamePrompt.invalidName() }
                    }
                    Button("删除清单…") {
                        if TaskNamePrompt.confirm("删除清单“\(name)”？", message: "任务（含子任务）将移到收集箱，不删除任务。可撤销。") { workspace.removeList(name) }
                    }
                }
                .dropDestination(for: String.self) { values, _ in
                    guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                    return workspace.moveToList(id, TaskList(name: name)).taskID != nil
                }
            }
            Text("标签").foregroundStyle(.secondary).padding(.top, 12)
            if workspace.tagNames.isEmpty { Text("在任务属性中添加标签").font(.caption).foregroundStyle(.tertiary) }
            ForEach(workspace.tagNames, id: \.self) { tag in
                Button("# " + tag) {
                    navigation.destination = .allTasks; workspace.activeList = nil; workspace.activeTag = tag; onNavigate()
                }.contextMenu {
                    Button("重命名标签") {
                        if let value = TaskNamePrompt.ask("重命名标签", value: tag), !value.isEmpty { workspace.renameTag(tag, to: value) }
                    }
                    Button("移除标签…") {
                        if TaskNamePrompt.confirm("移除标签“\(tag)”？", message: "从所有任务移除此标签，不删除任务。可撤销。") { workspace.renameTag(tag, to: nil) }
                    }
                }.padding(.vertical, 4)
            }
        }.buttonStyle(.plain).font(WFType.navigation)
    }
    private func openList(_ name: String) {
        navigation.destination = .allTasks; workspace.activeList = name; workspace.activeTag = nil
        workspace.select(nil); workspace.clearBulkSelection(); onNavigate()
    }
}

struct TaskComposer: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let onClose: (Bool) -> Void
    var dismissedTokenIDs: Set<String> = []
    let initialSchedule: QuickAddScheduleDraft?
    let initialProperties: QuickAddPropertiesOverrides
    @State var title: String
    @State var list: String
    @State var scheduled: Bool
    @State var date: Date
    @State private var hasTime: Bool
    @State private var priority: TaskPriority
    @State private var tags: String
    @State private var reminder: Bool
    @State private var reminderDate: Date
    @State private var frequency: TaskRepeat
    @State private var deadlineEnabled = false
    @State private var deadlineDate: Date
    @State private var repeatInterval: Int
    @State private var repeatEndEnabled: Bool
    @State private var repeatEndDate: Date
    @State private var repeatCountEnabled: Bool
    @State private var repeatCount: Int
    @State private var scheduleEdited: Bool
    @State private var reminderEdited: Bool
    @State private var frequencyEdited: Bool
    @State private var priorityEdited: Bool
    @State private var listEdited: Bool
    @State private var tagsEdited: Bool
    @FocusState private var titleFocused: Bool

    init(workspace: TaskWorkspaceModel, onClose: @escaping (Bool) -> Void,
         dismissedTokenIDs: Set<String> = [], title: String, list: String,
         scheduled: Bool, date: Date, initialSchedule: QuickAddScheduleDraft? = nil,
         initialProperties: QuickAddPropertiesOverrides = QuickAddPropertiesOverrides(
            priority: nil, listName: nil, tags: nil)) {
        let parsed = QuickAddParser.parse(title, now: workspace.clock(), calendar: workspace.calendar,
                                          availableLists: workspace.allListNames,
                                          dismissedTokenIDs: dismissedTokenIDs)
        self.workspace = workspace
        self.onClose = onClose
        self.dismissedTokenIDs = dismissedTokenIDs
        self.initialSchedule = initialSchedule
        self.initialProperties = initialProperties
        _title = State(initialValue: title)
        _list = State(initialValue: initialProperties.listName ?? parsed.listName ?? list)
        _scheduled = State(initialValue: initialSchedule.map { $0.dueAt != nil } ?? scheduled)
        _date = State(initialValue: initialSchedule?.dueAt ?? date)
        _hasTime = State(initialValue: initialSchedule?.hasTime ?? false)
        _priority = State(initialValue: initialProperties.priority ?? parsed.priority)
        _tags = State(initialValue: initialProperties.tags?.joined(separator: ",") ?? "")
        _reminder = State(initialValue: initialSchedule?.reminderAt != nil)
        _reminderDate = State(initialValue: initialSchedule?.reminderAt ?? workspace.clock().addingTimeInterval(3600))
        _frequency = State(initialValue: initialSchedule?.repeatFrequency ?? .never)
        _deadlineDate = State(initialValue: workspace.dateFromToday(0))
        _repeatInterval = State(initialValue: initialSchedule?.recurrenceRule?.interval ?? 1)
        _repeatEndEnabled = State(initialValue: initialSchedule?.recurrenceRule?.endDate != nil)
        _repeatEndDate = State(initialValue: initialSchedule?.recurrenceRule?.endDate ?? workspace.dateFromToday(30))
        _repeatCountEnabled = State(initialValue: initialSchedule?.recurrenceRule?.remainingCount != nil)
        _repeatCount = State(initialValue: initialSchedule?.recurrenceRule?.remainingCount ?? 10)
        _scheduleEdited = State(initialValue: initialSchedule != nil)
        _reminderEdited = State(initialValue: initialSchedule != nil)
        _frequencyEdited = State(initialValue: initialSchedule != nil)
        _priorityEdited = State(initialValue: initialProperties.priority != nil)
        _listEdited = State(initialValue: initialProperties.listName != nil)
        _tagsEdited = State(initialValue: initialProperties.tags != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建任务").font(.title2.bold())
            TextField("准备做什么？", text: $title).focused($titleFocused)
            Picker("清单", selection: $list) {
                ForEach(workspace.allListNames, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: list) { _, _ in listEdited = true }
            Toggle("安排日期", isOn: $scheduled)
                .onChange(of: scheduled) { _, _ in scheduleEdited = true }
            if scheduled {
                HStack {
                    Button("今天") { date = workspace.dateFromToday(0) }
                    Button("明天") { date = workspace.dateFromToday(1) }
                    Button("下周") { date = workspace.dateFromToday(7) }
                }
                DatePicker("日期", selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                Toggle("指定时间", isOn: $hasTime)
                    .onChange(of: hasTime) { _, _ in scheduleEdited = true }
            }
            Toggle("截止日期", isOn: $deadlineEnabled)
            if deadlineEnabled {
                DatePicker("截止", selection: $deadlineDate, displayedComponents: .date)
            }
            Picker("优先级", selection: $priority) {
                Text("无").tag(TaskPriority.none); Text("低").tag(TaskPriority.low)
                Text("中").tag(TaskPriority.medium); Text("高").tag(TaskPriority.high)
            }
            .onChange(of: priority) { _, _ in priorityEdited = true }
            TextField("标签（逗号分隔）", text: $tags)
                .onChange(of: tags) { _, _ in tagsEdited = true }
            Picker("重复", selection: $frequency) {
                ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .onChange(of: frequency) { _, _ in frequencyEdited = true }
            if frequency != .never {
                Stepper("间隔：\(repeatInterval)", value: $repeatInterval, in: 1...99)
                Toggle("设置结束日期", isOn: $repeatEndEnabled)
                if repeatEndEnabled {
                    DatePicker("重复至", selection: $repeatEndDate, displayedComponents: .date)
                }
                Toggle("限制次数", isOn: $repeatCountEnabled)
                if repeatCountEnabled {
                    Stepper("重复 \(repeatCount) 次（含本次）", value: $repeatCount, in: 1...999)
                }
            }
            Toggle("提醒", isOn: $reminder)
                .onChange(of: reminder) { _, _ in reminderEdited = true }
            if reminder { DatePicker("提醒时间", selection: $reminderDate) }
            HStack {
                Spacer()
                Button("取消") { onClose(false) }.keyboardShortcut(.cancelAction)
                Button("创建") {
                    let parsed = QuickAddParser.parse(title, now: workspace.clock(), calendar: workspace.calendar,
                                                     availableLists: workspace.allListNames,
                                                     dismissedTokenIDs: dismissedTokenIDs)
                    guard !parsed.title.isEmpty else { return }
                    let dueAt = scheduleEdited
                        ? (scheduled ? (hasTime ? date : workspace.calendar.startOfDay(for: date)) : nil)
                        : parsed.dueAt ?? (scheduled ? (hasTime ? date : workspace.calendar.startOfDay(for: date)) : nil)
                    let finalHasTime = scheduleEdited ? hasTime : parsed.dueAt != nil ? parsed.hasTime : hasTime
                    let finalFrequency = frequencyEdited ? frequency : parsed.recurrence
                    var rule = frequencyEdited
                        ? (frequency == initialSchedule?.repeatFrequency ? initialSchedule?.recurrenceRule : nil)
                        : parsed.recurrenceRule
                    if frequency != .never {
                        rule = rule ?? RecurrenceRule()
                        rule?.interval = repeatInterval
                        rule?.endDate = repeatEndEnabled ? workspace.calendar.startOfDay(for: repeatEndDate) : nil
                        rule?.remainingCount = repeatCountEnabled ? repeatCount : nil
                        if frequency == .weekly, rule?.weekday == nil { rule?.weekday = parsed.recurrenceRule?.weekday }
                        if frequency == .monthly, rule?.monthDay == nil { rule?.monthDay = parsed.recurrenceRule?.monthDay }
                    }
                    let parsedTags = tags.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",")
                    let enteredTags = tagsEdited || initialProperties.tags != nil
                        ? parsedTags : parsedTags + parsed.tags
                    let finalTags = (workspace.activeTag.map { [$0] } ?? []) + enteredTags
                    let finalList = listEdited ? list : parsed.listName ?? list
                    let finalPriority = priorityEdited ? priority : parsed.priority
                    let finalReminder = reminderEdited
                        ? (reminder ? reminderDate : nil)
                        : initialSchedule?.reminderAt ?? parsed.reminderAt
                    let result = workspace.createDraft(title: parsed.title,
                        list: finalList,
                        schedule: TaskSchedule(dueAt: dueAt, hasTime: finalHasTime,
                                               deadlineAt: deadlineEnabled ? workspace.calendar.startOfDay(for: deadlineDate) : nil),
                        priority: finalPriority, tags: finalTags,
                        reminder: finalReminder, repeatFrequency: finalFrequency,
                        recurrenceRule: rule)
                    if result.taskID != nil { onClose(true) }
                }.keyboardShortcut(.defaultAction).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
            .onAppear {
                titleFocused = true
                if initialSchedule?.reminderAt == nil { reminderDate = workspace.clock().addingTimeInterval(3600) }
            }
            .environment(\.calendar, workspace.calendar).environment(\.timeZone, workspace.calendar.timeZone)
    }
}

struct TaskBulkBar: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var date = Date()
    @State private var showDate = false
    var body: some View {
        HStack {
            Text("已选 \(workspace.bulkSelection.count)")
            Button("完成") { workspace.applyBulk(.complete) }
            Button("日期") { date = workspace.dateFromToday(0); showDate = true }
                .popover(isPresented: $showDate) {
                    VStack(spacing: 12) {
                        DatePicker("日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                        HStack {
                            Button("清除") { workspace.applyBulk(.schedule(TaskSchedule())); showDate = false }
                            Button("取消") { showDate = false }
                            Button("确定") { workspace.applyBulk(.schedule(TaskSchedule(dueAt: workspace.calendar.startOfDay(for: date)))); showDate = false }
                        }
                    }.padding(16)
                }
            Menu("移动") {
                ForEach(workspace.allListNames, id: \.self) { name in Button(name) { workspace.applyBulk(.move(name)) } }
            }
            Button("删除") { workspace.applyBulk(.delete) }
            Button { workspace.clearBulkSelection() } label: { Image(systemName: "xmark") }.help("取消选择")
        }.font(.caption).padding(10).background(WFColors.selection)
    }
}
