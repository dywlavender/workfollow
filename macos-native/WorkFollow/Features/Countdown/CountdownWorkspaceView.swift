import SwiftUI

// 色板（`countdownPaletteColors`）与 `countdownColor(_:)` 已移到
// `CountdownPaletteColors.swift`：这里是界面侧唯一一份，卡片 / 编辑器 / 样式弹窗 /
// 智能清单小节都从那儿取。原先本文件与 `CountdownEditorView.swift` 各存了一份
// 6 色板，靠注释约定同序同值。

/// 页头的类型筛选。参考图的四个胶囊：所有 / 纪念日 / 倒数日 / 节日。
///
/// 胶囊行**没有「生日」**（参考图就没有），所以生日记录归到「纪念日」下。
/// 这不是凑合：纪念日和生日本来就是同一类——都是「某一天」的年度纪念，
/// 差别只在生日多记一个出生年、卡片上多显示一个岁数。
///
/// 于是四个胶囊正好把四种 `CountdownKind` 分完（见 `kinds`），
/// **不会有记录落在任何胶囊之外**。加类型时记得同步这张映射表，
/// 漏了就会让新类型只在「所有」下可见。
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

    /// 这个胶囊收哪些记录类型；「所有」为 nil，表示不过滤。
    ///
    /// 是集合而不是单个类型，就是为了让「纪念日」能同时收下生日。
    var kinds: Set<CountdownKind>? {
        switch self {
        case .all: return nil
        case .anniversary: return [.anniversary, .birthday]
        case .countdown: return [.countdown]
        case .festival: return [.festival]
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
        store.events(matching: filter.kinds)
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
                        let place = position(of: event)
                        CountdownCardView(
                            event: event,
                            projection: event.projection(asOf: today, calendar: calendar),
                            magnitude: event.magnitude(asOf: today,
                                                       unit: event.effectiveDisplayUnit,
                                                       calendar: calendar),
                            ageText: event.ageText(asOf: today, calendar: calendar),
                            onCycleUnit: { store.cycleDisplayUnit(event.id) },
                            onOpen: { sheet = .edit(event) },
                            onStyle: { sheet = .style(event) },
                            onNote: { sheet = .note(event) },
                            onArchive: { store.archive(event.id) },
                            onDelete: { confirmDelete(event) },
                            onTogglePin: { store.togglePin(event.id) },
                            onMoveUp: { store.move(event.id, to: place.index - 1) },
                            onMoveDown: { store.move(event.id, to: place.index + 1) },
                            canMoveUp: place.index > 0,
                            canMoveDown: place.index < place.count - 1)
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

    /// 卡片在**未过滤**的完整列表里的位置，供上移/下移用。
    ///
    /// 用 `store.events` 而不是页面上过滤后的 `items`：`move(_:to:)` 操作的是完整
    /// 列表，拿过滤后的下标去移，「只看纪念日」这类筛选下会跳到意料之外的位置——
    /// 而且不会报错，只是顺序变得没法解释。
    private func position(of event: CountdownEvent) -> (index: Int, count: Int) {
        let order = store.events
        return (order.firstIndex { $0.id == event.id } ?? 0, order.count)
    }

    private func confirmDelete(_ event: CountdownEvent) {
        if TaskNamePrompt.confirm("删除“\(event.displayName)”？", message: "删除后无法恢复。",
                                  action: "删除") {
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
    /// 主数字按当前单位拆好的段：`128` / `4月9天` / `18周2天`。
    let magnitude: CountdownMagnitude
    /// 生日开了「显示岁数」时才有值，跟在名字后面。
    let ageText: String?
    /// 点卡片：轮换主数字单位（天 → 月 → 周）。编辑走悬停条里的「⋯ → 编辑」。
    let onCycleUnit: () -> Void
    let onOpen: () -> Void
    let onStyle: () -> Void
    let onNote: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    /// 已在首/末位时为假——菜单项据此禁用，比「点了没反应」清楚。
    let canMoveUp: Bool
    let canMoveDown: Bool

    @State private var hovering = false

    var body: some View {
        Button(action: onCycleUnit) {
            CountdownCardFace(event: event,
                              symbol: event.safeSymbol,
                              colorIndex: event.colorIndex,
                              projection: projection,
                              magnitude: magnitude,
                              ageText: ageText)
            // 参考图卡片内的竖向落点（以卡片上沿为原点，2× 图墨迹带中心）：名称 ≈44.8、
            // 数字 ≈101.3、文案 ≈154.8；我们实测 43.8 / 102.3 / 155，三项都在 1pt 内。
            // 上下不等距，所以分别给而不是 `.padding(.vertical,)`。
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
            // 天数才是这张卡片的主信息，要进无障碍标签；悬停提示另给一整句
            // （用 `sentence`，不是 `captionPrefix`——提示里没有那个大数字兜底）。
            //
            // 必须挂在**按钮内部**：挂到外层会把 overlay 里的置顶 / 更多两个按钮一起并进
            // 这个元素，它们各自的 `.accessibilityLabel` 就失效了——实测读到的会是整张卡片
            // 的标签（"春节，还有 128 天"）而不是"置顶"。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(event.displayName)\(ageText.map { "，\($0)" } ?? "")，"
                + "\(projection.isFuture ? "还有" : "已经") \(magnitude.spokenText)")
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                hoverActions.padding(WFSpace.sm)
            }
        }
        .onHover { hovering = $0 }
        .help(projection.sentence(with: magnitude))
        .contextMenu {
            menuItems
        }
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
    ///
    /// 上移/下移是加出来的两项：`CountdownStore.move(_:to:)` 早就写好、排序也一直
    /// 按 `sortOrder` 走，但**没有任何入口**，所以顺序实际恒等于创建顺序。
    /// 卡片在 3 列 `LazyVGrid` 里，网格拖拽重排又麻烦又容易做错，菜单两项是同样的
    /// 能力、零布局风险。归档/删除仍靠分隔线隔开。
    @ViewBuilder
    private var menuItems: some View {
        Button { onOpen() } label: { Label("编辑", systemImage: "pencil") }
        Button { onStyle() } label: { Label("样式", systemImage: "paintpalette") }
        Button { onNote() } label: { Label("备注", systemImage: "note.text") }
        Button { onMoveUp() } label: { Label("上移", systemImage: "arrow.up") }
            .disabled(!canMoveUp)
        Button { onMoveDown() } label: { Label("下移", systemImage: "arrow.down") }
            .disabled(!canMoveDown)
        Divider()
        Button { onArchive() } label: { Label("归档", systemImage: "archivebox") }
        Button { onDelete() } label: { Label("删除", systemImage: "trash") }
    }
}

// MARK: - 卡片的面子

/// 卡片的**面子**：图标 + 名称（生日另挂岁数）/ 大数字 / 距离文案。
///
/// **不含**内边距、底色与描边——那是「真卡片」与「样式弹窗里的预览卡」各自的事。
/// 抽出来的理由只有一个：预览卡的意义是「所见即所得」，另抄一份渲染迟早会漂，
/// 所以两者共用这一份。
///
/// `symbol` / `colorIndex` 单独传、不从 `event` 取：预览要显示**还没保存**的草稿值
/// ——用户在样式弹窗里点了某个颜色或图标，预览卡要立刻跟着变。
struct CountdownCardFace: View {
    let event: CountdownEvent
    let symbol: String
    let colorIndex: Int
    let projection: CountdownProjection
    /// 主数字按当前单位拆好的段：`128` / `4月9天` / `18周2天`。
    let magnitude: CountdownMagnitude
    /// 生日开了「显示岁数」时才有值，跟在名字后面。
    let ageText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WFSpace.sm) {
                iconBadge
                // 18pt 是量出来的（都是 2× 图、同一阈值）：参照物「春节」墨迹 69×35px，
                // 我们 15pt 只有 57×29px，18pt 是 68×34px——差 1px，已到字号能调的极限。
                // 墨迹密度参照物略高（0.561 vs 0.519），是它的中文字体笔画更粗，抄不了。
                Text(event.displayName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WFColors.overlayText)
                    .lineLimit(1)
                if let ageText {
                    // 岁数没有参照样本（三张参照图里没有生日卡），维持 11pt 不动。
                    Text(ageText)
                        .font(WFType.caption)
                        .foregroundStyle(WFColors.overlayTertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: WFSpace.sm)
            magnitudeRow
            Spacer(minLength: WFSpace.sm)
            // 12pt 而不是 `WFType.caption`（11）：参照物副标题墨迹带宽 353px、高 26px，
            // 我们 11pt 是 309×22px、12pt 是 336×25px——按宽度线性外推参照物约 12.6pt，
            // 12pt 把误差从 −12.5% 压到 −4.8%，且 `supporting` 本身就是 12pt 常规。
            // 剩下的宽度差主要来自它的大数字字体（数字那簇 127px vs 我们 117px），补不平。
            // 这里用**前缀**而不是完整句：上面 `magnitudeRow` 已经把天数单独
            // 放大显示了，两句并排会重复。**卡片是唯一该这么用的地方**，
            // 别处要一句话请用 `projection.sentence(with:)`。
            Text(projection.captionPrefix)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.overlayTertiaryText)
                .lineLimit(1)
        }
    }

    /// 主数字一行。数字大、单位字小，单位字约为数字的一半高。
    ///
    /// 对齐方式是**按基线**（`.lastTextBaseline`），不是居中：把参考图 `4月9天`
    /// 的字形墨迹框量出来，四个字的**底边齐平**（442 / 444 / 444 / 444 px），
    /// 而中心差了 18px（数字 408、单位 427）——居中会让单位字浮到数字腰上去。
    ///
    /// **字号按参照物的比例定**（都是 2 倍图的墨迹高，同一把尺子）：
    /// 参照物 `128` 的数字 83px、`4月9天` / `18周2天` 的数字 68~71px、单位字 34~35px，
    /// 也就是它**多段档会把数字缩到约 1/1.2**。我们自己的 44pt 给出 64px、
    /// 22pt 单位字给出 37px，据此换算：单段 83px → 57pt、多段 69px → 47pt、单位字 → 21pt。
    /// `spacing: 2` 补的是参考图里字与字之间那点缝（实测 14~18px，比字体自带的边距宽）。
    ///
    /// **字体层面做不到对齐**：参照物的大数字是它自带的商业字体
    /// （`TickTick.app/Contents/Resources/Gulzar dida.ttf`，PostScript 名
    /// `Gulzar-dida-Medium`，**只含 0-9**，所以单位字回落到系统字体）。
    /// 我们只能用 SF Rounded，字形抄不了——能对齐的只有字号与对齐方式。
    private var magnitudeRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            ForEach(Array(magnitude.parts.enumerated()), id: \.offset) { _, part in
                Text("\(part.value)")
                    .font(.system(size: digitSize, weight: .semibold, design: .rounded))
                if !part.unit.isEmpty {
                    Text(part.unit)
                        .font(.system(size: Self.unitGlyphSize, weight: .semibold,
                                      design: .rounded))
                }
            }
        }
        .foregroundStyle(WFColors.accent)
        // 放到 HStack 上靠环境传给每个 Text：`18周2天` 比 `128` 宽，窄卡片下要能缩。
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    /// 参照物 `128`：数字墨迹 83px。我们 44pt 是 64px，按比例换算得 57pt。
    private static let singlePartDigitSize: CGFloat = 57
    /// 参照物 `4月9天` / `18周2天`：数字墨迹 68~71px，比单段档小约 1/1.2 → 47pt。
    private static let multiPartDigitSize: CGFloat = 47
    /// 参照物单位字墨迹 34~35px；我们 22pt 是 37px → 21pt。
    private static let unitGlyphSize: CGFloat = 21

    /// 按**渲染出来的段数**选字号，而不是按单位：不足一个更大单位时会退回纯数字
    /// （`0月2天` → `2`），那个形态和按天档长得一样，就该一样大。
    private var digitSize: CGFloat {
        magnitude.parts.count > 1 ? Self.multiPartDigitSize : Self.singlePartDigitSize
    }

    private var iconBadge: some View {
        ZStack {
            Circle().fill(countdownColor(colorIndex))
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}
