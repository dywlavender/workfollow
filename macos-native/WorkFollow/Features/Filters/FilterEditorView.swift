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

    private static let priorityOrder: [TaskPriority] = [.none, .low, .medium, .high]

    @State private var name: String
    @State private var selectedLists: Set<String>
    @State private var selectedTags: Set<String>
    @State private var selectedPriorities: Set<TaskPriority>
    @State private var dateRange: SavedFilterDateRange
    /// 关键词输入原文（空格 / 逗号分隔），保存时解析成 token 列表。
    @State private var keywordText: String
    @State private var conflict = false

    init(store: FilterStore, workspace: TaskWorkspaceModel,
         initial: SavedFilter?, onDismiss: @escaping () -> Void) {
        self.store = store
        self.workspace = workspace
        self.initial = initial
        self.onDismiss = onDismiss
        _name = State(initialValue: initial?.name ?? "")
        _selectedLists = State(initialValue: Set(initial?.listNames ?? []))
        _selectedTags = State(initialValue: Set(initial?.tags ?? []))
        _selectedPriorities = State(initialValue: Set(initial?.priorities ?? []))
        _dateRange = State(initialValue: initial?.dateRange ?? .any)
        _keywordText = State(initialValue: (initial?.keywords ?? []).joined(separator: " "))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // 仿 TaskTagPickerPopover：候选 = 现有全集 ∪ 已选集合，已选项不因标签被移除而消失。
    private var listOptions: [String] { Array(Set(workspace.listNames).union(selectedLists)).sorted() }
    private var tagOptions: [String] { Array(Set(workspace.tagNames).union(selectedTags)).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.lg) {
            Text(initial == nil ? "新建过滤器" : "编辑过滤器").font(.title2.bold())
            TextField("过滤器名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .onChange(of: name) { _, _ in conflict = false }

            sectionLabel("清单")
            if listOptions.isEmpty {
                emptyHint("还没有清单")
            } else {
                chips(listOptions, symbol: "list.bullet", selection: selectedLists,
                      onToggle: { selectedLists = $0 })
            }

            sectionLabel("标签")
            if tagOptions.isEmpty {
                emptyHint("在任务属性中添加标签")
            } else {
                ScrollView {
                    chips(tagOptions, symbol: "tag", selection: selectedTags,
                          onToggle: { selectedTags = $0 })
                }
                .frame(maxHeight: 150)
            }

            sectionLabel("关键词")
            TextField("在标题与正文中匹配，空格或逗号分隔", text: $keywordText)
                .textFieldStyle(.roundedBorder)
                .help("多个关键词需全部命中（AND）；匹配标题与正文纯文本，忽略大小写")

            sectionLabel("优先级")
            HStack(spacing: WFSpace.sm) {
                ForEach(Self.priorityOrder, id: \.self) { priority in
                    chip(Self.priorityTitle(priority), symbol: "flag",
                         isOn: selectedPriorities.contains(priority)) {
                        if !selectedPriorities.insert(priority).inserted {
                            selectedPriorities.remove(priority)
                        }
                    }
                }
            }

            sectionLabel("日期范围")
            Picker("日期范围", selection: $dateRange) {
                ForEach(SavedFilterDateRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                if conflict {
                    Text("名称为空或已存在")
                        .font(WFType.supporting)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("取消", action: onDismiss).keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(WFSpace.xxl)
        .frame(width: 400)
    }

    private func save() {
        var filter = initial ?? SavedFilter(name: trimmedName)
        filter.name = trimmedName
        filter.listNames = selectedLists.sorted()
        filter.tags = selectedTags.sorted()
        filter.priorities = Self.priorityOrder.filter { selectedPriorities.contains($0) }
        filter.dateRange = dateRange
        filter.keywords = SavedFilter.parseKeywords(keywordText)
        let saved = initial == nil ? store.add(filter) : store.update(filter)
        if saved {
            onDismiss()
        } else {
            conflict = true
        }
    }

    // MARK: Pieces

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
