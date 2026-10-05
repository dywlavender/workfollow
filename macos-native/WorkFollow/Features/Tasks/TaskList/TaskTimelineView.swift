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

    /// 时间线的行：有日期的任务（时间段按 `dueEndAt` 拉长）。无日期任务不进时间线。
    private var rows: [(task: Task, start: Int, span: Int)] {
        let calendar = workspace.calendar
        let rangeStart = startDay(calendar)
        var seen = Set<UUID>()
        var result: [(Task, Int, Int)] = []
        for group in groups {
            for task in group.tasks where seen.insert(task.id).inserted {
                guard let due = task.schedule.dueAt else { continue }
                let start = dayOffset(from: rangeStart, to: calendar.startOfDay(for: due))
                let endDay = task.schedule.dueEndAt.map { calendar.startOfDay(for: $0) } ?? due
                let span = max(1, dayOffset(from: calendar.startOfDay(for: due),
                                            to: calendar.startOfDay(for: endDay)) + 1)
                result.append((task, start, span))
            }
        }
        return result.sorted { ($0.1, $0.0.title) < ($1.1, $1.0.title) }
    }

    private func startDay(_ calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: workspace.clock())
        let earliest = groups.flatMap(\.tasks).compactMap { $0.schedule.dueAt }
            .map { calendar.startOfDay(for: $0) }.min()
        guard let earliest, earliest < today else { return today }
        return earliest
    }

    private func dayOffset(from start: Date, to day: Date) -> Int {
        workspace.calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    var body: some View {
        let rows = self.rows
        let rangeStart = startDay(workspace.calendar)
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

    private func timelineRow(_ row: (task: Task, start: Int, span: Int),
                             rangeStart: Date) -> some View {
        HStack(spacing: 0) {
            Text(row.task.title.isEmpty ? "无标题" : row.task.title)
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
