import SwiftUI

/// 按日期、类型、来源与任务筛选；统计来自完整记录集，不依赖分页窗口。
struct FocusStatisticsPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    @Environment(\.colorScheme) private var scheme
    @State private var period = 7
    @State private var mode: FocusMode?
    @State private var source: FocusRecordSource?
    @State private var associated = 0
    @State private var taskID: UUID?
    @State private var loadedRecords: [PomodoroRecord] = []
    private var theme: FocusTheme { FocusTheme(scheme) }
    private var filtered: [PomodoroRecord] {
        loadedRecords.filter {
            (mode == nil || $0.mode == mode) && (source == nil || $0.source == source)
                && (taskID == nil || $0.taskID == taskID)
                && (associated == 0 || (associated == 1 ? $0.taskID != nil : $0.taskID == nil))
        }
    }
    private var totalSeconds: Int { filtered.reduce(0) { $0 + $1.activeSeconds } }
    private var totalPomodoros: Int { filtered.reduce(0) { $0 + $1.creditedPomodoros } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("专注统计").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button("返回概览") { store.showOverview() }.buttonStyle(.plain)
                }
                HStack {
                    Picker("日期", selection: $period) {
                        Text("最近 7 天").tag(7); Text("最近 30 天").tag(30); Text("全部").tag(0)
                    }
                    Picker("类型", selection: $mode) {
                        Text("全部类型").tag(Optional<FocusMode>.none)
                        ForEach(FocusMode.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                }
                HStack {
                    Picker("来源", selection: $source) {
                        Text("全部来源").tag(Optional<FocusRecordSource>.none)
                        Text("计时").tag(Optional(FocusRecordSource.timer))
                        Text("补记").tag(Optional(FocusRecordSource.manual))
                        Text("历史记录").tag(Optional(FocusRecordSource.legacy))
                    }
                    Picker("任务", selection: $taskID) {
                        Text("全部任务").tag(Optional<UUID>.none)
                        ForEach(workspace?.allTasks.filter { $0.deletedAt == nil } ?? []) { task in
                            Text(task.title.isEmpty ? "未命名任务" : task.title).tag(Optional(task.id))
                        }
                    }
                }
                Picker("关联", selection: $associated) {
                    Text("全部关联状态").tag(0); Text("已关联任务").tag(1); Text("未关联任务").tag(2)
                }.frame(maxWidth: 220)
                HStack(spacing: 36) {
                    statistic("专注时长", value: "\(totalSeconds / 60) 分")
                    statistic("番茄", value: "\(totalPomodoros)")
                    statistic("记录", value: "\(filtered.count)")
                }
                Divider()
                Text("每日投入").font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(dayTotals, id: \.day) { day in
                        HStack(spacing: 12) {
                            Text(FocusViewLogic.dayLabel(for: day.day, now: store.currentTime, calendar: store.presentationCalendar))
                                .font(.caption).foregroundStyle(theme.text2).frame(width: 64, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(theme.accent.opacity(0.7))
                                    .frame(width: max(2, geo.size.width * Double(day.seconds) / Double(maxDaySeconds)))
                            }.frame(height: 10)
                            Text("\(day.seconds / 60) 分").font(.caption).monospacedDigit().frame(width: 70, alignment: .trailing)
                        }
                    }
                }
                Divider()
                Text("任务分布").font(.headline)
                ForEach(Array(taskTotals.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.taskID.flatMap { workspace?.task(for: $0)?.title } ?? "未关联任务")
                        Spacer(); Text("\(item.seconds / 60) 分").monospacedDigit().foregroundStyle(theme.text2)
                    }
                }
                Button("查看这些记录") {
                    var filter = FocusRecordFilter(taskID: taskID, mode: mode, source: source)
                    if period > 0 { filter.from = cutoff }
                    filter.associated = associated == 0 ? nil : associated == 1
                    store.showRecords(taskID: taskID); store.setRecordFilter(filter)
                }.buttonStyle(.plain).foregroundStyle(theme.accent)
            }.padding(FocusLayoutMetrics.overviewHorizontalPadding)
        }
        .background(theme.canvas).focusRenderAnchor(.statistics)
        .onAppear { reload() }
        .onChange(of: period) { _, _ in reload() }
        .onChange(of: store.historyRevision) { _, _ in reload() }
    }
    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(theme.text2)
            Text(value).font(.system(size: 28, weight: .light)).monospacedDigit()
        }
    }
    private var cutoff: Date {
        store.presentationCalendar.date(byAdding: .day, value: -(max(1, period) - 1),
            to: store.presentationCalendar.startOfDay(for: store.currentTime)) ?? store.currentTime
    }
    private func reload() {
        loadedRecords = store.filteredRecords(FocusRecordFilter(from: period == 0 ? nil : cutoff))
    }
    private var dayTotals: [(day: Date, seconds: Int)] {
        Dictionary(grouping: filtered, by: { store.presentationCalendar.startOfDay(for: $0.startedAt) })
            .map { (day: $0.key, seconds: $0.value.reduce(0) { $0 + $1.activeSeconds }) }.sorted { $0.day < $1.day }
    }
    private var maxDaySeconds: Int { max(1, dayTotals.map(\.seconds).max() ?? 1) }
    private var taskTotals: [(taskID: UUID?, seconds: Int)] {
        Dictionary(grouping: filtered, by: \.taskID)
            .map { (taskID: $0.key, seconds: $0.value.reduce(0) { $0 + $1.activeSeconds }) }.sorted { $0.seconds > $1.seconds }
    }
}
