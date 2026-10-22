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
    @State private var recordDraft: FocusRecordDraft?
    @State private var selectedRecord: PomodoroRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.contentRoute == .records ? "专注记录" : "概览")
                    .font(.system(size: FocusLayoutMetrics.overviewTitleFontSize, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                if store.contentRoute == .records {
                    Button("清除筛选") { store.showOverview() }.buttonStyle(.plain)
                }
                Button("更多统计") { store.showStatistics() }.buttonStyle(.plain)
                    .accessibilityIdentifier("focus-show-statistics")
            }.padding(.bottom, FocusLayoutMetrics.overviewTitleBottom)

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
                Button { recordDraft = FocusRecordDraft(now: store.currentTime) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: FocusLayoutMetrics.recordHeaderIconSize, weight: .medium))
                        .frame(width: FocusLayoutMetrics.recordHeaderButtonSize,
                               height: FocusLayoutMetrics.recordHeaderButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text2)
                .help("补记专注")
                .accessibilityIdentifier("focus-add-record")
            }
            .padding(.top, FocusLayoutMetrics.recordHeaderTop)
            .padding(.bottom, FocusLayoutMetrics.recordHeaderBottom)

            if store.recordGroups.isEmpty && !store.historyLoading && !store.historyHasMore && store.historyError == nil {
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
        .task(id: store.historyRevision) { await store.resetHistory() }
        .sheet(item: $recordDraft) { draft in FocusRecordEditor(store: store, workspace: workspace, draft: draft) }
        .sheet(item: $selectedRecord) { record in
            FocusRecordDetail(store: store, recordID: record.id, workspace: workspace, onSelectTask: onSelectRecordTask)
        }
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
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.recordGroups) { group in
                Text(FocusViewLogic.dayLabel(for: group.day, now: store.currentTime, calendar: store.presentationCalendar))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text3)
                    .padding(.top, FocusLayoutMetrics.recordGroupTop)
                    .padding(.bottom, FocusLayoutMetrics.recordGroupBottom)
                ForEach(group.records) { record in recordRow(record) }
            }
            if store.historyLoading {
                ProgressView().controlSize(.small).padding()
            } else if let error = store.historyError {
                Text("读取记录失败：\(error)").font(.caption).foregroundStyle(theme.text3)
                Button("重试") { _Concurrency.Task { await store.loadMoreHistory() } }
            } else if store.historyHasMore {
                Button("加载更多") { _Concurrency.Task { await store.loadMoreHistory() } }
                    .buttonStyle(.plain).padding()
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
            selectedRecord = record
        }
        .onHover { hovering in
            if hovering {
                hoveredRecordID = record.id
            } else if hoveredRecordID == record.id {
                hoveredRecordID = nil
            }
        }
        .accessibilityIdentifier("focus-record-\(record.id.uuidString)")
        .businessContextMenu {
            Button("查看详情") { selectedRecord = record }
            Button("编辑") { recordDraft = FocusRecordDraft(record: record) }
            if let taskID = record.taskID { Button("打开任务") { onSelectRecordTask?(taskID) } }
            Button("删除记录", role: .destructive) { store.deleteRecord(record.id) }
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
        FocusViewLogic.timeLabel(for: date, calendar: store.presentationCalendar)
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
