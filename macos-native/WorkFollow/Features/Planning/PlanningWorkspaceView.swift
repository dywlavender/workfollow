import SwiftUI

struct PlanningWorkspaceView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let matrix: Bool
    @State private var anchor = Date()
    @State private var week = false
    @State private var showCompleted = true
    private let titles = ["Ⅰ 重要且紧急", "Ⅱ 重要不紧急", "Ⅲ 不重要但紧急", "Ⅳ 不重要不紧急"]
    private let colors: [Color] = [.red, .orange, .blue, .green]
    private var tasks: [Task] {
        workspace.allTasks.filter { $0.deletedAt == nil && (showCompleted || $0.status == .active) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(matrix ? "四象限" : "日历").font(WFType.pageTitle)
                Spacer()
                Toggle("显示已完成", isOn: $showCompleted).toggleStyle(.checkbox)
                if !matrix {
                    Picker("视图", selection: $week) { Text("月").tag(false); Text("周").tag(true) }
                        .pickerStyle(.segmented).frame(width: 100)
                }
            }
            if matrix { matrixBoard } else { calendarBoard }
        }.padding(20)
            .sheet(isPresented: Binding(get: { workspace.selectedTask != nil }, set: { if !$0 { workspace.select(nil) } })) {
                TaskInspectorShell(workspace: workspace, showBack: true)
                    .frame(minWidth: 340, idealWidth: 560, minHeight: 460, idealHeight: 620)
            }
    }

    private var matrixBoard: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width < 650 ? 1 : 2), spacing: 12) {
                    ForEach(0..<4) { quadrant in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(titles[quadrant]).foregroundStyle(colors[quadrant]).font(WFType.section)
                                Spacer()
                                Button { addToQuadrant(quadrant) } label: { Image(systemName: "plus") }
                            }
                            ScrollView {
                                let values = tasks.filter { PlanningProjection.quadrant($0, now: Date()) == quadrant }
                                let names = Array(Set(values.filter { $0.status == .active }.map { $0.list.name })).sorted()
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(names, id: \.self) { name in
                                        DisclosureGroup(name) {
                                            ForEach(values.filter { $0.status == .active && $0.list.name == name }) { task in taskRow(task) }
                                        }
                                    }
                                    let completed = values.filter { $0.status == .completed }
                                    if !completed.isEmpty {
                                        DisclosureGroup("已完成 \(completed.count)") {
                                            ForEach(completed) { task in taskRow(task) }
                                        }
                                    }
                                    if values.isEmpty { Text("暂无任务").foregroundStyle(.tertiary) }
                                }
                            }
                        }.padding(16).frame(height: max(240, (geometry.size.height - 44) / 2))
                            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 12))
                            .dropDestination(for: String.self) { strings, _ in
                                guard let id = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
                                moveToQuadrant(id, quadrant)
                                return true
                            }
                    }
                }
            }.background(WFColors.canvas)
        }
    }

    private var calendarBoard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Text(anchor.formatted(.dateTime.year().month(.wide)))
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Button("今天") { anchor = Date() }
            }
            ScrollView([.horizontal, .vertical]) {
                let days = week ? PlanningProjection.weekDays(containing: anchor) : PlanningProjection.monthDays(containing: anchor)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 120), spacing: 1), count: 7), spacing: 1) {
                    ForEach(days.prefix(7), id: \.self) { day in Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption).padding(8) }
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(day.formatted(.dateTime.day())).foregroundStyle(Calendar.current.isDateInToday(day) ? WFColors.accent : WFColors.text)
                                Spacer()
                                Button { addOnDate(day) } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                            }
                            ForEach(PlanningProjection.tasks(on: day, from: tasks)) { task in taskRow(task) }
                            Spacer(minLength: 0)
                        }.padding(8).frame(minWidth: 120, maxWidth: .infinity, minHeight: week ? 480 : 110, alignment: .topLeading)
                            .background(WFColors.content)
                            .dropDestination(for: String.self) { strings, _ in
                                guard let id = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
                                _ = workspace.setDueDate(id, day)
                                return true
                            }
                    }
                }.frame(minWidth: 900).background(WFColors.border)
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 6) {
            Button { _ = workspace.changeStatus(task) } label: {
                Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
            }.buttonStyle(.plain)
            Button { workspace.select(task.id) } label: {
                Text(task.title.isEmpty ? "未命名任务" : task.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.font(.callout).foregroundStyle(task.status == .completed ? WFColors.tertiaryText : WFColors.text)
            .padding(.vertical, 5).draggable(task.id.uuidString)
    }

    private func addOnDate(_ date: Date) {
        guard let id = workspace.createTask(title: "", in: .inbox).taskID else { return }
        _ = workspace.setDueDate(id, date)
        workspace.select(id)
    }
    private func addToQuadrant(_ quadrant: Int) {
        guard let id = workspace.createTask(title: "", in: .inbox).taskID else { return }
        moveToQuadrant(id, quadrant)
        workspace.select(id)
    }
    private func moveToQuadrant(_ id: UUID, _ quadrant: Int) {
        _ = workspace.setPriority(id, quadrant < 2 ? .high : .none)
        _ = workspace.setDueDate(id, quadrant == 0 || quadrant == 2 ? workspace.dateFromToday(0) : workspace.dateFromToday(4))
    }
    private func step(_ amount: Int) {
        anchor = Calendar.current.date(byAdding: week ? .weekOfYear : .month, value: amount, to: anchor) ?? anchor
    }
}
