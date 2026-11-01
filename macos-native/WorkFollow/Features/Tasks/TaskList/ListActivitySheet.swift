import SwiftUI

/// 清单动态（滴答清单页 ··· → 清单动态）：**按清单聚合**的任务变更时间线。
///
/// 事件模型、记录逻辑、"任务动态"三件事都归 `TaskActivityStore`，
/// 本页只做"按清单筛选 + 展示"，因此**不引入新的存储**。
/// 任务标题在渲染时解析——事件本身不冗余存名字；被删除的任务会从清单动态里消失
/// （当前口径，已登记）。
struct ListActivitySheet: View {
    let listName: String
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var activity: TaskActivityStore
    let onClose: () -> Void

    @StateObject private var history = TaskActivityPageModel()
    private var taskIDs: [UUID] {
        workspace.allTasks.filter { !$0.isNoteTask && $0.list.name == listName }.map(\.id)
    }
    private var events: [TaskActivityEvent] { history.events }
    private var queryKey: ActivityPageQueryKey {
        ActivityPageQueryKey(taskIDs: taskIDs, revision: activity.revision)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部与全站弹框同口径：标题用 DialogTitle 令牌、内边距取 formInset。
            // 原来这里用 .headline + 16 内边距，字号与标题位置都和别的弹框对不齐。
            HStack {
                DialogTitle(text: "清单动态 · \(listName)")
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .hoverTip("关闭清单动态")
                    .accessibilityLabel("关闭清单动态")
            }
            .padding(PopupMetrics.formInset)
            Divider()
            if events.isEmpty {
                if !history.isLoading && history.error == nil {
                    VStack(spacing: 8) {
                        Text("暂无清单动态").foregroundStyle(WFColors.text)
                        Text("仅记录启用后的任务变更，不补造历史记录。")
                            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    }
                    .padding(24)
                }
                TaskActivityPageControls(history: history) {
                    await history.loadMore(store: activity, taskIDs: taskIDs)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(workspace.task(for: event.taskID)?.title ?? "该任务")
                                    .foregroundStyle(WFColors.text)
                                    .lineLimit(1)
                                Text(event.title).font(WFType.body)
                                    .foregroundStyle(WFColors.secondaryText)
                                if let detail = event.detail {
                                    Text(detail).font(WFType.supporting)
                                        .foregroundStyle(WFColors.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(event.occurredAt, format: .dateTime.month().day().hour().minute())
                                    .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        TaskActivityPageControls(history: history) {
                            await history.loadMore(store: activity, taskIDs: taskIDs)
                        }
                    }
                    .padding(16)
                }
                .compactScrollbars()
            }
        }
        .task(id: queryKey) { await history.reset(store: activity, taskIDs: taskIDs) }
        .frame(width: SheetDialogMetrics.narrowWidth, height: 420)
        .workfollowPopupSurface(fallback: WFColors.canvas)
        .onExitCommand(perform: onClose)
        .environment(\.calendar, workspace.calendar)
        .environment(\.timeZone, workspace.calendar.timeZone)
    }
}
