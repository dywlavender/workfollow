import AppKit
import SwiftUI

struct TaskTrashView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var dragOrigin: CGFloat?
    @State private var confirmClear = false
    @State private var purgeID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= WFMetrics.splitMinimum
            let maximum = max(WFMetrics.listMinimum,
                              min(WFMetrics.listMaximum,
                                  geometry.size.width - WFMetrics.inspectorMinimum - WFMetrics.divider))
            let boundedWidth = min(max(workspace.taskListPaneWidth, WFMetrics.listMinimum), maximum)
            if wide {
                HStack(spacing: 0) {
                    list
                        .frame(width: boundedWidth)
                    Rectangle().fill(WFColors.border).frame(width: WFMetrics.divider)
                        .overlay {
                            Color.clear.frame(width: WFSpace.sm).contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() }
                                    else { NSCursor.pop() }
                                }
                                .gesture(DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if dragOrigin == nil { dragOrigin = boundedWidth }
                                        workspace.setTaskListPaneWidth(min(max((dragOrigin ?? boundedWidth)
                                            + value.translation.width, WFMetrics.listMinimum), maximum))
                                    }
                                    .onEnded { _ in dragOrigin = nil })
                        }
                    inspector(showBack: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let task = selectedTrashTask {
                inspector(showBack: true, task: task)
            } else {
                list
            }
        }
        .background(WFColors.content)
        .onAppear {
            if workspace.selectedTask?.deletedAt == nil { workspace.select(nil) }
        }
        .overlay {
            GeometryReader { overlayGeometry in
                if confirmClear {
                    TaskTrashConfirmationOverlay(
                        title: "清空垃圾桶",
                        message: "垃圾桶中的任务将被永久删除，确定清空垃圾桶吗？",
                        confirmTitle: "全部删除",
                        width: min(440, max(280, overlayGeometry.size.width - 40)),
                        onCancel: { confirmClear = false },
                        onConfirm: {
                            confirmClear = false
                            workspace.emptyTrash()
                        })
                } else if let id = purgeID {
                    TaskTrashConfirmationOverlay(
                        title: "永久删除任务？",
                        message: "该任务和它的子任务将无法恢复。",
                        confirmTitle: "永久删除",
                        width: min(440, max(280, overlayGeometry.size.width - 40)),
                        onCancel: { purgeID = nil },
                        onConfirm: {
                            purgeID = nil
                            workspace.permanentlyDelete(id)
                        })
                }
            }
        }
    }

    private var selectedTrashTask: Task? {
        guard let task = workspace.selectedTask, task.deletedAt != nil else { return nil }
        return task
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            HStack(spacing: WFSpace.md) {
                Label("垃圾桶", systemImage: "trash").font(WFType.pageTitle)
                Spacer(minLength: 0)
                Button { confirmClear = true } label: { Image(systemName: "trash.slash") }
                    .buttonStyle(.plain)
                    .help("清空垃圾桶")
                    .disabled(workspace.deletedTasks.isEmpty)
            }
            .padding(.horizontal, WFSpace.xl)
            .padding(.top, WFSpace.xl)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if workspace.deletedTasks.isEmpty {
                        Text("垃圾桶是空的").font(WFType.body).foregroundStyle(WFColors.secondaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, WFSpace.page)
                    }
                    ForEach(workspace.deletedTasks) { task in
                        TrashTaskRow(task: task, workspace: workspace) {
                            purgeID = task.id
                        }
                        Divider().padding(.leading, WFSpace.page)
                    }
                }
                .padding(.horizontal, WFSpace.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
    }

    @ViewBuilder
    private func inspector(showBack: Bool, task: Task? = nil) -> some View {
        if let task = task ?? selectedTrashTask {
            VStack(spacing: 0) {
                HStack(spacing: WFSpace.md) {
                    if showBack {
                        Button { workspace.select(nil) } label: {
                            Label("返回", systemImage: "chevron.left")
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button("恢复") { workspace.restoreDeleted(task.id) }
                        .disabled(task.parentID.flatMap { workspace.task(for: $0)?.deletedAt } != nil)
                    Button("永久删除", role: .destructive) { purgeID = task.id }
                }
                .padding(.horizontal, WFSpace.xl)
                .padding(.vertical, WFSpace.md)
                TaskInspectorShell(workspace: workspace, showBack: showBack)
            }
        } else {
            VStack(spacing: WFSpace.md) {
                Image(systemName: "hand.point.up.left").font(.title2)
                Text("选择一个任务").font(WFType.body)
            }
            .foregroundStyle(WFColors.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TrashTaskRow: View {
    let task: Task
    @ObservedObject var workspace: TaskWorkspaceModel
    let onPurge: () -> Void

    var body: some View {
        HStack(spacing: WFSpace.md) {
            Button { workspace.select(task.id) } label: {
                HStack(spacing: WFSpace.md) {
                    Image(systemName: task.isAbandoned ? "circle.slash"
                                     : task.isClosed ? "checkmark.square.fill" : "square")
                        .foregroundStyle(WFColors.tertiaryText)
                    Text(task.title.isEmpty ? "未命名任务" : task.title)
                        .font(WFType.listTitle)
                        .strikethrough(true, color: WFColors.tertiaryText)
                        .foregroundStyle(WFColors.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: WFSpace.sm)
                    Text("\(task.list.name) · \(deletedLabel)")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: WFMetrics.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(workspace.selectedTaskID == task.id ? WFColors.listSelection : .clear,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            Button { workspace.restoreDeleted(task.id) } label: {
                Image(systemName: "arrow.uturn.backward")
            }.buttonStyle(.plain).help("恢复任务")
                .disabled(task.parentID.flatMap { workspace.task(for: $0)?.deletedAt } != nil)
            Button(action: onPurge) { Image(systemName: "trash.slash") }
                .buttonStyle(.plain).help("永久删除任务")
        }
        .padding(.horizontal, WFSpace.sm)
    }

    private var deletedLabel: String {
        guard let date = task.deletedAt else { return "已删除" }
        return date.formatted(date: .abbreviated, time: .omitted) + " 删除"
    }
}

private struct TaskTrashConfirmationOverlay: View {
    let title: String
    let message: String
    let confirmTitle: String
    let width: CGFloat
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var actionWidth: CGFloat { min(132, max(0, (width - 64) / 2)) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.red, in: Circle())
                }
                .buttonStyle(.plain)
                .help("取消")
                .padding(.bottom, WFSpace.xs)
                Text(title)
                    .font(WFType.pageTitle)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(message)
                    .font(WFType.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, WFSpace.xl)
                HStack(spacing: WFSpace.md) {
                    Spacer(minLength: 0)
                    Button("取消", action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(width: actionWidth, height: 40)
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .frame(width: actionWidth, height: 40)
                }
                .padding(.top, WFSpace.xxl)
            }
            .padding(WFSpace.xl)
            .frame(width: width, alignment: .leading)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.18), radius: 22, y: 9)
            .onTapGesture {}
        }
        .onExitCommand(perform: onCancel)
    }
}
