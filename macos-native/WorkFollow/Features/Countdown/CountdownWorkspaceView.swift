import SwiftUI

/// 固定色板：与 `CountdownEvent.paletteSize`（Domain 白名单约定）数量一致。
/// 下标顺序同时被 `CountdownKind.defaultColorIndex` 依赖，改动要一起改。
private let countdownPalette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple]

/// 色板下标安全取色（负数/越界自动回绕）。
private func countdownColor(_ index: Int) -> Color {
    let count = max(countdownPalette.count, 1)
    return countdownPalette[((index % count) + count) % count]
}

/// 页头的类型筛选。参考图的四个胶囊：所有 / 纪念日 / 倒数日 / 节日。
///
/// 注意这里**没有「生日」**：参考图的胶囊行就只有这三个类型加「所有」，
/// 生日记录只在「所有」下出现。这是照着图复刻的结果，不是漏写——要加的话
/// 在 `CountdownFilter.allCases` 补一个 case 即可。
enum CountdownFilter: String, CaseIterable, Identifiable {
    case all, anniversary, countdown, festival

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "所有"
        case .anniversary: return CountdownKind.anniversary.title
        case .countdown: return CountdownKind.countdown.title
        case .festival: return CountdownKind.festival.title
        }
    }

    /// 对应的记录类型；「所有」为 nil。
    var kind: CountdownKind? {
        switch self {
        case .all: return nil
        case .anniversary: return .anniversary
        case .countdown: return .countdown
        case .festival: return .festival
        }
    }
}

/// 倒数纪念日工作区（对齐参考实现）：一行页头（标题 + 新增 + 更多）→ 类型胶囊 →
/// 自适应卡片网格。点击卡片进编辑，悬停出现置顶与更多按钮。
struct CountdownWorkspaceView: View {
    @ObservedObject var store: CountdownStore

    @State private var filter: CountdownFilter = .all
    @State private var sheet: Sheet?
    @State private var today = Date()

    private var calendar: Calendar { .current }

    /// 一次 sheet 弹出的目标；id 在展示期间保持稳定。
    enum Sheet: Identifiable {
        /// 原版 `+` 是菜单，选哪个类型就开哪个类型的面板，所以新建要带上类型。
        case create(CountdownKind)
        case edit(CountdownEvent)
        case style(CountdownEvent)
        case note(CountdownEvent)
        case archived

        var id: String {
            switch self {
            case .create(let kind): return "create-\(kind.rawValue)"
            case .edit(let event): return "edit-\(event.id)"
            case .style(let event): return "style-\(event.id)"
            case .note(let event): return "note-\(event.id)"
            case .archived: return "archived"
            }
        }
    }

    init(store: CountdownStore) {
        self.store = store
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: WFSpace.md) {
                header
                filterRow
                content(availableWidth: proxy.size.width)
            }
            .padding(.horizontal, WFSpace.lg)
            .padding(.top, WFSpace.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(WFColors.canvas)
        }
        .onAppear {
            today = Date()
            store.refresh()
        }
        // 跨天（含从睡眠唤醒）后重算天数；store 只在日界真的跨过时才会 bump。
        .onChange(of: store.dateRevision) { _, _ in today = Date() }
        .sheet(item: $sheet) { present in
            switch present {
            case .create(let kind):
                CountdownEditorView(store: store, original: nil, defaultKind: kind)
            case .edit(let event):
                CountdownEditorView(store: store, original: event)
            case .style(let event):
                CountdownStyleView(store: store, event: event)
            case .note(let event):
                CountdownNoteView(store: store, event: event)
            case .archived:
                ArchivedCountdownsView(store: store)
            }
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack(spacing: WFSpace.sm) {
            Text(NativeDestination.countdown.title)
                .font(WFType.pageTitle)
            // 参考图标题后有一个下拉小箭头（原版用它切换模块）。这里只做视觉对齐：
            // 模块切换已经由左侧图标栏承担，再造一个入口是重复的导航。
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
            Spacer(minLength: WFSpace.sm)
            // 原版的 `+` 不是直接开面板，而是先弹一个「纪念日 / 倒数日 / 生日 / 节日」
            // 菜单，选中哪个就开哪个类型的面板（参考图 4 的四张面板正是这么来的）。
            Menu {
                ForEach(CountdownKind.allCases) { kind in
                    Button(kind.title) { sheet = .create(kind) }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("新建")
            .accessibilityLabel("新建")
            // 参考图的「更多」菜单内容不可见，这里只放本页真正需要的入口：
            // 归档记录得有个地方能进得去。
            Menu {
                Button("已归档…") { sheet = .archived }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
            .accessibilityLabel("更多")
        }
        .foregroundStyle(WFColors.text)
    }

    // MARK: 类型筛选

    private var filterRow: some View {
        HStack(spacing: WFSpace.inline) {
            ForEach(CountdownFilter.allCases) { item in
                let selected = filter == item
                Button {
                    filter = item
                } label: {
                    Text(item.title)
                        .font(WFType.supporting)
                        .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                        .padding(.horizontal, WFSpace.control)
                        .frame(height: 22)
                        .background(selected ? WFColors.selection : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
    }

    // MARK: 卡片网格

    private var visibleEvents: [CountdownEvent] {
        store.events(matching: filter.kind)
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        let items = visibleEvents
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                // 参考实现是**三列固定卡片**：1512pt 窗口下每张 310×193、间距 20，
                // 整行只占 970pt，右边留白——不是铺满宽度的自适应网格。
                // 用 flexible + max 310 表达：宽窗口下钳到 310（与参考一致），
                // 窄窗口下按比例缩小而不是溢出。
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 200,
                                                                      maximum: 310),
                                                              spacing: 20),
                                         count: 3),
                          alignment: .leading,
                          spacing: WFSpace.xl) {
                    ForEach(items) { event in
                        CountdownCardView(
                            event: event,
                            projection: event.projection(asOf: today, calendar: calendar),
                            ageText: event.ageText(asOf: today, calendar: calendar),
                            onOpen: { sheet = .edit(event) },
                            onStyle: { sheet = .style(event) },
                            onNote: { sheet = .note(event) },
                            onArchive: { store.archive(event.id) },
                            onDelete: { confirmDelete(event) },
                            onTogglePin: { store.togglePin(event.id) })
                    }
                }
                .padding(.bottom, WFSpace.xl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 空态文案取自参照物语言包：`no_countdowns` = 记录你的重要时刻，
    /// `no_countdown_message` = 让回忆和期待都有迹可循。
    private var emptyState: some View {
        VStack(spacing: WFSpace.md) {
            Image(systemName: NativeDestination.countdown.symbol).font(.largeTitle)
            Text("记录你的重要时刻").font(WFType.body)
            Text("让回忆和期待都有迹可循")
                .font(WFType.supporting)
        }
        .foregroundStyle(WFColors.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func confirmDelete(_ event: CountdownEvent) {
        if TaskNamePrompt.confirm("删除“\(event.displayName)”？", message: "删除后无法恢复。") {
            _ = store.hardDelete(event.id)
        }
    }
}

// MARK: - 卡片

/// 一张倒数纪念日卡片：图标 + 名称（生日另挂岁数）、大号天数、距离文案；
/// 悬停出现置顶与更多。
struct CountdownCardView: View {
    let event: CountdownEvent
    let projection: CountdownProjection
    /// 生日开了「显示岁数」时才有值，跟在名字后面。
    let ageText: String?
    let onOpen: () -> Void
    let onStyle: () -> Void
    let onNote: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 0) {
                HStack(spacing: WFSpace.sm) {
                    iconBadge
                    Text(event.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(WFColors.overlayText)
                        .lineLimit(1)
                    if let ageText {
                        Text(ageText)
                            .font(WFType.caption)
                            .foregroundStyle(WFColors.overlayTertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: WFSpace.sm)
                Text("\(projection.days)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(WFColors.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: WFSpace.sm)
                Text(projection.caption)
                    .font(WFType.caption)
                    .foregroundStyle(WFColors.overlayTertiaryText)
                    .lineLimit(1)
            }
            // 参考图卡片内的竖向落点（卡片 193 高）：名称中心 ≈48、天数中心 ≈104、
            // 文案中心 ≈156。上下不等距，所以分别给而不是 `.padding(.vertical,)`。
            .padding(.horizontal, WFSpace.md)
            .padding(.top, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
            // 参考实测：1512pt 窗口下卡片 310×193。
            .frame(height: 193)
            .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hovering ? WFColors.accent.opacity(0.35) : WFColors.overlayBorder)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                hoverActions.padding(WFSpace.sm)
            }
        }
        .onHover { hovering = $0 }
        .help(projection.caption)
        // 天数才是这张卡片的主信息，要进无障碍标签；`caption` 作为悬停提示另给。
        .accessibilityLabel(
            "\(event.displayName)\(ageText.map { "，\($0)" } ?? "")，"
            + "\(projection.isFuture ? "还有" : "已经") \(projection.days) 天")
        .contextMenu {
            menuItems
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle().fill(countdownColor(event.colorIndex))
            Image(systemName: event.safeSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    /// 悬停时出现的两个方块按钮：置顶与更多（参考图右上角）。
    ///
    /// 参考图里这两个方块是**深灰底 + 白色字形**（26×26、圆角约 7）。原来用
    /// `tertiaryLabelColor` 在浅色下几乎是白的，白字形等于看不见。
    private var hoverActions: some View {
        HStack(spacing: WFSpace.sm) {
            Button(action: onTogglePin) {
                Image(systemName: event.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color(nsColor: .secondaryLabelColor),
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help(event.pinned ? "取消置顶" : "置顶")
            .accessibilityLabel(event.pinned ? "取消置顶" : "置顶")

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color(nsColor: .secondaryLabelColor),
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
            .accessibilityLabel("更多")
        }
    }

    /// 卡片菜单：参考图里的 编辑 / 样式 / 备注 / 归档 / 删除，**每项带图标**。
    @ViewBuilder
    private var menuItems: some View {
        Button { onOpen() } label: { Label("编辑", systemImage: "pencil") }
        Button { onStyle() } label: { Label("样式", systemImage: "paintpalette") }
        Button { onNote() } label: { Label("备注", systemImage: "note.text") }
        Button { onArchive() } label: { Label("归档", systemImage: "archivebox") }
        Button { onDelete() } label: { Label("删除", systemImage: "trash") }
    }
}
