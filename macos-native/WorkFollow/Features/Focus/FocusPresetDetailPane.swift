import SwiftUI

/// 常用项详情的卡片、图表与记录来自同一次全库查询；浏览不改变当前计时。
struct FocusPresetDetailPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    let presetID: UUID
    let onSelectRecordTask: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var period: FocusPresetStatisticsPeriod = .week
    @State private var periodAnchor: Date?
    @State private var statistics: FocusPresetStatistics?
    @State private var editingPreset: FocusStore.TimerPreset?
    @State private var recordDraft: FocusRecordDraft?
    @State private var selectedRecord: PomodoroRecord?
    @State private var archivingPreset: FocusStore.TimerPreset?
    private var theme: FocusTheme { FocusTheme(scheme) }
    private var preset: FocusStore.TimerPreset? { store.timers.first { $0.id == presetID } }

    var body: some View {
        ScrollView {
            if let preset {
                VStack(alignment: .leading, spacing: 0) {
                    toolbar(preset)
                    title(preset).padding(.top, 16)
                    if let statistics {
                        statisticsCards(statistics).padding(.top, 28)
                        chartSection(statistics, preset: preset).padding(.top, 28)
                        recordsSection(statistics, preset: preset).padding(.top, 28)
                    }
                }
                .padding(.horizontal, FocusLayoutMetrics.presetDetailHorizontalPadding)
                .padding(.top, 20).padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.canvas)
        .focusRenderAnchor(.presetDetail)
        .onAppear { reload() }
        .onChange(of: presetID) { _, _ in periodAnchor = nil; reload() }
        .onChange(of: period) { _, _ in periodAnchor = nil; reload() }
        .onChange(of: periodAnchor) { _, _ in reload() }
        .onChange(of: store.historyRevision) { _, _ in reload() }
        .onChange(of: store.timers) { _, _ in reload() }
        .sheet(item: $editingPreset) { FocusPresetEditor(store: store, workspace: workspace, preset: $0) }
        .sheet(item: $recordDraft) { FocusRecordEditor(store: store, workspace: workspace, draft: $0) }
        .sheet(item: $selectedRecord) { record in
            FocusRecordDetail(store: store, recordID: record.id, workspace: workspace, onSelectTask: onSelectRecordTask)
        }
        .focusPresetArchiveConfirmation(store: store, preset: $archivingPreset)
    }

    private func toolbar(_ preset: FocusStore.TimerPreset) -> some View {
        HStack {
            Button("关闭") { store.closePresetDetails() }.buttonStyle(.plain).foregroundStyle(theme.accent)
                .accessibilityIdentifier("focus-preset-detail-close")
            Spacer()
            BusinessMenu {
                if preset.archivedAt == nil {
                    Button("编辑") { editingPreset = preset }
                    Button("添加记录") { addRecord(preset) }
                    Button("归档") { archivingPreset = preset }
                } else {
                    Button("恢复") { _ = store.restoreTimer(preset.id) }.disabled(store.activeTimers.count >= 12)
                }
                Button("删除", role: .destructive) { store.deleteTimer(preset.id) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 24, height: 28)
            }.fixedSize().foregroundStyle(theme.text2)
                .accessibilityIdentifier("focus-preset-detail-menu")
        }.font(.system(size: 13)).frame(height: 28)
    }

    private func title(_ preset: FocusStore.TimerPreset) -> some View {
        HStack(spacing: 12) {
            Text(preset.emoji).font(.system(size: 26)).frame(width: 40, height: 40)
                .background(theme.avatarBackground, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.text)
                Text(preset.stopwatch ? "正计时" : "番茄计时 \(preset.minutes)m")
                    .font(.system(size: 12)).foregroundStyle(theme.text3)
            }
            Spacer()
        }.frame(height: 44)
    }

    private func statisticsCards(_ statistics: FocusPresetStatistics) -> some View {
        HStack(spacing: 12) {
            card("专注天数", value: statistics.focusDays, unit: nil)
            card("今日时长", value: statistics.todayActiveSeconds / 60, unit: "m")
            card("总时长", value: statistics.totalActiveSeconds / 60, unit: "m")
        }.focusRenderAnchor(.presetDetailCards)
    }

    private func card(_ label: String, value: Int, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundStyle(theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)").font(.system(size: 24)).monospacedDigit().foregroundStyle(theme.text)
                if let unit { Text(unit).font(.system(size: 12)).foregroundStyle(theme.text) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
        .frame(height: FocusLayoutMetrics.presetDetailCardHeight)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 11))
    }

    private func chartSection(_ statistics: FocusPresetStatistics, preset: FocusStore.TimerPreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(statistics.periodActiveSeconds / 60)").font(.system(size: 24)).monospacedDigit()
                    Text("m").font(.system(size: 13))
                }.foregroundStyle(theme.text)
                Spacer()
                BusinessPicker("统计周期", selection: $period, options:
                    FocusPresetStatisticsPeriod.allCases.map { BusinessChoice($0, $0.title) }).labelsHidden().frame(width: 52)
                    .accessibilityIdentifier("focus-preset-detail-period")
            }.frame(height: 29)
            HStack(spacing: 6) {
                Button { movePeriod(-1) } label: { Image(systemName: "chevron.left").frame(width: 16, height: 18) }
                    .buttonStyle(.plain).accessibilityIdentifier("focus-preset-period-previous")
                Text(periodLabel(statistics.periodInterval)).font(.system(size: 12))
                Button { movePeriod(1) } label: { Image(systemName: "chevron.right").frame(width: 16, height: 18) }
                    .buttonStyle(.plain).accessibilityIdentifier("focus-preset-period-next")
            }.foregroundStyle(theme.text2).frame(height: 20)
            FocusPresetChart(days: statistics.days, period: period,
                             targetSeconds: preset.stopwatch ? nil : preset.minutes * 60,
                             calendar: store.presentationCalendar, theme: theme)
                .padding(.top, 14).focusRenderAnchor(.presetDetailChart)
        }
    }

    private func recordsSection(_ statistics: FocusPresetStatistics, preset: FocusStore.TimerPreset) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(recordGroups(statistics.records), id: \.day) { group in
                Text(shortDate(group.day)).font(.system(size: 13)).foregroundStyle(theme.text3)
                    .padding(.top, 6).padding(.bottom, 20)
                ForEach(group.records) { record in
                    recordRow(record, preset: preset)
                }
            }
            if statistics.records.isEmpty {
                Text("本\(period.title)暂无专注记录").font(.system(size: 13)).foregroundStyle(theme.text3)
                    .frame(maxWidth: .infinity).padding(.top, 18)
            }
        }
    }

    private func recordRow(_ record: PomodoroRecord, preset: FocusStore.TimerPreset) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: record.mode == .stopwatch ? "stopwatch.fill" : "timer")
                    .font(.system(size: 13)).foregroundStyle(theme.accent)
                    .frame(width: 24, height: 24).background(theme.accent.opacity(0.13), in: Circle())
                Circle().stroke(theme.accent, lineWidth: 1).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(recordTime(record)).font(.system(size: 12)).foregroundStyle(theme.text3)
                    Spacer()
                    Text("\(record.activeSeconds / 60)m").font(.system(size: 12)).foregroundStyle(theme.text3)
                }
                Text(record.taskID.flatMap { workspace?.task(for: $0)?.title } ?? preset.name)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.text).lineLimit(2)
                if let note = record.note {
                    Text(note).font(.system(size: 13)).foregroundStyle(theme.text2).lineLimit(2)
                }
            }
        }
        .padding(.bottom, 20).contentShape(Rectangle()).onTapGesture { selectedRecord = record }
        .accessibilityIdentifier("focus-preset-record-\(record.id.uuidString)")
        .businessContextMenu {
            Button("查看详情") { selectedRecord = record }
            Button("编辑") { recordDraft = FocusRecordDraft(record: record) }
            Button("删除记录", role: .destructive) { store.deleteRecord(record.id) }
        }
    }

    private func reload() {
        statistics = store.presetStatistics(presetID: presetID, period: period, anchor: periodAnchor)
    }
    private func movePeriod(_ delta: Int) {
        periodAnchor = store.presentationCalendar.date(byAdding: period.calendarComponent, value: delta,
                                                       to: periodAnchor ?? store.currentTime)
    }
    private func periodLabel(_ interval: DateInterval) -> String {
        let end = store.presentationCalendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        return shortDate(interval.start) + " - " + shortDate(end)
    }
    private func shortDate(_ day: Date) -> String {
        let components = store.presentationCalendar.dateComponents([.month, .day], from: day)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }
    private func recordTime(_ record: PomodoroRecord) -> String {
        let start = FocusViewLogic.timeLabel(for: record.startedAt, calendar: store.presentationCalendar)
        return start + " - " + (record.endedAt.map {
            FocusViewLogic.timeLabel(for: $0, calendar: store.presentationCalendar)
        } ?? "未知")
    }
    private func recordGroups(_ records: [PomodoroRecord]) -> [(day: Date, records: [PomodoroRecord])] {
        Dictionary(grouping: records, by: { store.presentationCalendar.startOfDay(for: $0.startedAt) })
            .map { (day: $0.key, records: $0.value) }.sorted { $0.day > $1.day }
    }
    private func addRecord(_ preset: FocusStore.TimerPreset) {
        var draft = FocusRecordDraft(now: store.currentTime, taskID: preset.taskID,
                                    mode: preset.stopwatch ? .stopwatch : .pomodoro, presetID: preset.id)
        if !preset.stopwatch {
            draft.startedAt = draft.endedAt.addingTimeInterval(TimeInterval(-preset.minutes * 60))
            draft.durationMinutes = preset.minutes
        }
        recordDraft = draft
    }
}

private struct FocusPresetChart: View {
    let days: [FocusPresetDayTotal]
    let period: FocusPresetStatisticsPeriod
    let targetSeconds: Int?
    let calendar: Calendar
    let theme: FocusTheme
    private let axisWidth: CGFloat = 44
    private var maximumSeconds: Int {
        max(3_600, Int(ceil(Double(max(days.map(\.activeSeconds).max() ?? 0, targetSeconds ?? 0)) / 1_200)) * 1_200)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let plotWidth = max(0, geometry.size.width - axisWidth)
                let height = geometry.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { index in
                        let y = height * CGFloat(index) / 3
                        Rectangle().fill(theme.hairline).frame(width: plotWidth, height: 1).offset(y: y)
                        Text(axisLabel(maximumSeconds * (3 - index) / 3))
                            .font(.system(size: 12)).foregroundStyle(theme.text3)
                            .frame(width: axisWidth, height: 16, alignment: .leading)
                            .offset(x: plotWidth + 8, y: y - 8)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(days) { day in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2).fill(theme.accent)
                                    .frame(width: min(22, max(3, plotWidth / CGFloat(max(1, days.count)) * 0.38)),
                                           height: height * CGFloat(day.activeSeconds) / CGFloat(maximumSeconds))
                            }.frame(maxWidth: .infinity)
                        }
                    }.frame(width: plotWidth, height: height)
                    if let targetSeconds {
                        let y = height * (1 - CGFloat(targetSeconds) / CGFloat(maximumSeconds))
                        Rectangle().fill(theme.warn).frame(width: plotWidth, height: 1).offset(y: y)
                        Text("\(targetSeconds / 60)m").font(.system(size: 12)).foregroundStyle(theme.warn)
                            .frame(width: axisWidth, height: 16, alignment: .leading).offset(x: plotWidth + 8, y: y - 8)
                    }
                }
            }.frame(height: FocusLayoutMetrics.presetDetailChartHeight)
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Text(dayLabel(day.day, index: index)).font(.system(size: 12)).foregroundStyle(theme.text3)
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: axisWidth)
            }.frame(height: 20)
        }
    }
    private func axisLabel(_ seconds: Int) -> String {
        seconds >= 3_600 && seconds.isMultiple(of: 3_600) ? "\(seconds / 3_600)h" : "\(seconds / 60)m"
    }
    private func dayLabel(_ date: Date, index: Int) -> String {
        if period == .week {
            return ["日", "一", "二", "三", "四", "五", "六"][calendar.component(.weekday, from: date) - 1]
        }
        return index.isMultiple(of: 5) || index == days.count - 1 ? "\(calendar.component(.day, from: date))" : ""
    }
}
