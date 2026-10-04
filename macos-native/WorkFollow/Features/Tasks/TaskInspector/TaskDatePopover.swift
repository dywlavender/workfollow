import SwiftUI

struct TaskDateButton: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    var timeOnly = false
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            if let date = task.schedule.dueAt {
                Text(timeOnly && task.schedule.hasTime
                     ? Self.clockLabel(date, calendar: workspace.calendar)
                     : TaskDateLabel.text(date, hasTime: task.schedule.hasTime, now: workspace.clock(), calendar: workspace.calendar))
                    .lineLimit(1)
            } else {
                Image(systemName: "calendar.badge.plus")
            }
        }.buttonStyle(.plain).font(WFType.supporting)
            .foregroundStyle(task.isClosed ? WFColors.tertiaryText : isOverdue ? .red : WFColors.accent)
            .help("修改安排日期")
            .schedulePopover(isPresented: $presented) {
                TaskDatePopoverV2(task: task, workspace: workspace) { presented = false }
            }
    }

    private var isOverdue: Bool {
        guard let dueAt = task.schedule.dueAt else { return false }
        return workspace.calendar.startOfDay(for: dueAt) < workspace.calendar.startOfDay(for: workspace.clock())
    }

    private static func clockLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
