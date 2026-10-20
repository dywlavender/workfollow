import SwiftUI

struct AdvancedFilterRuleEditor: View {
    @Binding var rule: FilterEditorRule
    @ObservedObject var workspace: TaskWorkspaceModel
    let showsConnector: Bool
    let listOptions: [String]
    let tagOptions: [String]
    let onRemove: () -> Void
    @State private var showingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            if showsConnector {
                Picker("条件关系", selection: $rule.connector) {
                    Text("且").tag(FilterRuleConnector.and)
                    Text("或").tag(FilterRuleConnector.or)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 96)
                .accessibilityLabel("与前面条件的关系")
            }
            VStack(alignment: .leading, spacing: WFSpace.sm) {
                HStack {
                    Picker("条件属性", selection: Binding(get: { rule.kind }, set: { kind in
                        guard kind != rule.kind else { return }
                        rule = FilterEditorRule(id: rule.id, connector: rule.connector, kind: kind)
                    })) {
                        ForEach([FilterEditorRuleKind.lists, .tags, .priorities, .date, .keywords], id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .labelsHidden().frame(width: 116)
                    Spacer(minLength: 0)
                    Button(action: onRemove) {
                        Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain).foregroundStyle(WFColors.tertiaryText)
                    .help("移除此条件").accessibilityLabel("移除" + rule.kind.title + "条件")
                }
                valueEditor
            }
            .padding(WFSpace.md)
            .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        }
    }

    @ViewBuilder private var valueEditor: some View {
        switch rule.kind {
        case .lists, .tags:
            Button { showingOptions.toggle() } label: {
                HStack {
                    Text(rule.organizationNames.isEmpty ? "选择" + rule.kind.title : rule.organizationSelections.map(\.name).joined(separator: "、"))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: WFSpace.sm)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .font(WFType.body).padding(WFSpace.sm)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            // 业务弹层统一走无箭头呈现（与任务详情/日期面板同一套壳）。
            .background {
                AnchoredPropertyPanel(isPresented: $showingOptions, width: 264,
                                      placement: .verticalInOwner,
                                      focusPolicy: .preservePresenter) {
                    organizationOptions
                }
            }
            if rule.kind == .tags {
                Picker("标签匹配", selection: $rule.tagMatch) {
                    Text("包含任一标签").tag(FilterTagMatch.any)
                    Text("包含全部标签").tag(FilterTagMatch.all)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        case .priorities:
            HStack(spacing: WFSpace.sm) {
                ForEach(TaskPriority.menuOrder, id: \.self) { priority in
                    Button {
                        if !rule.selectedPriorities.insert(priority).inserted { rule.selectedPriorities.remove(priority) }
                    } label: {
                        Label(priorityTitle(priority), systemImage: "flag.fill")
                            .foregroundStyle(rule.selectedPriorities.contains(priority) ? WFColors.accent : WFColors.secondaryText)
                            .font(WFType.supporting).padding(WFSpace.sm)
                            .background(rule.selectedPriorities.contains(priority) ? WFColors.selection : WFColors.content,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(rule.selectedPriorities.contains(priority) ? "已选择" : "未选择")
                }
            }
        case .date:
            Picker("日期范围", selection: $rule.dateRange) {
                ForEach(SavedFilterDateRange.allCases, id: \.self) { range in Text(range.title).tag(range) }
            }.labelsHidden()
        case .keywords:
            TextField("在标题与正文中匹配，空格或逗号分隔", text: $rule.keywordText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var organizationOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("选择" + rule.kind.title).font(WFType.section).padding(WFSpace.md)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.sm) {
                    ForEach(rule.kind == .lists ? listOptions : tagOptions, id: \.self) { name in
                        Toggle(isOn: Binding(get: { rule.organizationNames.contains(name) }, set: { selected in
                            var names = rule.organizationNames
                            if selected { names.insert(name) } else { names.remove(name) }
                            rule.organizationNames = names
                        })) {
                            HStack(spacing: WFSpace.sm) {
                                Image(systemName: rule.kind == .tags ? "tag" : "list.bullet")
                                    .foregroundStyle(rule.kind == .tags ? workspace.tagColor(name) : WFColors.secondaryText)
                                Text(name).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(WFSpace.md).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
        .frame(width: 264)
        .onExitCommand { showingOptions = false }
    }

    private func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
