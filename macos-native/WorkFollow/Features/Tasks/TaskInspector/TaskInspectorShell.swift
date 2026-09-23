import SwiftUI

struct TaskInspectorShell: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let showBack: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let task = workspace.selectedTask {
                HStack(spacing: WFSpace.md) {
                    if showBack {
                        Button { workspace.select(nil) } label: {
                            Label("返回", systemImage: "chevron.left")
                        }.buttonStyle(.plain)
                    }
                    Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                        .foregroundStyle(WFColors.secondaryText)
                    if let date = task.schedule.dueAt {
                        Label(date.formatted(date: .abbreviated, time: task.schedule.hasTime ? .shortened : .omitted),
                              systemImage: "calendar").foregroundStyle(WFColors.accent)
                    }
                    if let deadline = task.schedule.deadlineAt {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar.badge.exclamationmark")
                            .foregroundStyle(WFColors.secondaryText)
                    }
                    Spacer()
                    Image(systemName: task.priority == .none ? "flag" : "flag.fill")
                        .foregroundStyle(task.priority == .none ? WFColors.secondaryText : .orange)
                }
                .font(WFType.body).padding(WFSpace.xl)
                Divider()
                Text(task.title).font(WFType.detailTitle)
                    .textSelection(.enabled).padding(WFSpace.page)
                Spacer(minLength: 0)
                Divider()
                Label(task.list.name, systemImage: "tray")
                    .font(WFType.body).foregroundStyle(WFColors.secondaryText)
                    .padding(WFSpace.xl)
            } else {
                Spacer()
                VStack(spacing: WFSpace.md) {
                    Image(systemName: "hand.point.up.left").font(.title2)
                    Text("选择一个任务").font(WFType.body)
                }
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        .onExitCommand { if showBack { workspace.select(nil) } }
    }
}
