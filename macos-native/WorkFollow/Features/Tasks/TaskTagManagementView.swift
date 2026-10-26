import SwiftUI

private struct TaskTagEditorRequest: Identifiable {
    let id = UUID()
    var tagID: UUID?
    var parentID: UUID?
}

@MainActor
extension TaskWorkspaceModel {
    func tagColor(_ name: String) -> Color {
        tag(named: name)?.colorARGB.map(WFListPalette.swatch) ?? WFColors.secondaryText
    }

    func tagDepth(_ name: String) -> Int {
        guard let tag = tag(named: name) else { return 0 }
        return tagAncestors(tag.id).count
    }

    func tagAncestors(_ id: UUID) -> [UUID] {
        var result: [UUID] = []
        var next = tag(for: id)?.parentID
        while let parent = next, !result.contains(parent) {
            result.append(parent)
            next = tag(for: parent)?.parentID
        }
        return result
    }
}

struct TaskTagsSectionView: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    @ObservedObject var navigation: AppNavigation
    var onNavigate: () -> Void = {}
    var sectionCollapsed: Bool = false
    var onToggleSection: () -> Void = {}
    /// 分组显示状态（滴答标签头「⋯」：显示 / 隐藏 / 有内容时显示）。
    /// 只控制组内标签行，分组头始终保留，保证入口随时可改回来。
    var sectionVisibility: SmartListVisibility = .visible
    var onSetSectionVisibility: (SmartListVisibility) -> Void = { _ in }
    @State private var collapsed: Set<UUID> = []
    @State private var targeted: UUID?
    @State private var colorTag: UUID?
    @State private var editor: TaskTagEditorRequest?

    var body: some View {
        let counts = workspace.tagSidebarCounts
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "标签", collapsed: sectionCollapsed, toggle: onToggleSection) {
                HStack(spacing: 0) {
                    tagSectionMenu
                    Button { create(parentID: nil) } label: {
                        Image(systemName: "plus").font(.system(size: 12)).frame(width: 20, height: 20)
                    }
                    .foregroundStyle(WFColors.secondaryText)
                    .help("新建标签").accessibilityLabel("新建标签")
                }
                .fixedSize()
            }
            if !sectionCollapsed && sectionVisibility.shows(hasContent: !workspace.taskTags.isEmpty) {
                if workspace.taskTags.isEmpty {
                    SidebarHintCard(text: "以标签的维度展示不同清单的任务。在添加任务时输入“#”可快速选择标签")
                } else {
                    ForEach(workspace.orderedTags.filter { workspace.tagAncestors($0.id).allSatisfy { !collapsed.contains($0) } }) { tag in
                        tagRow(tag, count: counts[tag.name, default: 0])
                    }
                }
            }
        }
        .buttonStyle(.plain).font(WFType.navigation)
        .sheet(item: $editor) { request in
            TaskTagEditorView(workspace: workspace,
                tag: request.tagID.flatMap { workspace.tag(for: $0) }, parentID: request.parentID,
                onSaved: { parentID in if let parentID { collapsed.remove(parentID) } },
                onDismiss: { editor = nil })
        }
    }

    /// 标签分组头「⋯」：对齐滴答实测（2026-10-25），只有三个显示状态项。
    /// 宽度用 narrow（176），不沿用右键菜单的 224 宽度。
    private var tagSectionMenu: some View {
        BusinessMenu(width: PopupMetrics.menuWidthNarrow, title: "标签显示") {
            BusinessMenuChoices(selection: Binding(
                get: { sectionVisibility },
                set: { onSetSectionVisibility($0) }),
                options: SmartListVisibility.menuOrder.map { BusinessChoice($0, $0.title) })
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 18, height: 20)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .help("标签显示")
        .accessibilityLabel("标签显示")
    }

    private func tagRow(_ tag: TaskTag, count: Int) -> some View {
        let children = workspace.taskTags.contains { $0.parentID == tag.id }
        return HStack(spacing: 0) {
            if children {
                Button {
                    if collapsed.contains(tag.id) { collapsed.remove(tag.id) } else { collapsed.insert(tag.id) }
                } label: {
                    Image(systemName: collapsed.contains(tag.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9)).frame(width: 12, height: NavigationMetrics.rowHeight)
                }
                .accessibilityLabel((collapsed.contains(tag.id) ? "展开" : "收起") + tag.name)
            }
            Button {
                navigation.destination = .allTasks
                workspace.activeList = nil; workspace.activeFilterID = nil; workspace.activeTag = tag.name
                onNavigate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag").font(.system(size: 12)).frame(width: 22)
                        .foregroundStyle(workspace.tagColor(tag.name))
                    Text(tag.name).lineLimit(1)
                    Spacer(minLength: WFSpace.xs)
                    if tag.colorARGB != nil {
                        Circle().fill(workspace.tagColor(tag.name)).frame(width: 7, height: 7)
                    }
                    if count > 0 {
                        Text("\(count)").font(WFType.supporting).foregroundStyle(WFColors.tertiaryText)
                    }
                }
                .frame(height: NavigationMetrics.rowHeight).contentShape(Rectangle())
            }
            .accessibilityLabel("标签：" + tag.name)
        }
        // 滴答实测：标签图标起于行内 19、文字 47，与智能清单同一列。
        .padding(.leading, 11)
        .padding(.trailing, WFSpace.sm)
        .padding(.leading, CGFloat(workspace.tagDepth(tag.name)) * 16)
        .background(workspace.activeTag == tag.name ? WFColors.listSelection : .clear,
                    in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .draggable("workfollow-tag:" + tag.id.uuidString)
        .overlay(alignment: .top) {
            Rectangle().fill(targeted == tag.id ? WFColors.accent : .clear)
                .frame(height: 6).contentShape(Rectangle())
                .dropDestination(for: String.self) { values, _ in
                    guard let raw = values.first, raw.hasPrefix("workfollow-tag:"),
                          let id = UUID(uuidString: String(raw.dropFirst("workfollow-tag:".count))) else { return false }
                    return workspace.reorderTag(id, before: tag.id)
                } isTargeted: { active in targeted = active ? tag.id : nil }
        }
        .businessContextMenu { tagMenu(tag) }
        // 业务弹层统一走无箭头呈现（和任务详情、日期面板同一套壳）。
        .background {
            AnchoredPropertyPanel(
                isPresented: Binding(get: { colorTag == tag.id }, set: { if !$0 { colorTag = nil } }),
                width: 220, placement: .verticalInOwner,
                focusPolicy: .preservePresenter) {
                TaskTagColorPicker(workspace: workspace, tagID: tag.id) { colorTag = nil }
            }
        }
    }

    @ViewBuilder private func tagMenu(_ tag: TaskTag) -> some View {
        Button("添加子标签…") { create(parentID: tag.id) }
        Button("编辑标签…") { editor = TaskTagEditorRequest(tagID: tag.id, parentID: tag.parentID) }
        Button("颜色…") { colorTag = tag.id }
        BusinessMenu("移动到") {
            Button("顶层") { workspace.reparentTag(tag.id, parentID: nil) }
            ForEach(workspace.orderedTags.filter { $0.id != tag.id && !workspace.tagAncestors($0.id).contains(tag.id) }) { parent in
                Button(parent.name) { workspace.reparentTag(tag.id, parentID: parent.id) }
            }
        }
        Button("移至同级末尾") { workspace.reorderTag(tag.id, before: nil) }
        Divider()
        Button("删除标签…") {
            guard TaskNamePrompt.confirm("删除标签“\(tag.name)”？", message: "任务会保留，子标签移到上一级。可撤销。", action: "删除") else { return }
            workspace.removeTag(tag.id)
        }
    }

    private func create(parentID: UUID?) {
        editor = TaskTagEditorRequest(tagID: nil, parentID: parentID)
    }
}

private struct TaskTagColorPicker: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let tagID: UUID
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: WFSpace.md) {
            Text("标签颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            TaskTagColorGrid(color: Binding(get: { workspace.tag(for: tagID)?.colorARGB },
                set: { workspace.setTagColor(tagID, colorARGB: $0) }))
        }
        .padding(WFSpace.lg).onExitCommand(perform: onDismiss)
    }
}
