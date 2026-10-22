import SwiftUI

struct WeeklyPlanningWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var context: WeeklyPlanningContext
    @EnvironmentObject private var environment: AppEnvironment
    @State private var title = ""
    @State private var showsPool = false
    @State private var search = ""
    @State private var showsCompleted = false
    @FocusState private var captureFocused: Bool

    private var projection: WeeklyPlanProjection {
        WeeklyPlanProjection(weekStart: context.weekStart, calendar: workspace.calendar)
    }
    private var tasks: [Task] { projection.tasks(from: workspace.tasksInActiveLists, listName: context.listName) }
    private var pending: [Task] { tasks.filter { !$0.isClosed } }
    private var completed: [Task] { tasks.filter { $0.status == .completed } }

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
            workspace.captureWeekPlan(weekOf: context.weekStart)
        }
        .onChange(of: context.listName) { _, _ in workspace.select(nil) }
        .sheet(isPresented: $showsPool) { taskPool }
    }

    private var planColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("周计划").font(WFType.detailTitle)
                Spacer()
                Button { showsPool = true } label: { Label("加入任务", systemImage: "plus") }
                Button(context.isCurrent ? "回顾本周" : "回顾这一周") { environment.navigation.destination = .summary }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.borderless).padding(.horizontal, 24).frame(height: 52)
            Divider()
            WeeklyPlanningToolbar(context: context, listNames: workspace.availableListNames)
            HStack(spacing: 16) {
                Text("待推进 \(pending.count)")
                Text("已完成 \(completed.count)")
                Spacer()
                Text("周一至周日").foregroundStyle(WFColors.tertiaryText)
            }
            .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            .padding(.horizontal, 24).padding(.bottom, 12)
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
                    if !unscheduled.isEmpty { taskSection("待安排日期", tasks: unscheduled) }
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let day = workspace.calendar.date(byAdding: .day, value: dayIndex, to: context.weekStart)!
                        let dayTasks = pending.filter { task in
                            guard let due = task.schedule.dueAt else { return false }
                            let visibleDay = max(workspace.calendar.startOfDay(for: due), context.weekStart)
                            return workspace.calendar.isDate(visibleDay, inSameDayAs: day)
                        }
                        if !dayTasks.isEmpty { taskSection(dayLabel(day, index: dayIndex), tasks: dayTasks) }
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
            TextField("添加任务，暂不安排日期", text: $title)
                .textFieldStyle(.plain).focused($captureFocused)
                .onSubmit {
                    if workspace.createWeeklyTask(title: title, list: context.listName ?? TaskList.inbox.name,
                                                  weekOf: context.weekStart) != nil {
                        title = ""; captureFocused = true
                    }
                }
        }
        .font(WFType.body).padding(12)
        .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 24).padding(.bottom, 14)
    }

    private func taskSection(_ label: String, tasks: [Task]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(WFType.section)
                Text("\(tasks.count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 5)
            ForEach(tasks) { task in taskRow(task) }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 10) {
            Button {
                if task.status == .completed { _ = workspace.restore(task.id) }
                else { _ = workspace.complete(task.id) }
            } label: {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(task.status == .completed ? WFColors.accent : WFColors.secondaryText)
            }
            .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")
            Button { workspace.select(task.id) } label: {
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
        .background(workspace.selectedTaskID == task.id ? WFColors.selection : Color.clear)
        .businessContextMenu {
            Button("打开任务") { workspace.select(task.id) }
            if !task.isClosed {
                Button("结转到下周") { _ = workspace.planTasks([task.id], weekOf: context.nextWeek) }
            }
        }
    }

    private var taskPool: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("加入这一周").font(WFType.detailTitle)
                Spacer()
                Button("完成") { showsPool = false }
            }
            TextField("搜索现有任务", text: $search).textFieldStyle(.roundedBorder)
            Text("无日期任务保留为待安排；有日期的任务平移到这一周，并同步调整提醒。")
                .font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(poolCandidates) { task in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).lineLimit(2)
                                Text(task.list.name).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                            }
                            Spacer()
                            Button("加入") { _ = workspace.planTasks([task.id], weekOf: context.weekStart) }
                        }
                        .padding(.vertical, 9)
                        Divider()
                    }
                    if poolCandidates.isEmpty { Text("没有可加入的任务").foregroundStyle(WFColors.secondaryText).padding(24) }
                }
            }
        }
        .padding(24).frame(width: 540, height: 490)
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
        var schedule = task.schedule
        let due = task.schedule.dueAt ?? day
        let shifted = TaskDateDraft.movingDay(due, to: day, calendar: workspace.calendar)
        if let end = schedule.dueEndAt { schedule.dueEndAt = end.addingTimeInterval(shifted.timeIntervalSince(due)) }
        schedule.dueAt = shifted
        _ = workspace.updateAttributes(task.id, schedule: schedule)
    }
}
