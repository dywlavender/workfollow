import SwiftUI

struct TaskInspectorShell: View {
    @ObservedObject var workspace: PreviewWorkspace
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
                    Image(systemName: task.completed ? "checkmark.square.fill" : "square")
                        .foregroundStyle(WFColors.secondaryText)
                    if task.scheduledToday {
                        Label("今天", systemImage: "calendar").foregroundStyle(WFColors.accent)
                    }
                    Spacer()
                    Image(systemName: task.priority ? "flag.fill" : "flag")
                        .foregroundStyle(task.priority ? .orange : WFColors.secondaryText)
                }
                .font(WFType.body).padding(WFSpace.xl)
                Divider()
                Text(task.title).font(WFType.detailTitle)
                    .textSelection(.enabled).padding(WFSpace.page)
                Spacer(minLength: 0)
                Divider()
                Label(task.list, systemImage: "tray")
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
