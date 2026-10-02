import SwiftUI

/// Focus 右侧概览与记录。尺寸使用固定 point 值，随窗口变化只调整卡片列宽和记录区。
struct FocusOverviewPane: View {
    @ObservedObject var store: FocusStore
    let workspace: TaskWorkspaceModel?
    let onSelectRecordTask: ((UUID) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    private var theme: FocusTheme { FocusTheme(colorScheme) }

    @State private var hoveredRecordID: UUID?
    @State private var showGoalPopover = false
    @State private var showAddRecord = false
    @State private var addRecordTaskID: UUID?
    @State private var addRecordMinutes = "25"
    @State private var addRecordHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("概览")
                .font(.system(size: FocusLayoutMetrics.overviewTitleFontSize, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.bottom, FocusLayoutMetrics.overviewTitleBottom)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: FocusLayoutMetrics.overviewCardGap),
                                GridItem(.flexible(), spacing: FocusLayoutMetrics.overviewCardGap)],
                      spacing: FocusLayoutMetrics.overviewCardGap) {
                statCard("今日番茄", value: store.todayPomodoros)
                    .focusRenderAnchor(.overviewFirstCard)
                statCard("今日专注时长", value: store.todayMinutes, unit: "m")
                statCard("总番茄", value: store.allTimePomodoros)
                statCard("总专注时长", value: store.allTimeMinutes, unit: "m")
            }

            goalLine
                .padding(.top, FocusLayoutMetrics.overviewGoalTop)

            HStack(alignment: .firstTextBaseline) {
                Text("专注记录")
                    .font(.system(size: FocusLayoutMetrics.recordHeaderFontSize, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .focusRenderAnchor(.recordsHeader)
                Spacer()
                Button { showAddRecord = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: FocusLayoutMetrics.recordHeaderIconSize, weight: .medium))
                        .frame(width: FocusLayoutMetrics.recordHeaderButtonSize,
                               height: FocusLayoutMetrics.recordHeaderButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text2)
                .help("补记专注")
                .background(AnchoredPropertyPanel(isPresented: $showAddRecord, width: 330) {
                    addRecordPopover
                })
            }
            .padding(.top, FocusLayoutMetrics.recordHeaderTop)
            .padding(.bottom, FocusLayoutMetrics.recordHeaderBottom)

            if store.recordGroups.isEmpty {
                emptyRecordsState
            } else {
                ScrollView { recordsList }
            }
        }
        .padding(.horizontal, FocusLayoutMetrics.overviewHorizontalPadding)
        .padding(.vertical, FocusLayoutMetrics.overviewVerticalPadding)
        .frame(minWidth: FocusLayoutMetrics.overviewPaneMinWidth, maxWidth: .infinity,
               maxHeight: .infinity, alignment: .topLeading)
        .background(theme.canvas)
    }

    private func statCard(_ label: String, value: Int, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: FocusLayoutMetrics.overviewCardTextGap) {
            Text(label)
                .font(.system(size: FocusLayoutMetrics.overviewLabelFontSize))
                .foregroundStyle(theme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: FocusLayoutMetrics.overviewValueFontSize, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
                if let unit {
                    Text(unit)
                        .font(.system(size: FocusLayoutMetrics.overviewUnitFontSize))
                        .foregroundStyle(theme.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FocusLayoutMetrics.overviewCardHorizontalPadding)
        .padding(.vertical, FocusLayoutMetrics.overviewCardVerticalPadding)
        .frame(height: FocusLayoutMetrics.overviewCardHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FocusLayoutMetrics.overviewCardRadius)
            .fill(theme.cardBackground))
    }

    private var goalLine: some View {
        Button { showGoalPopover = true } label: {
            HStack(spacing: FocusLayoutMetrics.overviewGoalContentGap) {
                Text("今日目标 \(store.todayPomodoros) / \(store.preferences.dailyGoal)")
                    .font(.system(size: FocusLayoutMetrics.overviewGoalFontSize))
                    .foregroundStyle(theme.text2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.track)
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: max(0, geo.size.width *
                                CGFloat(min(store.todayPomodoros, store.preferences.dailyGoal)) /
                                CGFloat(max(1, store.preferences.dailyGoal))))
                    }
                }
                .frame(height: FocusLayoutMetrics.overviewGoalProgressHeight)
            }
        }
        .buttonStyle(.plain)
        .help("点击修改每日目标")
        .background(AnchoredPropertyPanel(isPresented: $showGoalPopover, width: 190) {
            goalEditor
        })
    }

    private var emptyRecordsState: some View {
        VStack(spacing: FocusLayoutMetrics.recordEmptyContentGap) {
            FocusEmptyRecordsIllustration(theme: theme)
                .focusRenderAnchor(.emptyRecordsIllustration)
            Text("还没有专注记录")
                .font(.system(size: FocusLayoutMetrics.recordEmptyFontSize))
                .foregroundStyle(theme.text3)
        }
        .focusRenderAnchor(.emptyRecordsContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusRenderAnchor(.emptyRecordsRegion)
        .offset(y: -FocusLayoutMetrics.recordEmptyVerticalOffset)
    }

    private var recordsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.recordGroups) { group in
                Text(FocusViewLogic.dayLabel(for: group.day))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text3)
                    .padding(.top, FocusLayoutMetrics.recordGroupTop)
                    .padding(.bottom, FocusLayoutMetrics.recordGroupBottom)
                ForEach(group.records) { record in recordRow(record) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordRow(_ record: PomodoroRecord) -> some View {
        let isHovered = hoveredRecordID == record.id
        return HStack(spacing: 12) {
            Text(timeText(record.startedAt))
                .font(.system(size: FocusLayoutMetrics.recordTimeFontSize))
                .monospacedDigit()
                .foregroundStyle(theme.text3)
                .frame(width: 76, alignment: .leading)
            Text(recordTitle(for: record))
                .font(.system(size: FocusLayoutMetrics.recordTitleFontSize))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .frame(minWidth: 0, alignment: .leading)
            Spacer(minLength: 8)
            Text("\(record.minutes) 分钟")
                .font(.system(size: FocusLayoutMetrics.recordMinutesFontSize))
                .monospacedDigit()
                .foregroundStyle(record.completed ? theme.text2 : theme.text3)
            Circle()
                .fill(record.completed ? theme.good : theme.warn)
                .frame(width: FocusLayoutMetrics.recordStatusDotSize,
                       height: FocusLayoutMetrics.recordStatusDotSize)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FocusLayoutMetrics.recordRowHeight)
        .overlay(alignment: .trailing) {
            if isHovered {
                Button { store.deleteRecord(record.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.text3)
                        .frame(width: 26, height: 28)
                        .background(theme.canvas.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("删除记录")
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let taskID = record.taskID else { return }
            onSelectRecordTask?(taskID)
        }
        .onHover { hovering in
            if hovering {
                hoveredRecordID = record.id
            } else if hoveredRecordID == record.id {
                hoveredRecordID = nil
            }
        }
        .contextMenu {
            Button("删除记录", role: .destructive) { store.deleteRecord(record.id) }
        }
    }

    private var addRecordPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("补记专注")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.text)
            Menu {
                Button("不关联") { addRecordTaskID = nil }
                ForEach(recordCandidates) { task in
                    Button {
                        addRecordTaskID = task.id
                    } label: {
                        if task.id == addRecordTaskID {
                            Label(taskMenuTitle(task), systemImage: "checkmark")
                        } else {
                            Text(taskMenuTitle(task))
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(listDotColor(for: addRecordTaskID)).frame(width: 9, height: 9)
                    Text(addRecordTaskTitle)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text3)
                }
                .frame(width: 280)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            HStack(spacing: 12) {
                Text("时长").font(.system(size: 15)).foregroundStyle(theme.text2)
                TextField("分钟", text: $addRecordMinutes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text)
                    .frame(width: 76)
                    .padding(.vertical, 6)
                    .background(Capsule().stroke(theme.hairline, lineWidth: 1.5))
                    .onSubmit(submitAddRecord)
            }
            if let addRecordHint {
                Text(addRecordHint).font(.system(size: 13)).foregroundStyle(theme.warn)
            }
            Text("仅支持补记最近 7 天内、此刻之前的专注")
                .font(.system(size: 13))
                .foregroundStyle(theme.text3)
            HStack {
                Spacer()
                Button(action: submitAddRecord) {
                    Text("添 加")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 110, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 330)
    }

    private var recordCandidates: [Task] {
        guard let workspace else { return [] }
        return workspace.allTasks.filter { $0.deletedAt == nil && !$0.isAbandoned }
    }

    private var addRecordTaskTitle: String {
        guard let addRecordTaskID, let title = taskTitle(for: addRecordTaskID) else { return "不关联" }
        return title
    }

    private func submitAddRecord() {
        let minutes = Int(addRecordMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
        let endedNow = workspace?.clock() ?? Date()
        let startedAt = endedNow.addingTimeInterval(TimeInterval(-minutes * 60))
        if store.addRecord(taskID: addRecordTaskID, startedAt: startedAt, minutes: minutes) {
            showAddRecord = false
            addRecordHint = nil
            addRecordMinutes = "25"
        } else {
            addRecordHint = "补记失败：时长需 1–180 分钟，且时间要在最近 7 天内"
        }
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text("每日专注目标").font(WFType.section)
            Stepper(value: Binding(
                get: { store.preferences.dailyGoal },
                set: { store.setDailyGoal($0) }), in: 1...24) {
                Text("\(store.preferences.dailyGoal) 个番茄/天").font(WFType.body)
            }
        }
        .padding(WFSpace.lg)
        .frame(width: 190, alignment: .leading)
    }

    private func taskTitle(for id: UUID) -> String? {
        guard let workspace, let task = workspace.task(for: id) else { return nil }
        return task.title.isEmpty ? "未命名任务" : task.title
    }

    private func taskMenuTitle(_ task: Task) -> String {
        task.title.isEmpty ? "未命名任务" : task.title
    }

    private func recordTitle(for record: PomodoroRecord) -> String {
        record.taskID.flatMap { taskTitle(for: $0) } ?? "未关联任务"
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func listDotColor(for id: UUID?) -> Color {
        guard let id, let workspace, let task = workspace.task(for: id),
              let argb = workspace.listMetas.first(where: { $0.name == task.list.name })?.colorARGB
        else { return theme.accent }
        return Color(red: Double((argb >> 16) & 0xFF) / 255,
                     green: Double((argb >> 8) & 0xFF) / 255,
                     blue: Double(argb & 0xFF) / 255)
    }
}
