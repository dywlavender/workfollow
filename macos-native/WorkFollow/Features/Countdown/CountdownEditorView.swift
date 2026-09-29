import SwiftUI

/// 固定色板；与 `CountdownWorkspaceView.swift` 的同名调色板必须同序同值
/// （Domain 只存下标，颜色映射在界面侧）。
private let countdownEditorPalette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

private func countdownEditorColor(_ index: Int) -> Color {
    let count = max(countdownEditorPalette.count, 1)
    return countdownEditorPalette[((index % count) + count) % count]
}

/// 新建 / 编辑倒数纪念日。布局照参考图的「添加」面板：图标 + 名称输入框一行，
/// 其下 日期 / 提醒 / 重复 / 类型 / 显示 五行（生日多一行「显示岁数」），
/// 底部 取消 / 添加。
///
/// 行内编辑器用**就地展开**而不是浮层：浮层套在 sheet 里在 macOS 上焦点容易丢，
/// 而本项目的日程浮层（`TaskDatePopoverV2`）本来也是「行 + 就地展开」这一套。
struct CountdownEditorView: View {
    @ObservedObject var store: CountdownStore
    /// nil = 新建。
    let original: CountdownEvent?

    @Environment(\.dismiss) private var dismiss

    /// 一次只展开一行。
    private enum Row: String, Identifiable {
        case date, reminder, recurrence, kind, display
        var id: String { rawValue }
    }

    @State private var kind: CountdownKind
    @State private var name: String
    @State private var symbol: String
    @State private var colorIndex: Int
    @State private var pickedDate: Date?
    @State private var pickedFestival: CountdownFestival.Option?
    @State private var repeatSelection: CountdownRepeat
    @State private var reminders: Set<Int>
    @State private var showsInSmartList: Bool
    @State private var showsAge: Bool
    @State private var note: String
    @State private var noteExpanded: Bool
    @State private var openRow: Row?

    private var calendar: Calendar { .current }
    private var isNew: Bool { original == nil }

    // 参考面板实测（1512pt 窗口下的原版「添加」面板）：
    // 面板 460×448，左右内边距 39，行高 34，行间距 10，标签列宽 54，
    // 行内控件 322×34，底部按钮 102×32。这里按同一组数排，别凭感觉调。
    private static let panelWidth: CGFloat = 460
    private static let inset: CGFloat = 40
    private static let labelWidth: CGFloat = 54
    private static let rowHeight: CGFloat = 34
    private static let rowGap: CGFloat = 10
    private static let buttonWidth: CGFloat = 102

    init(store: CountdownStore, original: CountdownEvent?, defaultKind: CountdownKind = .anniversary) {
        self.store = store
        self.original = original
        let kind = original?.kind ?? defaultKind
        _kind = State(initialValue: kind)
        _name = State(initialValue: original?.name ?? "")
        _symbol = State(initialValue: original?.safeSymbol ?? kind.defaultSymbol)
        _colorIndex = State(initialValue: original?.colorIndex ?? kind.defaultColorIndex)
        // 编辑时把规则摊回「一个具体日期」：重复规则取它的下一次发生日，
        // 这样切换类型或改重复都不会把已选的日期丢掉。**生日例外**——它必须落回
        // 出生那天，否则出生年在「编辑一次再保存」的往返里就被磨掉了，
        // 「显示岁数」也就永远算不出来。
        //
        // 新建时**故意留空**：参考图的「日期」行是灰色的「选择日期」占位，
        // 「添加」按钮同时是禁用的——即日期属于必填，但初始不预设。
        let calendar = Calendar.current
        let today = Date()
        _pickedDate = State(initialValue: original.map { event -> Date in
            if case .birthday(let month, let day, let year) = event.rule,
               let birth = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                return birth
            }
            return event.occurrence(onOrAfter: today, calendar: calendar)
        })
        _pickedFestival = State(initialValue: original.flatMap {
            $0.kind == .festival ? CountdownFestival.name(for: $0.rule).flatMap { name in
                CountdownFestival.all.first { $0.name == name }
            } : nil
        })
        _repeatSelection = State(initialValue: original?.repeatValue ?? kind.defaultRepeat)
        _reminders = State(initialValue: Set(original?.reminderOffsets
            ?? CountdownEvent.defaultReminderOffsets))
        _showsInSmartList = State(initialValue: original?.showsInSmartList ?? true)
        _showsAge = State(initialValue: original?.showsAge ?? false)
        _note = State(initialValue: original?.note ?? "")
        _noteExpanded = State(initialValue: !(original?.note ?? "").isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加" : "编辑")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 30)
                .padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    nameRow
                    if noteExpanded { noteField }
                    dateRow
                    if openRow == .date { dateEditor }
                    reminderRow
                    if openRow == .reminder { reminderEditor }
                    repeatRow
                    if openRow == .recurrence { repeatEditor }
                    kindRow
                    if openRow == .kind { kindEditor }
                    displayRow
                    if openRow == .display { displayEditor }
                    if kind.hasAgeOption { ageRow }
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, WFSpace.xxl)
            }
            .frame(maxHeight: 380)
            Divider()
            footer
        }
        .frame(width: Self.panelWidth)
        .background(WFColors.canvas)
    }

    // MARK: 名称

    private var nameRow: some View {
        HStack(spacing: WFSpace.lg) {
            ZStack {
                Circle().fill(countdownEditorColor(colorIndex))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            TextField(kind.namePlaceholder, text: $name)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .onSubmit { if canSubmit { submit() } }

            // 参考图里输入框右端有个小方块图标按钮。它对应的行为在图上不可见，
            // 这里接成「备注」的展开开关——否则整页没有写备注的入口。
            Button {
                noteExpanded.toggle()
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 13))
                    .foregroundStyle(noteExpanded ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("备注")
            .accessibilityLabel("备注")
        }
    }

    private var noteField: some View {
        TextField("备注", text: $note, axis: .vertical)
            .textFieldStyle(.plain)
            .font(WFType.supporting)
            .lineLimit(2...4)
            .padding(WFSpace.sm)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .overlay {
                RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
            }
    }

    // MARK: 属性行

    private func propertyRow(_ row: Row, label: String, value: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: WFSpace.inline) {
            Text(label)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: Self.labelWidth, alignment: .leading)
            Button {
                openRow = openRow == row ? nil : row
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Text(value)
                        .font(WFType.supporting)
                        .foregroundStyle(isPlaceholder ? WFColors.tertiaryText : WFColors.text)
                        .lineLimit(1)
                    Spacer(minLength: WFSpace.xs)
                    Image(systemName: openRow == row ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .frame(maxWidth: .infinity)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(WFColors.border)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label)：\(value)")
        }
    }

    private var dateRow: some View {
        propertyRow(.date, label: "日期",
                    value: dateText ?? "选择日期", isPlaceholder: dateText == nil)
    }

    @ViewBuilder
    private var dateEditor: some View {
        if kind.usesFestivalCatalog {
            // 节日走目录：选项自带农历/公历规则，不需要用户自己挑日子。
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CountdownFestival.all) { option in
                        optionRow(option.name, checked: pickedFestival?.name == option.name) {
                            pickedFestival = option
                            // 名称还空着就顺手填上节日名：选了「春节」再手打一遍
                            // 「春节」是白费一次输入。只在空的时候填，不会覆盖用户写的。
                            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = option.name
                            }
                            openRow = nil
                        }
                    }
                }
            }
            .frame(height: 180)
        } else {
            // 图形日历的绑定要有值：还没选日期时以今天为默认落点，
            // 用户一动它就写进 `pickedDate`（不动则保持「未选」）。
            DatePicker("", selection: Binding(get: { pickedDate ?? Date() },
                                             set: { pickedDate = $0 }),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, .appDate)
                .frame(maxWidth: .infinity)
        }
    }

    private var reminderRow: some View {
        propertyRow(.reminder, label: "提醒",
                    value: CountdownEvent.reminderText(Array(reminders)) ?? "选择提醒",
                    isPlaceholder: reminders.isEmpty)
    }

    private var reminderEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownEvent.reminderChoices, id: \.self) { minutes in
                optionRow(CountdownEvent.reminderLabel(minutes), checked: reminders.contains(minutes)) {
                    if !reminders.insert(minutes).inserted { reminders.remove(minutes) }
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var repeatRow: some View {
        propertyRow(.recurrence, label: "重复", value: repeatSelection.title, isPlaceholder: false)
    }

    private var repeatEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownRepeat.allCases) { option in
                optionRow(option.title, checked: repeatSelection == option) {
                    repeatSelection = option
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var kindRow: some View {
        propertyRow(.kind, label: "类型", value: kind.title, isPlaceholder: false)
    }

    private var kindEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownKind.allCases) { option in
                optionRow(option.title, checked: kind == option) {
                    applyKind(option)
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayRow: some View {
        propertyRow(.display, label: "显示",
                    value: showsInSmartList ? "在智能清单中当天显示" : "不在智能清单中显示",
                    isPlaceholder: false)
    }

    private var displayEditor: some View {
        VStack(spacing: 0) {
            optionRow("在智能清单中当天显示", checked: showsInSmartList) {
                showsInSmartList = true
                openRow = nil
            }
            optionRow("不在智能清单中显示", checked: !showsInSmartList) {
                showsInSmartList = false
                openRow = nil
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 「显示岁数」这一行参考图里是**开关在左、文字在右**（和上面几行
    /// 「标签在左、控件在右」正好相反），而且开关落在标签列上、不再缩进。
    private var ageRow: some View {
        HStack(spacing: WFSpace.sm) {
            Toggle("", isOn: $showsAge)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("显示岁数")
            Text("显示岁数")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
    }

    private func optionRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WFSpace.sm) {
                Text(title).font(WFType.supporting).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: Self.rowHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: Self.rowGap) {
            Spacer()
            // 宽度得给到 label 上：`.frame(minWidth:)` 加在 Button 外面只撑布局框，
            // 撑不开 `.bordered` 自己画的那颗胶囊（实测仍是 54 宽）。
            Button { dismiss() } label: {
                Text("取消").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button { submit() } label: {
                Text(isNew ? "添加" : "保存").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 32)
    }

    // MARK: 派生

    /// 「日期」行显示的文本。
    private var dateText: String? {
        if kind.usesFestivalCatalog { return pickedFestival?.name }
        return pickedDate.map { CountdownEvent.solarText($0, calendar: calendar) }
    }

    /// 提交时的规则。节日取目录里的规则；其余按「重复」把已选日期转成
    /// 单次或每年。目录里认不出的农历规则（历史数据）原样保留，
    /// 免得因为编辑器不认得就把日期丢了。
    private var resolvedRule: CountdownRule? {
        if kind.usesFestivalCatalog {
            if let pickedFestival { return pickedFestival.rule }
            if let rule = original?.rule, rule.isRepeating, CountdownFestival.name(for: rule) == nil {
                return rule
            }
            return nil
        }
        guard let pickedDate else { return nil }
        switch repeatSelection {
        case .never:
            return .once(pickedDate)
        case .yearly:
            let parts = calendar.dateComponents([.year, .month, .day], from: pickedDate)
            guard let month = parts.month, let day = parts.day else { return .once(pickedDate) }
            // 生日要把出生年一起带上，岁数才算得出来。
            if kind == .birthday, let year = parts.year {
                return .birthday(month: month, day: day, birthYear: year)
            }
            return .solarYearly(month: month, day: day)
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedRule != nil
    }

    /// 切类型：换图标与颜色，并把「重复」带回该类型的默认值。
    /// 日期一律清空——参考图里换完类型「日期」仍是「选择日期」，
    /// 而且公历日期与农历节日本来就不是同一套落点，留着上一个只会误导。
    private func applyKind(_ next: CountdownKind) {
        kind = next
        symbol = next.defaultSymbol
        colorIndex = next.defaultColorIndex
        repeatSelection = next.defaultRepeat
        pickedFestival = nil
        pickedDate = nil
    }

    private func submit() {
        guard let rule = resolvedRule else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var original {
            original.name = trimmed
            original.kind = kind
            original.rule = rule
            original.symbol = symbol
            original.colorIndex = colorIndex
            original.reminderOffsets = Array(reminders)
            original.showsInSmartList = showsInSmartList
            original.showsAge = showsAge
            original.note = note
            store.update(original)
        } else {
            store.add(name: trimmed, kind: kind, rule: rule, symbol: symbol, colorIndex: colorIndex,
                      reminderOffsets: Array(reminders), showsInSmartList: showsInSmartList,
                      showsAge: showsAge, note: note)
        }
        dismiss()
    }
}

// MARK: - 样式

/// 卡片菜单「样式」：只改符号与颜色，点即生效。参考图里这一项的界面不可见，
/// 这里是自定的最小实现（顺带补上了添加面板里那个改不了图标的缺口）。
struct CountdownStyleView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var symbol: String
    @State private var colorIndex: Int

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _symbol = State(initialValue: event.safeSymbol)
        _colorIndex = State(initialValue: event.colorIndex)
    }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: WFSpace.sm), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            Text("样式").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            VStack(alignment: .leading, spacing: WFSpace.md) {
                HStack(spacing: WFSpace.sm) {
                    ZStack {
                        Circle().fill(countdownEditorColor(colorIndex))
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    Text(event.displayName).font(WFType.body).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text("颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                HStack(spacing: WFSpace.sm) {
                    ForEach(0..<CountdownEvent.paletteSize, id: \.self) { index in
                        Button {
                            colorIndex = index
                            apply()
                        } label: {
                            ZStack {
                                Circle().fill(countdownEditorColor(index)).frame(width: 22, height: 22)
                                if index == colorIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("颜色 \(index + 1)")
                    }
                    Spacer(minLength: 0)
                }
                Text("图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                LazyVGrid(columns: columns, spacing: WFSpace.sm) {
                    ForEach(CountdownEvent.symbolOptions, id: \.self) { option in
                        Button {
                            symbol = option
                            apply()
                        } label: {
                            Image(systemName: option)
                                .font(.system(size: 14))
                                .foregroundStyle(option == symbol ? WFColors.accent : WFColors.secondaryText)
                                .frame(width: 34, height: 30)
                                .background(option == symbol ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                    }
                }
            }
            .padding(WFSpace.xl)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 320)
        .background(WFColors.canvas)
    }

    private func apply() {
        store.setStyle(event.id, symbol: symbol, colorIndex: colorIndex)
    }
}

// MARK: - 备注

/// 卡片菜单「备注」。
struct CountdownNoteView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _note = State(initialValue: event.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("备注").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            TextField("写点什么…", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .lineLimit(6...12)
                .padding(WFSpace.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .padding(WFSpace.xl)
            Divider()
            HStack(spacing: WFSpace.sm) {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.bordered)
                Button("保存") {
                    store.setNote(event.id, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 360)
        .background(WFColors.canvas)
    }
}

// MARK: - 已归档

/// 页头「更多 → 已归档」：恢复或彻底删除。
struct ArchivedCountdownsView: View {
    @ObservedObject var store: CountdownStore

    @Environment(\.dismiss) private var dismiss
    @State private var today = Date()

    var body: some View {
        VStack(spacing: 0) {
            // 参照物语言包：`archived_countdowns` = 已归档倒数纪念日
            Text("已归档倒数纪念日").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            if store.archivedEvents.isEmpty {
                VStack(spacing: WFSpace.sm) {
                    // `no_archived_countdowns_dida` = 还没有已归档的纪念日
                    Text("还没有已归档的纪念日").font(WFType.body)
                }
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.archivedEvents) { event in
                            row(event)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 380)
        .background(WFColors.canvas)
        .onAppear { today = Date() }
    }

    private func row(_ event: CountdownEvent) -> some View {
        let projection = event.projection(asOf: today)
        return HStack(spacing: WFSpace.sm) {
            ZStack {
                Circle().fill(countdownEditorColor(event.colorIndex))
                Image(systemName: event.safeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayName).font(WFType.listTitle).lineLimit(1)
                Text(projection.caption).font(WFType.caption)
                    .foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: WFSpace.sm)
            Button("恢复") { store.restore(event.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("删除") {
                if TaskNamePrompt.confirm("删除“\(event.displayName)”？", message: "删除后无法恢复。") {
                    _ = store.hardDelete(event.id)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, WFSpace.lg)
        .padding(.vertical, WFSpace.sm)
    }
}
