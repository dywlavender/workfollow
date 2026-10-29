import SwiftUI

struct TaskTagPickerPopover: View {
    let onCancel: () -> Void
    let onApply: ([String]) -> Void
    let initialTags: [String]
    private let panelHeight: CGFloat
    @ObservedObject var workspace: TaskWorkspaceModel
    @State private var session: TaskTagPickerSession
    @FocusState private var searchFocused: Bool

    init(initialTags: [String], workspace: TaskWorkspaceModel,
         onCancel: @escaping () -> Void, onApply: @escaping ([String]) -> Void) {
        self.workspace = workspace
        self.onCancel = onCancel
        self.onApply = onApply
        self.initialTags = initialTags
        let draft = TaskTagPickerSession(initialTags: initialTags)
        _session = State(initialValue: draft)
        let rows = draft.allTags(availableTags: workspace.orderedTags.map(\.name)).count
        let headerHeight: CGFloat = 17 + WFSpace.md * 2
            + (draft.orderedSelection.isEmpty ? 0 : 24 + WFSpace.md)
        let footerHeight = PopupMetrics.compactButtonHeight + PopupMetrics.contentInset * 2 + 1
        // 短列表按初始内容收高，打开后外框稳定；搜索和草稿变化只调整列表的可用空间。
        panelHeight = min(320, headerHeight + footerHeight + WFSpace.xs * 2
            + CGFloat(max(3, rows)) * PopupMetrics.menuRowHeight)
    }

    private var matchingTags: [String] { session.matchingTags(availableTags: workspace.orderedTags.map(\.name)) }
    private var creatableTags: [String] { session.creatableTags(availableTags: workspace.tagNames) }

    var body: some View {
        VStack(spacing: 0) {
            if !session.orderedSelection.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.orderedSelection, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag).lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: PopupMetrics.tagPickerWidth - 68)
                                Button { session.toggle(tag) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(WFColors.secondaryText)
                                        .frame(width: 14, height: 20).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).hoverTip("取消选择标签：" + tag)
                                    .accessibilityLabel("取消选择标签：" + tag)
                                .tagPickerRenderAnchor(.remove(tag))
                            }
                            .font(WFType.body).foregroundStyle(WFColors.accent)
                            .padding(.leading, 8).padding(.trailing, 4).frame(height: 24)
                            .background(WFColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(height: 24).padding(.horizontal, WFSpace.md).padding(.top, WFSpace.md)
            }
            HStack(spacing: WFSpace.sm) {
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
                        TaskTagPickerChoiceRow(name: tag, color: workspace.tagColor(tag),
                            selected: session.selectedTags.contains(tag),
                            indent: session.query.isEmpty ? CGFloat(workspace.tagDepth(tag)) * 12 : 0) {
                            session.toggle(tag)
                        }
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
                .compactScrollbars()
            }
            PopupActionBar {
                PopupActionButton(title: "取消", action: onCancel)
                    .tagPickerRenderAnchor(.cancel)
                PopupActionButton(title: "确定", primary: true) { onApply(session.orderedSelection) }
                    .tagPickerRenderAnchor(.confirm)
            }
        }
        .frame(width: PopupMetrics.tagPickerWidth, height: panelHeight)
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

private struct TaskTagPickerChoiceRow: View {
    let name: String
    let color: Color
    let selected: Bool
    let indent: CGFloat
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: WFSpace.md) {
                Image(systemName: "tag").foregroundStyle(selected ? WFColors.accent : color)
                Text(name).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(selected ? WFColors.accent : WFColors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                    .opacity(selected ? 1 : 0)
            }
            .font(WFType.body).padding(.horizontal, WFSpace.md).padding(.leading, indent)
            .frame(height: PopupMetrics.menuRowHeight).contentShape(Rectangle())
            .background(hovered ? WFColors.hover : .clear,
                        in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.transaction { $0.animation = nil }
        .accessibilityLabel(name).accessibilityValue(selected ? "已选择" : "未选择")
    }
}
