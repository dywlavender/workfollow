import SwiftUI

struct TaskTagPickerPopover: View {
    let onCancel: () -> Void
    let onApply: ([String]) -> Void
    let initialTags: [String]
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var session: TaskTagPickerSession
    @FocusState private var searchFocused: Bool

    init(initialTags: [String], workspace: TaskWorkspaceModel,
         onCancel: @escaping () -> Void, onApply: @escaping ([String]) -> Void) {
        self.workspace = workspace
        self.onCancel = onCancel
        self.onApply = onApply
        self.initialTags = initialTags
        _session = State(initialValue: TaskTagPickerSession(initialTags: initialTags))
    }

    private var matchingTags: [String] { session.matchingTags(availableTags: workspace.tagNames) }
    private var creatableTags: [String] { session.creatableTags(availableTags: workspace.tagNames) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(WFColors.secondaryText)
                TextField("输入标签", text: $session.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onKeyPress(.escape) {
                        onCancel()
                        return .handled
                    }
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
                        Button { session.toggle(tag) } label: {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: "tag").foregroundStyle(WFColors.secondaryText)
                                Text(tag).frame(maxWidth: .infinity, alignment: .leading)
                                if session.selectedTags.contains(tag) {
                                    Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                                }
                            }
                            .padding(.horizontal, WFSpace.md).padding(.vertical, WFSpace.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tagPickerRenderAnchor(.tag(tag))
                    }
                    if !creatableTags.isEmpty {
                        Button {
                            session.createFromQuery(availableTags: workspace.tagNames)
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
                    .tagPickerRenderAnchor(.cancel)
                Button("确定") { onApply(Array(session.selectedTags).sorted()) }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    .tagPickerRenderAnchor(.confirm)
            }
            .padding(WFSpace.md)
        }
        .frame(width: 264, height: 320)
        .coordinateSpace(name: "task-tag-picker")
        .onAppear {
            session = TaskTagPickerSession(initialTags: initialTags)
            // The hosting view appears before its native child window is attached.
            DispatchQueue.main.async { searchFocused = true }
        }
        .background(PopupEscapeRouter(depth: 2, onEscape: onCancel))
        .onExitCommand(perform: onCancel)
    }
}
