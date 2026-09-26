import SwiftUI

struct TaskTagPickerPopover: View {
    let onCancel: () -> Void
    let onApply: ([String]) -> Void
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var query = ""
    @State private var selectedTags: Set<String>
    @FocusState private var searchFocused: Bool

    init(initialTags: [String], workspace: TaskWorkspaceModel,
         onCancel: @escaping () -> Void, onApply: @escaping ([String]) -> Void) {
        self.workspace = workspace
        self.onCancel = onCancel
        self.onApply = onApply
        _selectedTags = State(initialValue: Set(initialTags))
    }

    private var allTags: [String] { Array(Set(workspace.tagNames).union(selectedTags)).sorted() }
    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^#", with: "", options: .regularExpression)
    }
    private var matchingTags: [String] {
        allTags.filter { normalizedQuery.isEmpty || $0.localizedCaseInsensitiveContains(normalizedQuery) }
    }
    private var creatableTags: [String] {
        normalizedQuery.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "^#", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty && !allTags.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("输入标签", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(WFSpace.md)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if matchingTags.isEmpty && creatableTags.isEmpty {
                        VStack(spacing: WFSpace.sm) {
                            Image(systemName: "tag").font(.system(size: 28)).foregroundStyle(WFColors.tertiaryText)
                            Text("没有标签").font(WFType.body).foregroundStyle(WFColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, WFSpace.xl)
                    }
                    ForEach(matchingTags, id: \.self) { tag in
                        Button { toggle(tag) } label: {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: "tag").foregroundStyle(WFColors.secondaryText)
                                Text(tag).frame(maxWidth: .infinity, alignment: .leading)
                                if selectedTags.contains(tag) {
                                    Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                                }
                            }
                            .padding(.horizontal, WFSpace.md).padding(.vertical, WFSpace.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !creatableTags.isEmpty {
                        Button {
                            selectedTags.formUnion(creatableTags)
                            query = ""
                            searchFocused = true
                        } label: {
                            Label("创建「\(creatableTags.joined(separator: "、"))」", systemImage: "plus")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, WFSpace.md).padding(.vertical, WFSpace.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, WFSpace.xs)
            }
            Divider()
            HStack(spacing: WFSpace.sm) {
                Button("取消", action: onCancel).frame(maxWidth: .infinity)
                Button("确定") { onApply(Array(selectedTags).sorted()) }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            .padding(WFSpace.md)
        }
        .frame(width: 264, height: 320)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: onCancel)
    }

    private func toggle(_ tag: String) {
        if !selectedTags.insert(tag).inserted { selectedTags.remove(tag) }
    }
}
