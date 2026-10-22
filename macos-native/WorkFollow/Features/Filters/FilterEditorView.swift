import SwiftUI

/// Sheet editor for one saved filter (Wave 1 F5). `initial == nil` creates a
/// new filter; otherwise it edits that filter in place. Saving writes straight
/// into the store; an empty or duplicate name keeps the sheet open with an
/// inline error, mirroring the 清单 rename prompts.
struct FilterEditorView: View {
    @ObservedObject var store: FilterStore
    @ObservedObject var workspace: TaskWorkspaceModel
    let initial: SavedFilter?
    let onDismiss: () -> Void

    @State private var draft: FilterEditorDraft
    @State private var conflict = false
    @State private var modeIssue: String?

    init(store: FilterStore, workspace: TaskWorkspaceModel,
         initial: SavedFilter?, onDismiss: @escaping () -> Void) {
        self.store = store
        self.workspace = workspace
        self.initial = initial
        self.onDismiss = onDismiss
        _draft = State(initialValue: FilterEditorDraft(initial: initial))
    }

    private var listOptions: [String] { draft.listOptions(allListNames: workspace.availableListNames) }
    private var tagOptions: [String] { draft.tagOptions(tagNames: workspace.orderedTags.map(\.name)) }
    private var preview: FilterEditorPreview {
        FilterEditorPreview.project(tasks: workspace.tasksInActiveLists, filter: draft.filter,
                                    now: workspace.clock(), calendar: workspace.calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: WFSpace.lg) {
                DialogTitle(text: initial == nil ? "新建过滤器" : "编辑过滤器")
                TextField("过滤器名称", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("filter.editor.name")
                    .onChange(of: draft.name) { _, _ in conflict = false }
                Picker("筛选方式", selection: Binding(get: { draft.mode }, set: { mode in
                    if draft.switchMode(to: mode) { modeIssue = nil }
                    else { modeIssue = draft.basicConversionIssue }
                })) {
                    Text("普通").tag(FilterEditorMode.basic)
                    Text("高级").tag(FilterEditorMode.advanced)
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("filter.editor.mode")
                if modeIssue != nil, let issue = draft.basicConversionIssue {
                    Text(issue).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                }
            }
            .padding(WFSpace.xxl)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.xl) {
                    if draft.mode == .basic {
                    Text("不同条件需同时满足。清单、标签和优先级多选时匹配任一项，关键词需全部包含。不选择的条件不作限制。")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: WFSpace.sm) {
                        sectionLabel("清单")
                        chips(listOptions, symbol: "list.bullet", selection: draft.selectedLists,
                              onToggle: { draft.selectedLists = $0 })
                    }

                    VStack(alignment: .leading, spacing: WFSpace.sm) {
                        sectionLabel("标签")
                        if tagOptions.isEmpty {
                            emptyHint("先在侧栏新建标签")
                        } else {
                            chips(tagOptions, symbol: "tag", selection: draft.selectedTags,
                                  onToggle: { draft.selectedTags = $0 })
                        }
                    }

                    VStack(alignment: .leading, spacing: WFSpace.sm) {
                        sectionLabel("关键词")
                        TextField("在标题与正文中匹配，空格或逗号分隔", text: $draft.keywordText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("filter.editor.keywords")
                            .help("多个关键词需全部命中；匹配标题与正文，忽略大小写")
                    }

                    VStack(alignment: .leading, spacing: WFSpace.sm) {
                        sectionLabel("优先级")
                        HStack(spacing: WFSpace.sm) {
                            ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                                chip(Self.priorityTitle(priority), symbol: "flag",
                                     isOn: draft.selectedPriorities.contains(priority)) {
                                    if !draft.selectedPriorities.insert(priority).inserted {
                                        draft.selectedPriorities.remove(priority)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: WFSpace.sm) {
                        sectionLabel("日期范围")
                        Picker("日期范围", selection: $draft.dateRange) {
                            ForEach(SavedFilterDateRange.allCases, id: \.self) { range in
                                Text(range.title).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    } else {
                        advancedConditions
                    }

                    previewSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(WFSpace.xxl)
            }

            DialogFooter(canSubmit: !draft.trimmedName.isEmpty,
                         cancelIdentifier: "filter.editor.cancel", primaryIdentifier: "filter.editor.save",
                         onCancel: onDismiss, onSubmit: save) {
                if conflict {
                    Text("名称为空或已存在").foregroundStyle(WFColors.danger)
                } else {
                    Text("匹配 \(preview.matchingCount) 个未完成任务")
                        .foregroundStyle(WFColors.secondaryText)
                        .accessibilityIdentifier("filter.editor.preview.count")
                }
            }
        }
        .frame(width: 520, height: 600)
        .background(WFColors.content)
    }

    private func save() {
        let filter = draft.filter
        let saved = initial == nil ? store.add(filter) : store.update(filter)
        if saved {
            onDismiss()
        } else {
            conflict = true
        }
    }

    // MARK: Pieces

    private var advancedConditions: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            if let issue = draft.advancedEditingIssue {
                Text(issue).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            }
            if draft.canEditAdvancedRules {
                ForEach($draft.rules) { $rule in
                    AdvancedFilterRuleEditor(rule: $rule, workspace: workspace,
                        showsConnector: rule.id != draft.rules.first?.id,
                        listOptions: listOptions, tagOptions: tagOptions,
                        onRemove: { draft.removeRule(id: rule.id) })
                }
                BusinessMenu {
                    ForEach([FilterEditorRuleKind.lists, .tags, .priorities, .date, .keywords], id: \.self) { kind in
                        Button(kind.title) { draft.addRule(kind: kind) }
                    }
                } label: { Label("添加条件", systemImage: "plus") }
                    .fixedSize()
                    .accessibilityIdentifier("filter.editor.addRule")
            }
            VStack(alignment: .leading, spacing: WFSpace.xs) {
                Text("条件组合").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                Text(draft.expressionSummary).font(WFType.supporting)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filter.editor.expression")
            }
        }
    }

    private var previewSection: some View {
        let result = preview
        return VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text("任务预览")
                .font(WFType.section)
            if result.matchingCount == 0 {
                emptyHint("没有符合当前条件的未完成任务")
            } else {
                ForEach(result.tasks) { task in
                    HStack(spacing: WFSpace.sm) {
                        Image(systemName: "circle").foregroundStyle(WFColors.tertiaryText)
                        Text(task.title).lineLimit(1)
                    }
                    .font(WFType.supporting)
                    .help(task.title)
                }
                if result.matchingCount > result.tasks.count {
                    emptyHint("还有 \(result.matchingCount - result.tasks.count) 个匹配任务")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WFSpace.md)
        .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(WFType.section).foregroundStyle(WFColors.secondaryText)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
    }

    private func chips(_ options: [String], symbol: String, selection: Set<String>,
                       onToggle: @escaping (Set<String>) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: WFSpace.sm)],
                  alignment: .leading, spacing: WFSpace.sm) {
            ForEach(options, id: \.self) { option in
                chip(option, symbol: symbol, isOn: selection.contains(option)) {
                    var updated = selection
                    if !updated.insert(option).inserted { updated.remove(option) }
                    onToggle(updated)
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String, isOn: Bool,
                      onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: WFSpace.xs) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
            }
            .font(WFType.supporting)
            .foregroundStyle(isOn ? WFColors.accent : WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: 26)
            .background(isOn ? WFColors.selection : WFColors.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "已选择" : "未选择")
        .help(title)
    }

    private static func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
