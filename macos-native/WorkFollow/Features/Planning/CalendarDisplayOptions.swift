import SwiftUI

struct CalendarDisplayOptions: View {
    @ObservedObject var settings: PlanningSettingsStore
    let lists: [String]
    let tags: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("日历显示设置").font(.title3.weight(.semibold))
            Form {
                Toggle("显示已完成任务", isOn: value(\.showCompleted))
                Toggle("显示未来重复周期", isOn: value(\.showFutureOccurrences))
                Toggle("显示子任务", isOn: value(\.showSubtasks))
                Toggle("显示安排任务面板", isOn: value(\.showArrangePane))
                Picker("每周开始于", selection: value(\.firstWeekday)) {
                    ForEach(1...7, id: \.self) { Text(CalendarWeekHeaderLabels.all[$0 - 1]).tag($0) }
                }
                Picker("任务颜色", selection: value(\.colorSource)) {
                    ForEach(CalendarColorSource.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Slider(value: value(\.hourHeight), in: CalendarDisplaySizing.hourHeightRange, step: 4) { Text("时间轴缩放") }
                Slider(value: value(\.allDayHeight), in: CalendarDisplaySizing.allDayHeightRange, step: 20) { Text("全天区域高度") }
                Section("清单范围 · 未选择时显示全部") {
                    ForEach(lists, id: \.self) { name in Toggle(name, isOn: selected(name, in: \.listNames)) }
                }
                if !tags.isEmpty {
                    Section("标签范围 · 未选择时显示全部") {
                        ForEach(tags, id: \.self) { tag in Toggle(tag, isOn: selected(tag, in: \.tagNames)) }
                    }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 440, height: 600)
    }
    private func value<T>(_ path: WritableKeyPath<CalendarPreferences, T>) -> Binding<T> {
        Binding(get: { settings.calendar[keyPath: path] }, set: { value in settings.updateCalendar { $0[keyPath: path] = value } })
    }
    private func selected(_ name: String, in path: WritableKeyPath<CalendarPreferences, [String]>) -> Binding<Bool> {
        Binding(get: { settings.calendar[keyPath: path].contains(name) }, set: { selected in settings.updateCalendar {
            $0[keyPath: path].removeAll { $0 == name }
            if selected { $0[keyPath: path].append(name) }
        } })
    }
}

struct CalendarDayAgenda: View {
    let day: Date
    let tasks: [Task]
    let calendar: Calendar
    let color: (UUID) -> Color
    let onOpen: (UUID) -> Void
    let onToggle: (UUID) -> Void
    let onCreate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(day.formatted(.dateTime.month().day().weekday())).font(WFType.sectionSemibold)
                Spacer()
                Button(action: onCreate) { Image(systemName: "plus") }.buttonStyle(.plain).help("新建任务")
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(tasks) { task in
                        HStack(spacing: 8) {
                            Button { onToggle(task.id) } label: {
                                TaskCompletionBox(size: 13, completed: task.status == .completed)
                            }.buttonStyle(.plain).accessibilityLabel("完成：\(task.title)")
                            Button { onOpen(task.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).lineLimit(2)
                                    Text(calendarClock(task.schedule.dueAt, hasTime: task.schedule.hasTime, calendar: calendar)
                                         ?? (PlanningProjection.spansMultipleDays(task, calendar: calendar) ? "跨天安排" : "全天"))
                                        .font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                        .padding(8).background(color(task.id).opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
            if tasks.isEmpty { Text("当天没有安排").foregroundStyle(WFColors.secondaryText) }
        }.padding(14).background(WFColors.content)
    }
}

struct CalendarArrangePane: View {
    let tasks: [Task]
    let onOpen: (UUID) -> Void
    let onArrange: (UUID) -> Void
    let anchorSink: PlanningAnchorRef
    @State private var anchor = PlanningAnchorRef()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("安排任务").font(WFType.sectionSemibold)
            Text("拖入日期或时间轴安排").font(WFType.caption).foregroundStyle(WFColors.secondaryText)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tasks) { task in
                        Button { anchorSink.rect = anchor.rect; onOpen(task.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(WFType.listMeta).lineLimit(2)
                                Text(task.list.name).font(WFType.caption).foregroundStyle(WFColors.secondaryText)
                            }
                            .padding(8)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .draggable(task.id.uuidString) {
                                Text(task.title).font(WFType.listMeta).lineLimit(2)
                                    .padding(10).frame(width: 200, alignment: .leading)
                                    .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
                                    .onAppear { NativeAcceptanceInteractionTrace.record("arrange.drag-preview") }
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("calendar.arrange-card.\(task.id.uuidString)")
                        .help("拖入日历安排，单击打开任务")
                        .contextMenu { Button("安排到选中日期") { onArrange(task.id) } }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            if tasks.isEmpty { Text("所有任务均已安排").font(WFType.caption).foregroundStyle(WFColors.secondaryText) }
        }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14).background(WFColors.calendarCanvas)
            .background(PlanningAnchorProbe(ref: anchor))
    }
}
