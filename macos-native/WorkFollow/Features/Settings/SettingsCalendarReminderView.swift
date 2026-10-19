import SwiftUI
import UserNotifications
import EventKit
import ServiceManagement

struct SettingsCalendarReminderView: View {
    @ObservedObject var reminders: NativeReminderService
    @ObservedObject var integration: CalendarSyncCoordinator
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var pendingList: String?
    @State private var calendarName = "WorkFollow"
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("任务提醒") {
                HStack {
                    Text(notificationStatus)
                    Spacer()
                    Button("允许通知") { reminders.enable(for: workspace.tasksInActiveLists) }
                }
                Toggle("提醒声音", isOn: Binding(get: { reminders.state.snapshot.preferences.soundEnabled },
                    set: { flag in reminders.state.updatePreferences { $0.soundEnabled = flag } }))
                Picker("铃声", selection: Binding(get: { reminders.state.snapshot.preferences.bell },
                    set: { name in reminders.state.updatePreferences { $0.bell = name } })) {
                    Text("清脆").tag("Glass")
                    Text("轻响").tag("Ping")
                    Text("和弦").tag("Hero")
                    Text("低鸣").tag("Submarine")
                }
                Picker("默认稍后提醒", selection: Binding(get: { reminders.state.snapshot.preferences.snoozeMinutes },
                    set: { minutes in reminders.state.updatePreferences { $0.snoozeMinutes = minutes } })) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                }
                HStack {
                    Button("试听铃声") { reminders.previewSound() }
                    Button("5 秒后测试提醒") { reminders.sendTest() }
                        .disabled(reminders.authorization != .authorized && reminders.authorization != .provisional)
                }
                if let end = reminders.coverageEnd {
                    Text("已安排 \(reminders.pendingCount) 条提醒，最晚至 \(end.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("应用运行时可停止铃声；完全退出后使用系统短铃。稍后提醒不会改变任务日期。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("登录时启动 WorkFollow", isOn: Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginStatus = SMAppService.mainApp.status; loginError = nil
                    } catch { loginError = error.localizedDescription; loginStatus = SMAppService.mainApp.status }
                }))
                if loginStatus == .requiresApproval {
                    Button("在系统设置中允许登录启动") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
                if let message = reminders.message { Text(message).foregroundStyle(.red) }
                if !reminders.missed.isEmpty {
                    Text("最近 24 小时错过的提醒").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(reminders.missed.suffix(10))) { item in
                        HStack {
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Button("打开") { reminders.openReminder(item) }
                            Button("稍后提醒") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: reminders.state.snapshot.preferences.snoozeMinutes) } }
                            Button("停止") { _Concurrency.Task { await reminders.handle(item, snoozeMinutes: nil) } }
                        }
                    }
                }
            }
            Section("Apple 日历") {
                HStack {
                    Text(integration.authorization == .fullAccess ? "已允许完整访问" : "尚未连接")
                    Spacer()
                    Button("连接日历") { _Concurrency.Task { await integration.connect() } }
                }
                if integration.authorization == .fullAccess {
                    Toggle("启用日历连接", isOn: Binding(get: { integration.store.snapshot.enabled },
                        set: { flag in integration.store.configure { $0.enabled = flag } }))
                    Picker("任务写入日历", selection: Binding(get: { integration.store.snapshot.targetCalendarID ?? "" },
                        set: { id in integration.store.configure { $0.targetCalendarID = id.isEmpty ? nil : id } })) {
                        Text("请选择").tag("")
                        ForEach(integration.calendars.filter(\.writable)) { Text($0.title).tag($0.id) }
                    }
                    TextField("新日历名称", text: $calendarName)
                    Button("新建日历") { integration.createDedicatedCalendar(title: calendarName) }
                        .disabled(calendarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("测试日历连接") { integration.testConnection() }
                        .help("创建、更新并移除一条临时日程")
                    if let result = integration.connectionTestResult { Text(result).font(.caption) }
                    Picker("单点任务显示时长", selection: Binding(get: { integration.store.snapshot.defaultDurationMinutes },
                        set: { minutes in integration.store.configure { $0.defaultDurationMinutes = minutes } })) {
                        ForEach([15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }
                    Text("自动同步这些清单中的排期任务") .font(.caption).foregroundStyle(.secondary)
                    ForEach(workspace.availableListNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(get: { integration.store.snapshot.autoSyncLists.contains(name) }, set: { flag in
                            if flag { pendingList = name }
                            else { integration.store.configure { $0.autoSyncLists.removeAll { $0 == name } } }
                        }))
                    }
                    Text("在本项目中显示的系统日历").font(.caption).foregroundStyle(.secondary)
                    ForEach(integration.calendars) { item in
                        Toggle(item.title, isOn: Binding(get: { integration.store.snapshot.visibleCalendarIDs.contains(item.id) }, set: { flag in
                            integration.store.configure { value in
                                value.visibleCalendarIDs.removeAll { $0 == item.id }
                                if flag { value.visibleCalendarIDs.append(item.id) }
                            }
                        }))
                    }
                    Toggle("允许日历修改关联任务的标题和时间", isOn: Binding(get: { integration.store.snapshot.bidirectional },
                        set: { flag in integration.store.configure { $0.bidirectional = flag } }))
                    Button(integration.syncing ? "正在同步…" : "重新同步") { integration.onNeedsSync?() }
                        .disabled(integration.syncing)
                    Text("默认由 WorkFollow 提醒，日历副本不添加警报。重复任务同步未来 90 天，应用运行时自动补齐。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let message = integration.message { Text(message).foregroundStyle(.red) }
            }
            if !integration.conflicts.isEmpty {
                Section("日历修改待处理") {
                    ForEach(integration.conflicts) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text("任务：" + description(item.task))
                            Text("日历：" + description(item.event))
                            HStack {
                                Button("采用日历修改") { integration.resolve(item, useCalendar: true) }
                                Button("保留任务内容") { integration.resolve(item, useCalendar: false) }
                            }
                        }.font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { integration.refreshAccess(); reminders.reconcile(workspace.tasksInActiveLists, force: true) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginStatus = SMAppService.mainApp.status }
        .confirmationDialog("同步清单中的排期任务", isPresented: Binding(get: { pendingList != nil },
            set: { if !$0 { pendingList = nil } }), titleVisibility: .visible) {
            if let name = pendingList {
                Button("开始同步") {
                    integration.store.configure { $0.autoSyncLists.append(name) }; pendingList = nil
                }
                Button("取消", role: .cancel) { pendingList = nil }
            }
        } message: {
            if let name = pendingList {
                let count = workspace.allTasks.filter { $0.list.name == name && $0.schedule.dueAt != nil && $0.deletedAt == nil && $0.parentID == nil }.count
                Text("「\(name)」目前有 \(count) 个已排期任务；重复任务将同步未来 90 天的周期。")
            }
        }
    }
    private var notificationStatus: String {
        switch reminders.authorization {
        case .authorized, .provisional: "系统通知已开启"
        case .denied: "系统通知已关闭"
        default: "尚未允许系统通知"
        }
    }
    private func description(_ fields: CalendarEventFields) -> String {
        let format = Date.FormatStyle.dateTime.month().day().locale(.appDate)
        if fields.allDay {
            let last = fields.end.addingTimeInterval(-1)
            let high = Calendar.current.isDate(fields.start, inSameDayAs: last) ? "" : " 至 " + last.formatted(format)
            return fields.title + " · " + fields.start.formatted(format) + high + "（全天）"
        }
        return fields.title + " · " + fields.start.formatted(format.hour().minute()) + " 至 " + fields.end.formatted(format.hour().minute())
    }
}

struct TaskSystemCalendarRow: View {
    let task: Task
    @ObservedObject var integration: CalendarSyncCoordinator
    @ObservedObject var reminders: NativeReminderService
    let tasks: [Task]
    @State private var showUnlink = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if task.reminderAt != nil || !(task.reminderOffsets ?? []).isEmpty {
                if reminders.authorization != .authorized && reminders.authorization != .provisional {
                    Button("允许任务到点通知") { reminders.enable(for: tasks) }
                }
            }
            if integration.authorization == .fullAccess || integration.store.snapshot.enabled {
                Toggle("同步到 Apple 日历", isOn: Binding(get: { integration.store.snapshot.includes(task) }, set: { flag in
                    if flag { integration.store.setTask(task, enabled: true) } else { showUnlink = true }
                })).disabled(task.schedule.dueAt == nil || task.parentID != nil)
                if task.schedule.dueAt == nil {
                    Text("设置任务日期后即可同步").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(integration.status(for: task)).foregroundStyle(.secondary)
                        if integration.status(for: task).contains("重新关联") {
                            Button("重新关联") { integration.reconnect(task) }
                        }
                    }
                }
            }
        }.font(.caption)
        .confirmationDialog("取消任务与日历的关联", isPresented: $showUnlink, titleVisibility: .visible) {
            Button("移除未来日历副本") { integration.store.setTask(task, enabled: false) }
            Button("保留日历副本") { integration.unlinkKeepingEvents(task) }
            Button("取消", role: .cancel) {}
        }
    }
}
