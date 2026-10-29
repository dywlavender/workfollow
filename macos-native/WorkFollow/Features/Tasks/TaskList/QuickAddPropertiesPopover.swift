import SwiftUI

/// 输入框显示模式（对齐滴答「输入框设置」的简洁 / 详细）。
enum QuickAddDisplayMode: String, CaseIterable {
    case compact, detailed

    static let defaultsKey = "quickAddDisplayMode"

    var title: String {
        switch self {
        case .compact: "简洁"
        case .detailed: "详细"
        }
    }

    var detail: String {
        switch self {
        case .compact: "单行输入，属性在菜单"
        case .detailed: "常显日期与属性图标"
        }
    }
}

struct QuickAddPropertiesOverrides: Equatable {
    var priority: TaskPriority?
    var listName: String?
    var tags: [String]?

    static func renamedTags(_ tags: [String]?, notification: Notification) -> [String]? {
        guard notification.userInfo?["kind"] as? String == TaskOrganizationRename.Kind.tag.rawValue,
              let old = notification.userInfo?["old"] as? String,
              let new = notification.userInfo?["new"] as? String else { return tags }
        return tags.map { $0.map { $0 == old ? new : $0 } }
    }
}

struct QuickAddPropertiesPopover: View {
    @ObservedObject var workspace: TaskWorkspaceModel
    let selectedPriority: TaskPriority
    let selectedList: String
    let selectedTags: [String]
    var attachments: [NativeAttachment] = []
    var displayMode: QuickAddDisplayMode = .compact
    let onPriority: (TaskPriority) -> Void
    let onList: (String) -> Void
    let onTags: ([String]) -> Void
    let onTemplate: () -> Void
    var onAttachments: ([NativeAttachment]) -> Void = { _ in }
    var onDisplayMode: (QuickAddDisplayMode) -> Void = { _ in }
    let onDismiss: () -> Void

    private enum Child { case list, tags, displayMode }
    @State private var activeChild: Child?

    private func presented(_ child: Child) -> Binding<Bool> {
        Binding(get: { activeChild == child }, set: { if !$0, activeChild == child { activeChild = nil } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            Text("优先级").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            HStack(spacing: WFSpace.xs) {
                priorityButton(.high, color: WFColors.flagHigh)
                priorityButton(.medium, color: WFColors.flagMedium)
                priorityButton(.low, color: WFColors.accent)
                priorityButton(.none, color: WFColors.secondaryText)
            }
            Divider()
            PopupMenuRow(action: {
                activeChild = .list
            }, minHeight: WFMetrics.controlHeight, horizontalPadding: 0) {
                propertyRow(icon: selectedList == TaskList.inbox.name ? "tray" : "list.bullet",
                            title: selectedList)
            }
            .quickAddRenderAnchor(.list)
            .background(AnchoredPropertyPanel(isPresented: presented(.list), width: PopupMetrics.quickAddChildWidth,
                                              placement: .submenu, focusPolicy: .panel) {
                QuickAddListPickerPopover(workspace: workspace, selectedList: selectedList,
                    onCancel: { activeChild = nil },
                    onSelect: { name in
                        onList(name)
                        activeChild = nil
                    })
            })
            PopupMenuRow(action: {
                activeChild = .tags
            }, minHeight: WFMetrics.controlHeight, horizontalPadding: 0) {
                propertyRow(icon: "tag", title: selectedTags.isEmpty ? "标签" : selectedTags.map { "#\($0)" }.joined(separator: " "))
            }
            .quickAddRenderAnchor(.tags)
            .background(AnchoredPropertyPanel(isPresented: presented(.tags), width: PopupMetrics.tagPickerWidth,
                                              placement: .submenu, focusPolicy: .panel) {
                TaskTagPickerPopover(initialTags: selectedTags, workspace: workspace,
                    onCancel: { activeChild = nil },
                    onApply: { values in
                        onTags(values)
                        activeChild = nil
                    })
            })
            // 滴答属性菜单第 5 项（实测 2026-10-16）：附件（文件选择器）。
            PopupMenuRow(action: {
                pickAttachments()
            }, minHeight: WFMetrics.controlHeight, horizontalPadding: 0) {
                propertyRow(icon: "paperclip",
                            title: attachments.isEmpty ? "附件" : "附件 \(attachments.count)",
                            hasChild: false)
            }
            .quickAddRenderAnchor(.attachment)
            // 滴答属性菜单第 6 项（实测 2026-10-17）：从模板添加（带右 chevron，打开模板选择器）。
            PopupMenuRow(action: onTemplate,
                         minHeight: WFMetrics.controlHeight,
                         horizontalPadding: 0) {
                propertyRow(icon: "doc.text", title: "从模板添加", hasChild: true)
            }
            .quickAddRenderAnchor(.template)
            // 滴答属性菜单第 7 项（实测 2026-10-17）：输入框设置（简洁 / 详细）。
            // 滴答这一行在菜单最底部，图标是齿轮，不是滑杆。
            PopupMenuRow(action: {
                activeChild = .displayMode
            }, minHeight: WFMetrics.controlHeight, horizontalPadding: 0) {
                propertyRow(icon: "gearshape", title: "输入框设置：\(displayMode.title)")
            }
            .quickAddRenderAnchor(.displayMode)
            .background(AnchoredPropertyPanel(isPresented: presented(.displayMode), width: 250,
                                              placement: .submenu, focusPolicy: .panel) {
                QuickAddDisplayModePopover(selected: displayMode,
                    onCancel: { activeChild = nil },
                    onSelect: { mode in
                        onDisplayMode(mode)
                        activeChild = nil
                    })
            })
        }
        .padding(WFSpace.md)
        .frame(width: PopupMetrics.quickAddPropertiesWidth)
        .quickAddRenderAnchor(.properties)
        .background(PopupEscapeRouter(depth: 1) {
            if activeChild != nil { activeChild = nil }
            else { onDismiss() }
        })
        .onDisappear { activeChild = nil }
        .onExitCommand {
            if activeChild != nil { activeChild = nil }
            else { onDismiss() }
        }
    }

    private func priorityButton(_ priority: TaskPriority, color: Color) -> some View {
        Button { onPriority(priority) } label: {
            Image(systemName: priority == .none ? "flag" : "flag.fill")
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: WFMetrics.controlHeight)
                .background(selectedPriority == priority ? WFColors.selection : .clear,
                            in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popupMenuRowBackground(selected: selectedPriority == priority,
                                cornerRadius: WFMetrics.corner)
        .hoverTip(priorityLabel(priority))
        .accessibilityLabel(priorityLabel(priority))
        .quickAddRenderAnchor(.priority(priority))
    }

    private func priorityLabel(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    private func pickAttachments() {
        NativeAttachmentFiles.choose { result in
            guard case .success(let picked) = result, !picked.isEmpty else { return }
            onAttachments(attachments + picked)
        }
    }

    private func propertyRow(icon: String, title: String, hasChild: Bool = true) -> some View {
        HStack(spacing: WFSpace.md) {
            Image(systemName: icon).foregroundStyle(WFColors.secondaryText)
            Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WFColors.secondaryText)
                .opacity(hasChild ? 1 : 0)
        }
        .padding(.horizontal, WFSpace.sm)
        .frame(height: WFMetrics.controlHeight)
        .contentShape(Rectangle())
    }
}

private struct QuickAddDisplayModePopover: View {
    let selected: QuickAddDisplayMode
    let onCancel: () -> Void
    let onSelect: (QuickAddDisplayMode) -> Void

    var body: some View {
        VStack(spacing: WFSpace.xs) {
            ForEach(QuickAddDisplayMode.allCases, id: \.self) { mode in
                PopupMenuRow(action: { onSelect(mode) }, minHeight: 48,
                             horizontalPadding: WFSpace.sm) {
                    HStack(spacing: WFSpace.md) {
                        Image(systemName: mode == .compact ? "rectangle" : "rectangle.split.1x2")
                            .foregroundStyle(WFColors.secondaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(WFType.menu)
                            Text(mode.detail).font(WFType.supporting)
                                .foregroundStyle(WFColors.secondaryText)
                        }
                        Spacer(minLength: 4)
                        if selected == mode {
                            Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                        }
                    }
                }
                .foregroundStyle(WFColors.text)
            }
        }
        .padding(WFSpace.sm)
        .frame(width: PopupMetrics.quickAddChildWidth)
        .onExitCommand(perform: onCancel)
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
        workspace.availableListNames.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
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
                        PopupMenuRow(action: { onSelect(name) },
                                     minHeight: WFMetrics.controlHeight,
                                     horizontalPadding: WFSpace.md) {
                            HStack(spacing: WFSpace.md) {
                                Image(systemName: name == TaskList.inbox.name ? "tray" : "list.bullet")
                                    .foregroundStyle(WFColors.secondaryText)
                                Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                if name == selectedList {
                                    Image(systemName: "checkmark").foregroundStyle(WFColors.accent)
                                }
                            }
                        }
                    }
                    if matches.isEmpty {
                        Text("没有匹配的清单").font(WFType.supporting)
                            .foregroundStyle(WFColors.secondaryText).padding(WFSpace.lg)
                    }
                }
                .compactScrollbars()
            }
        }
        .frame(width: 250, height: 300)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        .onExitCommand(perform: onCancel)
    }
}
