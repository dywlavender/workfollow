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
    @State private var collapsed: Set<UUID> = []
    @State private var targeted: UUID?
    @State private var colorTag: UUID?
    @State private var editor: TaskTagEditorRequest?

    var body: some View {
        let counts = workspace.tagSidebarCounts
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("标签").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                Spacer(minLength: 0)
                Button { create(parentID: nil) } label: {
                    Image(systemName: "plus").font(.system(size: 12)).frame(width: 20, height: 20)
                }
                .foregroundStyle(WFColors.secondaryText)
                .help("新建标签").accessibilityLabel("新建标签")
            }
            .padding(.horizontal, WFSpace.sm).padding(.top, WFSpace.lg).padding(.bottom, WFSpace.xs)
            if workspace.taskTags.isEmpty {
                Text("以标签组织不同清单中的任务").font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, WFSpace.sm)
            }
            ForEach(workspace.orderedTags.filter { workspace.tagAncestors($0.id).allSatisfy { !collapsed.contains($0) } }) { tag in
                tagRow(tag, count: counts[tag.name, default: 0])
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
                HStack(spacing: 4) {
                    Image(systemName: "tag").font(.system(size: 12)).frame(width: 12)
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
        .padding(.horizontal, WFSpace.sm)
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
        .contextMenu { tagMenu(tag) }
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
        Menu("移动到") {
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
