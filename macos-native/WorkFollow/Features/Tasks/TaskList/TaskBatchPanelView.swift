import SwiftUI

/// 测试锚点(仅测试消费):SwiftUI 文本不进进程内 AX 树也不落 NSTextField,
/// 渲染契约测试靠这个 key 收集面板实际渲染出的文案。
struct TaskBatchPanelTextKey: PreferenceKey {
    static let defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

extension View {
    @ViewBuilder
    func batchPanelTextProbe(_ text: String) -> some View {
        #if DEBUG
        background(
            GeometryReader { _ in
                Color.clear.preference(key: TaskBatchPanelTextKey.self, value: [text])
            }
        )
        #else
        self
        #endif
    }
}

/// 批量面板布局常量：滴答实测值(2026-10 截图 2x 像素扫描换算 1x pt)。
/// 面板消费、渲染契约测试锁定——改尺寸必须同时过滴答截图对照,防止回退。
enum BatchPanelLayout {
    static let tileHeight: CGFloat = 75
    static let tileColumnGap: CGFloat = 2
    static let rowHeight: CGFloat = 30
    static let flagTileHeight: CGFloat = 34
}

/// 批量面板（阶段2,补齐轮对齐滴答瓦片布局）：bulkSelection 非空时右栏整体
/// 替换为它——状态机 A 的 S2 投影,面板存在与否完全由 `bulkSelection.isEmpty`
/// 推导,没有独立的"面板模式"开关。
/// 上半区属性行（日期/优先级/清单/标签,经确认后批量应用）,下半区动作瓦片
/// （即时执行）。所有 mutation 走 `applyBulk`/`convertBulkToNotes`（HUD 反馈
/// 与一步撤销自动获得）。提醒（reminderOffsets）动作层虽支持,但批量场景没有
/// 可信的授权 UI,宁缺毋假不暴露。
struct TaskBatchPanelView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var workspace: TaskWorkspaceModel

    @State private var showSchedule = false
    @State private var showTagPicker = false
    @State private var showParentPicker = false

    private var count: Int { workspace.bulkSelection.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: WFSpace.md) {
                    propertySection
                    Divider()
                    actionTiles
                }
                .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
                .padding(.vertical, WFSpace.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WFColors.content)
        // Esc 阶梯最外层：批量态下 Esc = 退出批量（面板持有焦点时由此接）。
        .onExitCommand { workspace.clearBulkSelection() }
        .schedulePopover(isPresented: $showSchedule) {
            TaskDatePopoverV2(task: Self.draftTask(clock: workspace.clock()),
                              workspace: workspace,
                              draftCommit: { plan in
                                  // 弹层"确定"才提交：applyBulk 清空集合，面板随之回到空态/详情。
                                  workspace.applyBulk(.schedule(plan.schedule))
                              }) {
                showSchedule = false
            }
        }
        .background(AnchoredPropertyPanel(isPresented: $showTagPicker, width: 264) {
            TaskTagPickerPopover(initialTags: [], workspace: workspace,
                                 onCancel: { showTagPicker = false },
                                 onApply: { tags in
                                     // 空选集 = 没挑任何标签,不动任务直接收起。
                                     guard !tags.isEmpty else { showTagPicker = false; return }
                                     workspace.applyBulk(.tags(tags))
                                     showTagPicker = false
                                 })
        })
        .background(AnchoredPropertyPanel(isPresented: $showParentPicker, width: 280) {
            TaskParentPicker(taskID: workspace.bulkSelection.first ?? UUID(),
                             workspace: workspace,
                             onClose: { showParentPicker = false })
        })
    }

    // MARK: - 头部：计数 + 取消

    private var header: some View {
        HStack(spacing: WFSpace.sm) {
            Text("已选择 \(count) 项").font(WFType.pageTitle).batchPanelTextProbe("已选择 \(count) 项")
            Spacer(minLength: 0)
            Button { workspace.clearBulkSelection() } label: {
                Text("取消")
                    .font(WFType.control)
                    .foregroundStyle(WFColors.accent)
                    .frame(height: WFMetrics.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("退出批量选择")
            .accessibilityLabel("取消批量选择")
        }
        .padding(.horizontal, TaskInspectorMetrics.horizontalPadding)
        .padding(.top, WFSpace.lg)
        .padding(.bottom, WFSpace.md)
    }

    // MARK: - 属性区（滴答形态）：一个灰卡片包四行值显示行,点击弹选择器。
    // 优先级/清单显示所选任务的"共同值"（一致→蓝色高亮,不一致→中性文案）,
    // 这与滴答一致——批量面板先展示现状,选择器再改。

    private var propertySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            scheduleChip
            priorityValueRow
            if priorityPickerExpanded { priorityFlagRow }
            listValueRow
            tagRow
        }
        .padding(.vertical, WFSpace.xs)
        .background(WFColors.menuSelected, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 所选任务优先级共同值:全部一致→该值;不一致→nil。
    private var commonPriority: TaskPriority? {
        let tasks = workspace.allTasks.filter { workspace.bulkSelection.contains($0.id) }
        guard !tasks.isEmpty else { return nil }
        let first = tasks[0].priority
        return tasks.allSatisfy { $0.priority == first } ? first : nil
    }

    /// 所选任务清单共同值。
    private var commonListName: String? {
        let tasks = workspace.allTasks.filter { workspace.bulkSelection.contains($0.id) }
        guard !tasks.isEmpty else { return nil }
        let first = tasks[0].list.name
        return tasks.allSatisfy { $0.list.name == first } ? first : nil
    }

    private var scheduleChip: some View {
        Button { showSchedule = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text("设置日期")
                Spacer(minLength: 0)
            }
            .font(WFType.control)
            .foregroundStyle(WFColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .padding(.horizontal, WFSpace.md)
            .contentShape(Rectangle())
            .batchPanelTextProbe("设置日期")
        }
        .buttonStyle(.plain)
        .help("批量设置日期（各自截止日保留）")
        .accessibilityLabel("批量设置日期")
        .scheduleTrigger()
    }

    /// 优先级值行:显示共同值（滴答"无优先级"文案形态),点击展开四旗选择。
    private var priorityValueRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { priorityPickerExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag")
                Text(priorityTitle(commonPriority ?? .none))
                Spacer(minLength: 0)
            }
            .font(WFType.control)
            .foregroundStyle(commonPriority != nil && commonPriority != .none
                             ? WFColors.accent : WFColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .padding(.horizontal, WFSpace.md)
            .contentShape(Rectangle())
            .batchPanelTextProbe(priorityTitle(commonPriority ?? .none))
        }
        .buttonStyle(.plain)
        .help("批量设置优先级")
        .accessibilityLabel("批量设置优先级")
    }

    /// 展开的四旗选择行(选中即应用并收起,滴答的旗子在详情弹层,批量这里就地展开)。
    private var priorityFlagRow: some View {
        HStack(spacing: WFSpace.sm) {
            priorityButton(.high, color: WFColors.flagHigh)
            priorityButton(.medium, color: WFColors.flagMedium)
            priorityButton(.low, color: WFColors.accent)
            priorityButton(.none, color: WFColors.secondaryText)
        }
        .padding(.horizontal, WFSpace.md)
        .padding(.bottom, WFSpace.sm)
        .frame(maxWidth: .infinity)
    }

    @State private var priorityPickerExpanded = false

    private func priorityButton(_ priority: TaskPriority, color: Color) -> some View {
        Button {
            workspace.applyBulk(.priority(priority))
            priorityPickerExpanded = false
        } label: {
            Image(systemName: priority == .none ? "flag" : "flag.fill")
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: BatchPanelLayout.flagTileHeight)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(priorityTitle(priority))
        .accessibilityLabel("批量设置\(priorityTitle(priority))")
    }

    private var listValueRow: some View {
        Menu {
            ForEach(workspace.allListNames, id: \.self) { name in
                Button { workspace.applyBulk(.move(name)) } label: { Text(name) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tray.full")
                Text(commonListName ?? "移动到清单")
                Spacer(minLength: 0)
            }
            .font(WFType.control)
            .foregroundStyle(commonListName != nil ? WFColors.accent : WFColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .padding(.horizontal, WFSpace.md)
            .contentShape(Rectangle())
            .batchPanelTextProbe(commonListName ?? "移动到清单")
        }
        .menuIndicator(.hidden)
        .help("批量移动到清单")
        .accessibilityLabel("批量移动到清单")
    }

    private var tagRow: some View {
        Button { showTagPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                Text("标签")
                Spacer(minLength: 0)
            }
            .font(WFType.control)
            .foregroundStyle(WFColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .padding(.horizontal, WFSpace.md)
            .contentShape(Rectangle())
            .batchPanelTextProbe("标签")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help("批量添加标签（追加去重）")
        .accessibilityLabel("批量添加标签")
    }

    // MARK: - 动作瓦片区（滴答式双列）

    private var actionTiles: some View {
        // 滴答实测(2x 图换算):瓦片 215×75pt,列隙 ~2pt,行隙 ~8pt,近乎无缝。
        LazyVGrid(columns: [GridItem(.flexible(), spacing: BatchPanelLayout.tileColumnGap),
                            GridItem(.flexible(), spacing: BatchPanelLayout.tileColumnGap)],
                  spacing: WFSpace.sm) {
            actionTile("完成", symbol: "checkmark.circle", tint: WFColors.tileBlue) {
                workspace.applyBulk(.complete)
            }
            actionTile("置顶", symbol: "pin", tint: WFColors.tileYellow) {
                workspace.applyBulk(.pin(true))
            }
            actionTile("关联主任务", symbol: "arrow.triangle.branch", tint: WFColors.tileGreen) {
                showParentPicker = true
            }
            // 「合并」有意缺席：滴答里该入口点击即改任务（多任务并一）,语义
            // 未实证前宁缺毋假,单独一轮验证后再实施。
            actionTile("创建副本", symbol: "doc.on.doc", tint: WFColors.tileCyan) {
                workspace.applyBulk(.duplicate)
            }
            actionTile("转换为笔记", symbol: "note.text", tint: WFColors.tileGreen) {
                workspace.convertBulkToNotes(environment: environment)
            }
            actionTile("复制文本", symbol: "doc.plaintext", tint: WFColors.tileBlue) {
                workspace.copyBulkTitlesToPasteboard()
            }
            actionTile("删除", symbol: "trash", tint: WFColors.flagHigh) {
                workspace.applyBulk(.delete)
            }
        }
    }

    private func actionTile(_ title: String, symbol: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: WFSpace.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(tint)
                Text(title)
                    .font(WFType.control)
                    .foregroundStyle(WFColors.text)
            }
            // 滴答的瓦片铺满格子(缝只来自格隙 2pt/8pt),按钮 label 必须
            // frame 到全宽全高,否则 flexible 格子里内容居中会再生缝隙。
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: BatchPanelLayout.tileHeight)
            .background(WFColors.menuSelected,
                        in: RoundedRectangle(cornerRadius: WFMetrics.corner))
            .contentShape(Rectangle())
            .batchPanelTextProbe(title)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: BatchPanelLayout.tileHeight)
        .help("批量\(title)")
        .accessibilityLabel("批量\(title)")
    }

    private func priorityTitle(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: "无优先级"
        case .low: "低优先级"
        case .medium: "中优先级"
        case .high: "高优先级"
        }
    }

    /// 日期弹层的草稿宿主：批量没有"当前任务"，用一个固定 ID 的合成任务承载
    /// 草稿态（同快速添加 quickAddDraftTaskID 的做法），提交时只取 CommitPlan.schedule。
    private static func draftTask(clock: @autoclosure () -> Date) -> Task {
        Task(id: UUID(uuidString: "00000000-0000-0000-0000-00000000BA7C")!,
             title: "批量安排", list: TaskList.inbox, priority: .none,
             schedule: TaskSchedule(), parentID: nil, childOrder: 0,
             createdAt: clock(), updatedAt: clock())
    }
}
