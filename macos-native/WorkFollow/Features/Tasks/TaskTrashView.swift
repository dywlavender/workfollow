import SwiftUI

struct TaskTrashView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var confirmClear = false
    @State private var purgeID: UUID?
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width >= 640 || workspace.selectedTask == nil {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Label("垃圾桶", systemImage: "trash").font(WFType.pageTitle)
                            Spacer()
                            Button("全部删除") { confirmClear = true }.disabled(workspace.deletedTasks.isEmpty)
                        }
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if workspace.deletedTasks.isEmpty { Text("垃圾桶是空的").foregroundStyle(.secondary).padding() }
                                ForEach(workspace.deletedTasks) { task in
                                    Button { workspace.select(task.id) } label: {
                                        HStack {
                                            Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                                            Text(task.title.isEmpty ? "未命名任务" : task.title).lineLimit(1)
                                            Spacer()
                                            Text(task.deletedAt!.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                                        }.padding(.vertical, 16).padding(.horizontal, 8)
                                            .background(workspace.selectedTaskID == task.id ? WFColors.selection : .clear)
                                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                                    Divider()
                                }
                            }
                        }
                    }.padding(20).frame(maxWidth: geometry.size.width >= 640 ? 440 : .infinity)
                }
                if geometry.size.width >= 640 || workspace.selectedTask != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 20) {
                        if let task = workspace.selectedTask, task.deletedAt != nil {
                            HStack {
                                Button("返回") { workspace.select(nil) }
                                Spacer()
                                Button("恢复") { workspace.restoreDeleted(task.id) }
                                    .disabled(task.parentID.flatMap { workspace.task(for: $0)?.deletedAt } != nil)
                                Button("永久删除", role: .destructive) { purgeID = task.id }
                            }
                            Text(task.title).font(WFType.detailTitle)
                            Text(task.list.name).foregroundStyle(.secondary)
                            ScrollView { Text(task.document.plainText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        } else {
                            Text("选择一个任务").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("清空任务垃圾桶", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("全部删除", role: .destructive) { workspace.emptyTrash() }
        } message: { Text("垃圾桶中的任务将被永久删除，无法恢复。笔记不受影响。") }
        .alert("永久删除任务？", isPresented: Binding(get: { purgeID != nil }, set: { if !$0 { purgeID = nil } })) {
            Button("取消", role: .cancel) { purgeID = nil }
            Button("删除", role: .destructive) { if let id = purgeID { workspace.permanentlyDelete(id) }; purgeID = nil }
        } message: { Text("该任务和其子任务将被永久删除。") }
    }
}
