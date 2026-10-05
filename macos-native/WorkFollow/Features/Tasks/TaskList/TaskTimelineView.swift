import SwiftUI

/// 时间线视图（滴答清单页 ··· → 视图：列表 / 看板 / **时间线**）。
///
/// ⚠️ **当前不进 UI**（`TaskListViewMode.exposedCases` 不含 `.timeline`）。
///
/// 更正：本文件早先写着"结构照滴答自己的前端组件 `TimelineContentBlock` 定"——
/// 那个依据拿不出来（仓库与桌面基线里都搜不到该标识符），是我的推断被写成了事实。
/// 我对滴答时间线**没有一手依据**（真有一手依据的只有层级"文件夹→清单→分组→任务"
/// 与文件夹/分组的入口语义，来自官方帮助中心）。
///
/// 实测结论（自测截图 + 量像素）：缺了拖拽改期，它就只是"按天对齐的只读表格"，
/// 对"多数任务没有日期"的数据分布没有任何价值，且 1 条任务撑起 21 天空网格像坏了。
/// **重新暴露前必须先补**：左列钉住、拖拽改期、未排期任务池、日格线通到底。
struct TaskTimelineView: View {
    let groups: [TaskListGroup]
    @ObservedObject var workspace: TaskWorkspaceModel
    let onSelect: (UUID) -> Void

    private static let dayWidth: CGFloat = 88
    private static let rowHeight: CGFloat = 32
    private static let labelWidth: CGFloat = 208
    private static let dayCount = 21

    /// 时间线的行（几何见 `TaskTimelineLayout`，此处只做取值与排序）。
    private var rows: [TaskTimelineRow] {
        let tasks = groups.flatMap(\.tasks)
        return TaskTimelineLayout.rows(tasks: tasks, now: workspace.clock(),
                                       calendar: workspace.calendar)
    }

    private var rangeStart: Date {
        TaskTimelineLayout.rangeStart(tasks: groups.flatMap(\.tasks),
                                      now: workspace.clock(), calendar: workspace.calendar)
    }

    var body: some View {
        let rows = self.rows
        let rangeStart = self.rangeStart
        // 表头与行必须躺在**同一个**滚动容器里：分成两个滚动视图时表头会被容器裁掉、
        // 且与行的横向偏移各滚各的（实测截图：时间线只剩左边一条窄栏）。
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(rangeStart)
                if rows.isEmpty {
                    Text("时间线上没有带日期的任务")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .padding(WFSpace.md)
                } else {
                    ForEach(rows, id: \.task.id) { row in
                        timelineRow(row, rangeStart: rangeStart)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 表头：左侧标题栏占位 + 按天分栏（今天高亮）。
    private func headerRow(_ rangeStart: Date) -> some View {
        HStack(spacing: 0) {
            Text("任务").font(WFType.sectionSemibold)
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: Self.labelWidth, alignment: .leading)
                .padding(.leading, WFSpace.sm)
            let today = workspace.calendar.startOfDay(for: workspace.clock())
            ForEach(0..<Self.dayCount, id: \.self) { index in
                let day = workspace.calendar.date(byAdding: .day, value: index, to: rangeStart) ?? rangeStart
                VStack(spacing: 2) {
                    Text(day, format: .dateTime.weekday(.abbreviated).locale(.appDate))
                        .font(WFType.supporting)
                        .foregroundStyle(day == today ? WFColors.accent : WFColors.secondaryText)
                    Text(day, format: .dateTime.month(.abbreviated).day().locale(.appDate))
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .frame(width: Self.dayWidth)
                // 今天那一列整体加底色：只有表头文字变色，一整列是空的会看不出"今天"。
                .background(day == today ? WFColors.accent.opacity(0.08) : Color.clear)
                .overlay(alignment: .leading) {
                    Rectangle().fill(WFColors.listSelection.opacity(0.5)).frame(width: 1)
                }
            }
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func timelineRow(_ row: TaskTimelineRow, rangeStart: Date) -> some View {
        HStack(spacing: 0) {
            Text(title(of: row.task))
                .font(WFType.listBody)
                .foregroundStyle(row.task.isClosed ? WFColors.taskCompletedPreview : WFColors.text)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
                .padding(.leading, WFSpace.sm)
            ZStack(alignment: .leading) {
                // 天格底纹（与表头同一列宽）
                HStack(spacing: 0) {
                    ForEach(0..<Self.dayCount, id: \.self) { _ in
                        Color.clear.frame(width: Self.dayWidth)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(WFColors.listSelection.opacity(0.5)).frame(width: 1)
                            }
                    }
                }
                // 今天基线（每行一段，与表头的今天底色连成一条）。
                if let offset = todayOffset(rangeStart) {
                    Rectangle().fill(WFColors.accent.opacity(0.55))
                        .frame(width: 1.5)
                        .offset(x: CGFloat(offset) * Self.dayWidth)
                }
                bar(row.task)
                    .frame(width: CGFloat(row.span) * Self.dayWidth - 6, height: 20)
                    .offset(x: CGFloat(max(0, row.start)) * Self.dayWidth + 3)
            }
        }
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// 跨天条：起点 = 开始日，长度 = 天数（`dueEndAt` 拉长）；点一下选中任务。
    private func bar(_ task: Task) -> some View {
        Button {
            onSelect(task.id)
        } label: {
            Text(task.title.isEmpty ? "无标题" : task.title)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.text)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // 底色必须画在 Button **外层**：SwiftUI 给 label 的宽度提议是"未指定"，
        // 画在 label 里就只有文字固有宽度（实测 1 天的条只画了 55pt，而不是 88-6）。
        .background(barColor(task), in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    /// 今天在 21 天视野里的列号；不在视野内 → nil。
    private func todayOffset(_ rangeStart: Date) -> Int? {
        let today = workspace.calendar.startOfDay(for: workspace.clock())
        let days = workspace.calendar.dateComponents([.day], from: rangeStart, to: today).day ?? 0
        return (0..<Self.dayCount).contains(days) ? days : nil
    }


    private func title(of task: Task) -> String {
        task.title.isEmpty ? "无标题" : task.title
    }

    private func barColor(_ task: Task) -> Color {
        if task.isClosed { return WFColors.listSelection }
        switch task.priority {
        case .high: return TaskRowPriority.color(.high).opacity(0.28)
        case .medium: return TaskRowPriority.color(.medium).opacity(0.28)
        case .low: return TaskRowPriority.color(.low).opacity(0.28)
        case .none: return WFColors.accent.opacity(0.22)
        }
    }
}


/// 时间线的**纯几何**：范围起点、每条任务的起点偏移与跨度天数。
/// 抽出来是为了可单测——视图只负责按它画，不再自己算。
/// 口径：起点 = `min(今天, 最早到期日)`（逾期任务也在视野里）；
/// 跨度 = `dueEndAt` 拉长的天数（无 `dueEndAt` 即 1 天）；无日期任务不进时间线。
struct TaskTimelineRow: Equatable {
    let task: Task
    let start: Int
    let span: Int
}

enum TaskTimelineLayout {
    static let dayCount = 21

    static func rangeStart(tasks: [Task], now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let earliest = tasks.compactMap { $0.schedule.dueAt }
            .map { calendar.startOfDay(for: $0) }.min()
        guard let earliest, earliest < today else { return today }
        return earliest
    }

    static func rows(tasks: [Task], now: Date, calendar: Calendar) -> [TaskTimelineRow] {
        let start = rangeStart(tasks: tasks, now: now, calendar: calendar)
        var seen = Set<UUID>()
        var rows: [TaskTimelineRow] = []
        for task in tasks where seen.insert(task.id).inserted {
            guard let due = task.schedule.dueAt else { continue }
            let dueDay = calendar.startOfDay(for: due)
            let endDay = task.schedule.dueEndAt.map { calendar.startOfDay(for: $0) } ?? due
            let span = max(1, (calendar.dateComponents([.day], from: dueDay, to: endDay).day ?? 0) + 1)
            rows.append(TaskTimelineRow(task: task,
                                        start: calendar.dateComponents([.day], from: start,
                                                                       to: dueDay).day ?? 0,
                                        span: span))
        }
        return rows.sorted { ($0.start, $0.task.id.uuidString) < ($1.start, $1.task.id.uuidString) }
    }
}
