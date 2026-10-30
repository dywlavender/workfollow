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

    private enum DateField: Equatable { case start, end }
    @State private var activeDateField: DateField?
    @State private var dateFieldMonth = Date()

    private var matches: Int { tasks.filter { PlanningProjection.appearsOnCalendar($0) && value.rule.matches($0, now: now, calendar: calendar) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("象限名称与规则").font(.title3.weight(.semibold))
                Spacer()
                Text("匹配 \(matches) 项任务").foregroundStyle(WFColors.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.lg) {
                    WFFormSection {
                        WFFormRow("名称") {
                            TextField("名称", text: $value.title)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        WFFormRow("颜色") {
                            BusinessPicker("", selection: $value.colorIndex, options:
                                [BusinessChoice(0, "红色", symbol: "circle.fill", color: WFColors.danger),
                                 BusinessChoice(1, "黄色", symbol: "circle.fill", color: WFColors.warning),
                                 BusinessChoice(2, "蓝色", symbol: "circle.fill", color: WFColors.accent),
                                 BusinessChoice(3, "绿色", symbol: "circle.fill", color: .green)])
                                .labelsHidden()
                        }
                        WFFormRow("排序") {
                            BusinessPicker("", selection: $value.sort, options: MatrixSort.allCases.map { BusinessChoice($0, $0.title) })
                                .labelsHidden()
                        }
                        WFFormRow("分组", showsDivider: false) {
                            BusinessPicker("", selection: $value.grouping, options: MatrixGrouping.allCases.map { BusinessChoice($0, $0.title) })
                                .labelsHidden()
                        }
                    }
                    WFFormSection("优先级 · 未选择时不限") {
                        HStack(spacing: WFSpace.lg) {
                            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                                Toggle(priority.shortTitle, isOn: membership(priority, in: $value.rule.priorities))
                                    .toggleStyle(.checkbox)
                            }
                        }
                        .font(WFType.body)
                        .padding(.horizontal, WFSpace.md)
                    }
                    WFFormSection("日期条件") {
                        WFFormRow("判断依据") {
                            BusinessPicker("", selection: $value.rule.date.basis, options:
                                MatrixDateBasis.allCases.map { BusinessChoice($0, $0.title) })
                                .labelsHidden()
                        }
                        WFFormRow("范围") {
                            BusinessPicker("", selection: $value.rule.date.kind, options:
                                MatrixDateKind.allCases.map { BusinessChoice($0, $0.title) })
                                .labelsHidden()
                        }
                        if value.rule.date.kind == .nextDays || value.rule.date.kind == .afterDays {
                            WFFormRow("天数") {
                                Stepper("\(value.rule.date.days) 天", value: $value.rule.date.days, in: 0...365)
                            }
                        }
                        if value.rule.date.kind == .nextDays {
                            WFFormToggleRow("包含逾期任务", isOn: $value.rule.date.includeOverdue)
                        }
                        if value.rule.date.kind == .dateRange {
                            WFFormRow("开始") {
                                dateButton(.start, binding: $value.rule.date.rangeStart)
                            }
                            WFFormRow("结束") {
                                dateButton(.end, binding: $value.rule.date.rangeEnd)
                            }
                        }
                    }
                    WFFormSection("清单范围 · 未选择时不限") {
                        ForEach(lists, id: \.self) { name in
                            WFFormToggleRow(name, isOn: membership(name, in: $value.rule.listNames))
                        }
                    }
                    if !tags.isEmpty {
                        WFFormSection("标签条件 · 未选择时不限") {
                            ForEach(tags, id: \.self) { tag in
                                WFFormToggleRow(tag, isOn: membership(tag, in: $value.rule.tagNames))
                            }
                            WFFormToggleRow("同时包含所有选中标签", isOn: $value.rule.requiresAllTags, showsDivider: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .compactScrollbars()
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
        .workfollowPopupSurface(fallback: WFColors.canvas)
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

    private func dateButton(_ field: DateField, binding: Binding<Date?>) -> some View {
        Button {
            dateFieldMonth = binding.wrappedValue ?? now
            activeDateField = field
        } label: {
            HStack(spacing: 6) {
                Text(binding.wrappedValue.map {
                    $0.formatted(.dateTime.year().month().day().locale(.appDate))
                } ?? "选择日期")
                Spacer(minLength: 0)
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(WFColors.secondaryText)
            }
            .font(WFType.control)
            .foregroundStyle(binding.wrappedValue == nil ? WFColors.secondaryText : WFColors.text)
            .padding(.horizontal, 8)
            .frame(width: 190, height: 26)
            .background(WFColors.hover, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field == .start ? "开始日期" : "结束日期")
        .background {
            AnchoredPropertyPanel(isPresented: Binding(
                get: { activeDateField == field },
                set: { if !$0, activeDateField == field { activeDateField = nil } }),
                width: 260, placement: .vertical,
                focusPolicy: .preservePresenter, title: "日期") {
                    AppKitMonthGridView(calendar: calendar,
                        displayedMonth: $dateFieldMonth,
                        today: now,
                        selection: binding.wrappedValue,
                        minimumDate: field == .end ? value.rule.date.rangeStart : nil,
                        onSelect: { day in
                            binding.wrappedValue = day
                            activeDateField = nil
                        })
                        .frame(height: AppKitMonthGridView.contentHeight)
                        .overlay(alignment: .top) {
                            CalendarAnnotationOverlay(calendar: calendar,
                                displayedMonth: dateFieldMonth,
                                occurrenceDays: Set<Date>(), showBadges: true)
                                .allowsHitTesting(false)
                        }
                        .padding(14)
                }
        }
    }

    private func membership<T: Equatable>(_ item: T, in collection: Binding<[T]>) -> Binding<Bool> {
        Binding(get: { collection.wrappedValue.contains(item) }, set: { enabled in
            collection.wrappedValue.removeAll { $0 == item }
            if enabled { collection.wrappedValue.append(item) }
        })
    }
}
