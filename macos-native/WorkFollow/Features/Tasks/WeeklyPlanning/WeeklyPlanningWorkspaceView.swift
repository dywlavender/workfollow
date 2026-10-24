import SwiftUI

struct WeeklyPlanningWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var context: WeeklyPlanningContext
    @EnvironmentObject private var environment: AppEnvironment
    @State private var title = ""
    @State private var showsPool = false
    @State private var search = ""
    @State private var showsCompleted = false
    @State private var selecting = false
    @State private var selectedTasks: Set<UUID> = []
    @State private var selectedPool: Set<UUID> = []
    @State private var targetedDay: Int?
    @FocusState private var captureFocused: Bool

    private var projection: WeeklyPlanProjection {
        WeeklyPlanProjection(weekStart: context.weekStart, calendar: workspace.calendar)
    }
    private var tasks: [Task] { projection.tasks(from: workspace.tasksInActiveLists, listName: context.listName) }
    private var pending: [Task] { tasks.filter { !$0.isClosed } }
    private var completed: [Task] { tasks.filter { $0.status == .completed } }
    private var carriedCount: Int {
        let carried = workspace.tasksInActiveLists.filter { task in
            task.deletedAt == nil && task.skippedAt == nil && !task.isConverted
                && (context.listName == nil || task.list.name == context.listName)
                && task.weeklyPlanning?.history.contains(where: { $0.weekKey == context.weekKey && $0.movedToWeek != nil }) == true
        }
        let ids = Set(carried.map(\.id))
        return carried.filter { $0.parentID.map { !ids.contains($0) } ?? true }.count
    }


    var body: some View {
        GeometryReader { geometry in
            if workspace.selectedTask != nil && geometry.size.width < 850 {
                TaskInspectorShell(workspace: workspace, showBack: true, commentStore: environment.taskCommentStore)
            } else {
                HStack(spacing: 0) {
                    planColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if workspace.selectedTask != nil {
                        Divider()
                        TaskInspectorShell(workspace: workspace, showBack: false, allowsClosing: true,
                                           commentStore: environment.taskCommentStore)
                            .frame(width: min(440, geometry.size.width * 0.46))
                    }
                }
            }
        }
        .background(WFColors.content)
        .onAppear { workspace.captureWeekPlan(weekOf: context.weekStart) }
        .onChange(of: context.weekStart) { _, _ in
            workspace.select(nil)
            selectedTasks = []; selectedPool = []
            workspace.captureWeekPlan(weekOf: context.weekStart)
        }
        .onChange(of: context.listName) { _, _ in
            workspace.select(nil); selectedTasks = []; selectedPool = []
        }
        .onChange(of: pending.map(\.id)) { _, ids in selectedTasks.formIntersection(ids) }
        .sheet(isPresented: $showsPool) { taskPool }
    }

    private var planColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("周计划").font(WFType.detailTitle)
                Spacer()
                Button(selecting ? "完成选择" : "选择") {
                    selecting.toggle(); selectedTasks = []
                }.disabled(pending.isEmpty).workflowActionAnchor("weekly.select")
                Button { selectedPool = []; showsPool = true } label: { Label("加入任务", systemImage: "plus") }.workflowActionAnchor("weekly.pool")
                Button(context.isCurrent ? "回顾本周" : "回顾这一周") { environment.navigation.destination = .summary }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.borderless).padding(.horizontal, 24).frame(height: 52)
            Divider()
            WeeklyPlanningToolbar(context: context, listNames: workspace.availableListNames)
            HStack(spacing: 16) {
                Text("待安排 \(pending.filter { $0.schedule.dueAt == nil }.count)")
                Text("待推进 \(pending.count)")
                Text("已完成 \(completed.count)")
                if carriedCount > 0 { Text("已结转 \(carriedCount)") }
                Spacer()
                Text("周一至周日").foregroundStyle(WFColors.tertiaryText)
            }
            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, 24).padding(.bottom, 12)
            if selecting { batchBar }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    capture
                    if pending.isEmpty {
                        VStack(spacing: 8) {
                            Text(tasks.isEmpty ? "这一周还没有计划" : "本周任务已处理完")
                                .font(WFType.section).foregroundStyle(WFColors.secondaryText)
                            Text("可以先加入本周，再安排到具体日期。")
                                .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                            Button("从现有任务中选择") { showsPool = true }.buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                    }
                    let unscheduled = pending.filter { $0.schedule.dueAt == nil }
                    taskSection("待安排日期", tasks: unscheduled, dayIndex: -1)
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let day = workspace.calendar.date(byAdding: .day, value: dayIndex, to: context.weekStart)!
                        let dayTasks = pending.filter { task in
                            guard let due = task.schedule.dueAt else { return false }
                            let visibleDay = max(workspace.calendar.startOfDay(for: due), context.weekStart)
                            return workspace.calendar.isDate(visibleDay, inSameDayAs: day)
                        }
                        taskSection(dayLabel(day, index: dayIndex), tasks: dayTasks, dayIndex: dayIndex)
                    }
                    if !completed.isEmpty {
                        DisclosureGroup(isExpanded: $showsCompleted) {
                            ForEach(completed) { task in taskRow(task) }
                        } label: {
                            Text("已完成 \(completed.count)").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                        }
                        .padding(.horizontal, 24).padding(.top, 20)
                    }
                }
                .padding(.bottom, 32)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var capture: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(WFColors.accent)
            TextField("添加任务，支持明天、#标签、@清单", text: $title)
                .textFieldStyle(.plain).focused($captureFocused)
                .onSubmit {
                    let ids = workspace.submitWeeklyCapture(QuickCaptureSession(text: title),
                        weekOf: context.weekStart, list: context.listName)
                    guard let last = ids.last else { return }
                    title = ""; captureFocused = true
                    if let task = workspace.task(for: last), !projection.includes(task) {
                        environment.feedback.show(FeedbackEvent(kind: .success,
                            message: "已添加到其他日期 · " + task.list.name,
                            destinationTitle: "查看", destinationAction: { environment.openTask(last) }))
                    }
                }
        }
        .font(WFType.body).padding(12)
        .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    private func taskSection(_ label: String, tasks: [Task], dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(WFType.section)
                Text("\(tasks.count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                Spacer()
                if tasks.isEmpty {
                    Text("拖入安排").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                }
            }
            .padding(.horizontal, 24).padding(.top, tasks.isEmpty ? 8 : 16).padding(.bottom, tasks.isEmpty ? 8 : 5)
            ForEach(tasks) { task in taskRow(task) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targetedDay == dayIndex ? WFColors.selection : Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            let ids = Set(values.compactMap(UUID.init(uuidString:)))
            guard !ids.isEmpty else { return false }
            let day = dayIndex < 0 ? nil : workspace.calendar.date(byAdding: .day, value: dayIndex, to: context.weekStart)
            return workspace.arrangeWeeklyTasks(ids, on: day, weekOf: context.weekStart) > 0
        } isTargeted: { targeted in targetedDay = targeted ? dayIndex : nil }
        .transaction { $0.animation = nil }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 10) {
            if selecting && !task.isClosed {
                Button { toggleSelection(task.id) } label: {
                    Image(systemName: selectedTasks.contains(task.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(WFColors.accent)
                }.accessibilityLabel("选择：" + task.title).workflowActionAnchor("weekly.select." + task.id.uuidString)
            }
            Button {
                if task.status == .completed { _ = workspace.restore(task.id) }
                else { _ = workspace.complete(task.id) }
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(task.status == .completed ? WFColors.accent : WFColors.secondaryText)
            }
            .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")
            Button { if selecting { toggleSelection(task.id) } else { workspace.select(task.id) } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(WFType.body).foregroundStyle(WFColors.text).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(task.list.name)
                        if let progress = workspace.subtaskProgress(for: task.id) { Text(progress) }
                    }
                    .font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            if !task.isClosed {
                BusinessMenu {
                    ForEach(0..<7, id: \.self) { offset in
                        let day = workspace.calendar.date(byAdding: .day, value: offset, to: context.weekStart)!
                        Button(dayLabel(day, index: offset)) { arrange(task, on: day) }
                    }
                    Divider()
                    Button("结转到下周") { _ = workspace.planTasks([task.id], weekOf: context.nextWeek) }
                } label: {
                    Text(task.schedule.dueAt.map { $0.formatted(.dateTime.month().day().locale(.appDate)) } ?? "安排日期")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .background(workspace.selectedTaskID == task.id || selectedTasks.contains(task.id) ? WFColors.selection : Color.clear)
        .draggable(task.id.uuidString) { TaskDragPreview(title: task.title) }
        .modifier(TaskReorderDragPolicy())
        .businessContextMenu {
            Button("打开任务") { workspace.select(task.id) }
            if !task.isClosed {
                Button("结转到下周") { _ = workspace.planTasks([task.id], weekOf: context.nextWeek) }
            }
        }
    }

    private var batchBar: some View {
        HStack {
            Button(selectedTasks.count == pending.count ? "取消全选" : "全选") {
                selectedTasks = selectedTasks.count == pending.count ? [] : Set(pending.map(\.id))
            }
            Text("已选 \(selectedTasks.count) 项").foregroundStyle(WFColors.secondaryText)
            Spacer()
            BusinessMenu("安排日期") {
                Button("待安排日期") { arrangeSelection(on: nil) }
                ForEach(0..<7, id: \.self) { index in
                    let day = workspace.calendar.date(byAdding: .day, value: index, to: context.weekStart)!
                    Button(dayLabel(day, index: index)) { arrangeSelection(on: day) }.workflowActionAnchor("weekly.day." + String(index))
                }
            }.disabled(selectedTasks.isEmpty).workflowActionAnchor("weekly.batch.schedule")
        }.buttonStyle(.borderless).font(WFType.supporting).padding(.horizontal, 24).padding(.vertical, 8)
    }
    private func toggleSelection(_ id: UUID) {
        if !selectedTasks.insert(id).inserted { selectedTasks.remove(id) }
    }
    private func arrangeSelection(on day: Date?) {
        _ = workspace.arrangeWeeklyTasks(selectedTasks, on: day, weekOf: context.weekStart)
        selectedTasks = []; selecting = false
    }
    private var taskPool: some View {
        VStack(spacing: 0) {
            DialogHeader(title: "加入这一周")
            VStack(alignment: .leading, spacing: 12) {
                TextField("搜索现有任务", text: $search).textFieldStyle(.roundedBorder)
                HStack {
                    Text("无日期任务先加入本周；有日期的任务保留星期和时刻。")
                        .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                    Spacer()
                    Button("全选结果") { selectedPool.formUnion(poolCandidates.map(\.id)) }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(poolCandidates) { task in
                            Button {
                                if !selectedPool.insert(task.id).inserted { selectedPool.remove(task.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedPool.contains(task.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(WFColors.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title).lineLimit(2)
                                        Text(task.list.name).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                                    }
                                    Spacer()
                                }.padding(.vertical, 9).contentShape(Rectangle())
                            }.buttonStyle(.plain).workflowActionAnchor("weekly.pool." + task.id.uuidString)
                            Divider()
                        }
                        if poolCandidates.isEmpty { Text("没有可加入的任务").foregroundStyle(WFColors.secondaryText).padding(24) }
                    }
                }
            }.padding(PopupMetrics.formInset)
            DialogFooter(primaryTitle: "加入本周", canSubmit: !selectedPool.isEmpty, cancelIdentifier: "weekly.pool.cancel", primaryIdentifier: "weekly.pool.submit",
                onCancel: { showsPool = false; selectedPool = [] }, onSubmit: {
                    _ = workspace.planTasks(selectedPool, weekOf: context.weekStart)
                    showsPool = false; selectedPool = []
                }) { Text("已选 \(selectedPool.count) 项") }
        }.frame(width: 540, height: 490)
    }

    private var poolCandidates: [Task] {
        workspace.tasksInActiveLists.filter {
            !$0.isClosed && !$0.isConverted && $0.deletedAt == nil && $0.skippedAt == nil
                && !projection.includes($0) && (context.listName == nil || $0.list.name == context.listName)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }.sorted {
            if ($0.schedule.dueAt == nil) != ($1.schedule.dueAt == nil) { return $0.schedule.dueAt == nil }
            return $0.createdAt > $1.createdAt
        }
    }

    private func dayLabel(_ day: Date, index: Int) -> String {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return names[index] + " · " + day.formatted(.dateTime.month().day().locale(.appDate))
    }

    private func arrange(_ task: Task, on day: Date) {
        _ = workspace.arrangeWeeklyTasks([task.id], on: day, weekOf: context.weekStart)
    }
}
