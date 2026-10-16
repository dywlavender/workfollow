import SwiftUI

struct MatrixRuleEditor: View {
    @State var value: MatrixQuadrantConfiguration
    let tasks: [Task]
    let lists: [String]
    let tags: [String]
    let now: Date
    let calendar: Calendar
    let onSave: (MatrixQuadrantConfiguration) -> Void
    let onCancel: () -> Void

    private var matches: Int { tasks.filter { PlanningProjection.appearsOnCalendar($0) && value.rule.matches($0, now: now, calendar: calendar) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("象限名称与规则").font(.title3.weight(.semibold))
                Spacer()
                Text("匹配 \(matches) 项任务").foregroundStyle(WFColors.secondaryText)
            }
            ScrollView {
                Form {
                    TextField("名称", text: $value.title)
                    Picker("颜色", selection: $value.colorIndex) {
                        Text("红色").tag(0); Text("黄色").tag(1); Text("蓝色").tag(2); Text("绿色").tag(3)
                    }
                    Picker("排序", selection: $value.sort) { ForEach(MatrixSort.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("分组", selection: $value.grouping) { ForEach(MatrixGrouping.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Section("优先级 · 未选择时不限") {
                        HStack {
                            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                                Toggle(priority.shortTitle, isOn: membership(priority, in: $value.rule.priorities))
                                    .toggleStyle(.checkbox)
                            }
                        }
                    }
                    Section("日期条件") {
                        Picker("判断依据", selection: $value.rule.date.basis) {
                            ForEach(MatrixDateBasis.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("范围", selection: $value.rule.date.kind) {
                            ForEach(MatrixDateKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if value.rule.date.kind == .nextDays || value.rule.date.kind == .afterDays {
                            Stepper("\(value.rule.date.days) 天", value: $value.rule.date.days, in: 0...365)
                        }
                        if value.rule.date.kind == .nextDays { Toggle("包含逾期任务", isOn: $value.rule.date.includeOverdue) }
                        if value.rule.date.kind == .dateRange {
                            DatePicker("开始", selection: optionalDate($value.rule.date.rangeStart), displayedComponents: .date)
                            DatePicker("结束", selection: optionalDate($value.rule.date.rangeEnd), displayedComponents: .date)
                        }
                    }
                    Section("清单范围 · 未选择时不限") {
                        ForEach(lists, id: \.self) { name in Toggle(name, isOn: membership(name, in: $value.rule.listNames)) }
                    }
                    if !tags.isEmpty {
                        Section("标签条件 · 未选择时不限") {
                            ForEach(tags, id: \.self) { tag in Toggle(tag, isOn: membership(tag, in: $value.rule.tagNames)) }
                            Toggle("同时包含所有选中标签", isOn: $value.rule.requiresAllTags)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            Text("同一任务命中多条规则时，按 I → II → III → IV 归属；移动象限位置不改变匹配顺序。")
                .font(.caption).foregroundStyle(WFColors.secondaryText)
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") {
                    var result = value
                    result.title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || invalidRange)
            }
        }
        .padding(20)
        .frame(width: 520, height: 660)
        .onChange(of: value.rule.date.kind) { _, kind in
            if kind == .dateRange {
                if value.rule.date.rangeStart == nil { value.rule.date.rangeStart = calendar.startOfDay(for: now) }
                if value.rule.date.rangeEnd == nil { value.rule.date.rangeEnd = calendar.startOfDay(for: now) }
            }
        }
    }
    private var invalidRange: Bool {
        value.rule.date.kind == .dateRange && (value.rule.date.rangeEnd ?? now) < (value.rule.date.rangeStart ?? now)
    }
    private func membership<T: Equatable>(_ item: T, in collection: Binding<[T]>) -> Binding<Bool> {
        Binding(get: { collection.wrappedValue.contains(item) }, set: { enabled in
            collection.wrappedValue.removeAll { $0 == item }
            if enabled { collection.wrappedValue.append(item) }
        })
    }
    private func optionalDate(_ binding: Binding<Date?>) -> Binding<Date> {
        Binding(get: { binding.wrappedValue ?? now }, set: { binding.wrappedValue = $0 })
    }
}

struct MatrixDropConfirmation: View {
    let proposal: MatrixDropProposal
    let targetTitle: String
    let onChoose: (String?, String?) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("移入“\(targetTitle)”").font(.title3.weight(.semibold))
            ForEach(proposal.changes, id: \.self) { Text($0) }
            if proposal.listChoices.count > 1 {
                Picker("清单", selection: Binding(get: { proposal.list?.name ?? "" }, set: { onChoose($0, proposal.tags?.last) })) {
                    ForEach(proposal.listChoices, id: \.self) { Text($0).tag($0) }
                }
            }
            if proposal.tagChoices.count > 1 {
                Picker("添加标签", selection: Binding(get: {
                    proposal.tagChoices.first { proposal.tags?.contains($0) == true } ?? proposal.tagChoices[0]
                }, set: { onChoose(proposal.list?.name, $0) })) {
                    ForEach(proposal.tagChoices, id: \.self) { Text($0).tag($0) }
                }
            }
            if let conflict = proposal.conflict { Text(conflict).foregroundStyle(WFColors.danger) }
            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("移动", action: onCommit).keyboardShortcut(.defaultAction).disabled(!proposal.canCommit)
            }
        }
        .padding(24).frame(width: 410)
    }
}
