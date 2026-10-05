import SwiftUI

/// 时间线视图（滴答清单页 ··· → 视图：列表 / 看板 / **时间线**）。
///
/// 结构照滴答自己的前端组件 `TimelineContentBlock` 定：
/// 左侧是任务行（title + subText），右侧是**按天分栏的网格**（其量纲就是
/// `viewGridDayWidth` / `dayWidth`），一行任务画成一根**跨天条**；
/// 它还有折叠与"拖到表头改期"的入口——本轮先落**只读版**（浏览 + 选中），
/// 折叠与拖拽改期登记待做。
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(rangeStart)
                if rows.isEmpty {
                    Text("时间线上没有带日期的任务")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .padding(WFSpace.md)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(rows, id: \.task.id) { row in
                                timelineRow(row, rangeStart: rangeStart)
                            }
                        }
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
                .background(barColor(task), in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
