import SwiftUI

struct QuickAddPropertiesOverrides: Equatable {
    var priority: TaskPriority?
    var listName: String?
    var tags: [String]?
}

struct QuickAddPropertiesPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selectedPriority: TaskPriority
    let selectedList: String
    let selectedTags: [String]
    let onPriority: (TaskPriority) -> Void
    let onList: (String) -> Void
    let onTags: ([String]) -> Void
    let onReminder: () -> Void
    let onRepeat: () -> Void

    @State private var showingListPicker = false
    @State private var showingTagPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text("优先级").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            HStack(spacing: WFSpace.xs) {
                priorityButton(.high, color: .red)
                priorityButton(.medium, color: .orange)
                priorityButton(.low, color: WFColors.accent)
                priorityButton(.none, color: WFColors.secondaryText)
            }
            Divider()
            Button {
                showingListPicker = true
            } label: {
                propertyRow(icon: selectedList == TaskList.inbox.name ? "tray" : "list.bullet",
                            title: selectedList, detail: "清单")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingListPicker, arrowEdge: .trailing) {
                QuickAddListPickerPopover(workspace: workspace, selectedList: selectedList,
                    onCancel: { showingListPicker = false },
                    onSelect: { name in
                        onList(name)
                        showingListPicker = false
                    })
            }
            Button {
                showingTagPicker = true
            } label: {
                propertyRow(icon: "tag", title: selectedTags.isEmpty ? "标签" : selectedTags.map { "#\($0)" }.joined(separator: " "), detail: "标签")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingTagPicker, arrowEdge: .trailing) {
                TaskTagPickerPopover(initialTags: selectedTags, workspace: workspace,
                    onCancel: { showingTagPicker = false },
                    onApply: { values in
                        onTags(values)
                        showingTagPicker = false
                    })
            }
            Button(action: onReminder) {
                propertyRow(icon: "alarm", title: "提醒", detail: "提醒")
            }
            .buttonStyle(.plain)
            Button(action: onRepeat) {
                propertyRow(icon: "repeat", title: "重复", detail: "重复")
            }
            .buttonStyle(.plain)
        }
        .padding(WFSpace.md)
        .frame(width: 270)
    }

    private func priorityButton(_ priority: TaskPriority, color: Color) -> some View {
        Button { onPriority(priority) } label: {
            Image(systemName: "flag.fill")
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: WFMetrics.controlHeight)
                .background(selectedPriority == priority ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(priorityLabel(priority))
        .accessibilityLabel(priorityLabel(priority))
    }

    private func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    private func propertyRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: WFSpace.md) {
            Image(systemName: icon).foregroundStyle(WFColors.secondaryText)
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(detail).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WFColors.secondaryText)
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: WFMetrics.controlHeight)
        .contentShape(Rectangle())
    }
}

private struct QuickAddListPickerPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selectedList: String
    let onCancel: () -> Void
    let onSelect: (String) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var matches: [String] {
        workspace.allListNames.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("搜索清单", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(WFSpace.md)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { name in
                        Button { onSelect(name) } label: {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: name == TaskList.inbox.name ? "tray" : "list.bullet")
                                    .foregroundStyle(WFColors.secondaryText)
                                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                if name == selectedList {
                                    Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                                }
                            }
                            .padding(.horizontal, WFSpace.md)
                            .frame(height: WFMetrics.controlHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if matches.isEmpty {
                        Text("没有匹配的清单").font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText).padding(WFSpace.lg)
                    }
                }
            }
        }
        .frame(width: 250, height: 300)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onCancel)
    }
}
