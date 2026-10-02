import SwiftUI

// 色板与取色函数已移到 `CountdownPaletteColors.swift`（界面侧唯一一份），
// 本文件原先自带的 6 色板副本已删。

/// 新建 / 编辑倒数纪念日。布局照参考图的「添加」面板：图标 + 名称输入框一行，
/// 其下 日期 / 提醒 / 重复 / 类型 / 显示 五行（生日多一行「显示岁数」），
/// 底部 取消 / 添加。
///
/// 五个下拉都是**浮层**（`overlayPreferenceValue` + `FieldAnchorKey` 定位），
/// 不是行内展开：行内展开会把面板撑高、把底部按钮推走，而参考图的面板是定高的。
///
/// 浮层贴的是**字段**（不含左侧标签列），不是整行——参考图里浮层与字段左右对齐。
/// 早先按整行定位，浮层会宽出 60pt 并盖住标签；而日期浮层改贴字段之后，
/// 同一面板里两种宽度、打开时还会左右横跳，所以统一到字段。
///
/// 注意浮层必须留在面板内：macOS 的 sheet 就是一块真实窗口、会裁掉伸出去的内容，
/// 所以「下方放不下就翻到上方」（见 `popupY`），而不是让浮层溢出面板。
struct CountdownEditorView: View {
    @ObservedObject var store: CountdownStore
    /// nil = 新建。
    let original: CountdownEvent?

    @Environment(\.dismiss) private var dismiss

    /// 一次只展开一行。
    private enum Row: String, Identifiable {
        case date, reminder, recurrence, kind, display
        var id: String { rawValue }
    }

    /// 「日期」浮层里的草稿：公历还是农历、哪个月/日、带不带年份。
    ///
    /// 做成**一个值**而不是几个 `@State`，是为了能用一次 `==` 回答「用户动过没有」。
    /// 这个判断不是洁癖：`除夕`（`.lunarEve`）的农历月/日是逐年变的（腊月廿九或
    /// 三十），用「月/日」下拉重建一定会在某些年份落到不存在的日子上，所以没动过
    /// 就必须原样保留原规则。
    private struct DateDraft: Equatable {
        /// 用户选过日期没有。新建时是 false：日期行显示灰色占位、「添加」禁用。
        var isSet: Bool
        var isLunar: Bool
        var month: Int
        var day: Int
        var year: Int
        /// 勾上 = 日期不带年份（每年重复）；勾掉 = 具体某一年的某一天。
        var ignoresYear: Bool
    }

    /// 面板的**基准**：草稿初值，以及它对应的原始规则。
    ///
    /// 两者必须一起变，所以合成一个值。判断「用户到底动过日期没有」只要一次 `==`
    /// ——`除夕`（`.lunarEve`）这类规则的农历月/日是逐年变的，用「月/日」重建会
    /// 失真，没动过就必须原样保留（见 `draftDeviates`）。
    ///
    /// 拆成两个独立状态出过事：从节日目录选了「除夕」，只更新草稿、不更新基准，
    /// `draftDeviates` 立刻为真，目录给的 `.lunarEve` 被旁路，规则按草稿的月/日
    /// 重建成 `lunarYearly(12, 29)`——腊月若恰有三十天就早一天，界面也从
    /// 「农历除夕」变成「农历腊月廿九」。合成一个值类型，让「一起变」成为结构上的
    /// 必然，而不是靠记得。
    private struct Baseline: Equatable {
        var draft: DateDraft
        var rule: CountdownRule?
    }

    @State private var kind: CountdownKind
    @State private var name: String
    @State private var symbol: String
    @State private var colorIndex: Int
    /// 已确定的日期。日期行、提交用的规则都看它。
    @State private var draft: DateDraft
    /// 浮层里正在编辑的那一份。打开浮层时从 `draft` 拷过来，「确定」才写回去——
    /// 所以「取消」不必回滚，直接丢掉即可。
    @State private var editing: DateDraft
    /// 打开面板时的基准；从节日目录选一条之后也跟着换成新基准。
    @State private var baseline: Baseline
    @State private var repeatSelection: CountdownRepeat
    @State private var reminders: Set<Int>
    @State private var smartListDisplay: CountdownSmartListDisplay
    @State private var showsAge: Bool
    /// 名称框右端那个按钮的浮层开关。
    ///
    /// 参考图里它打开的是**图标选择器**（13 个预设：旅行 / 演唱会 / 发工资 /
    /// 交房租 / 信用卡还款 …，每条带图标和名字）。原先这里被猜成了「备注」的
    /// 展开开关——面板上因此多出一个参考图里根本没有的备注行。
    /// 备注在滴答那边只有**卡片菜单 → 独立模态框**一个入口，不在添加/编辑面板里。
    @State private var symbolPickerOpen: Bool
    @State private var openRow: Row?
    /// 「提醒 → 自定义」里的提前天数。存量里已有的非预设值回填到这里。
    @State private var customReminderDays: Int
    /// 「重复 → 自定义」里的间隔天数。
    @State private var customIntervalDays: Int

    private var calendar: Calendar { .current }
    private var isNew: Bool { original == nil }

    // 参考面板实测（1512pt 窗口下的原版「添加」面板）：
    // 面板 460×448，左右内边距 39，行高 34，行间距 10，标签列宽 54，
    // 行内控件 322×34，底部按钮 102×32。这里按同一组数排，别凭感觉调。
    private static let panelWidth: CGFloat = 460
    private static let inset: CGFloat = 40
    private static let labelWidth: CGFloat = 54
    private static let rowHeight: CGFloat = 34
    private static let rowGap: CGFloat = 10
    private static let buttonWidth: CGFloat = 102
    /// 下拉浮层里选项行的高度。
    ///
    /// 参考图的下拉行距是 34（跟面板行一样），但参考图里浮层是**伸出面板之外**画的，
    /// 而 macOS 的 sheet 会把伸出去的部分裁掉。面板又不能变高（那正是要修的毛病），
    /// 所以只能让行距小一点，把选项塞进面板里：
    /// - 34 时「提醒」「重复」都放不下，被迫翻到行上方；
    /// - 30 时能挂在行下方，但最底下的「自定义」会被面板下沿切掉一点；
    /// - 28 时 7 行 = 208pt，稳稳落在可用高度（约 215pt）内，最后一行完整可见。
    private static let popupRowHeight: CGFloat = 28

    /// 「日期」浮层的几何。各段间距照参考图**分段**给，不是等距——参考图里
    /// 分段控件与下拉行之间最松（26），下拉行与「忽略年份」之间最紧（19），
    /// 「忽略年份」与按钮之间最松（31）。等距会让「忽略年份」看起来和下拉行
    /// 是一组、按钮是另一组，而参考图里它是独立的一行。
    ///
    /// 参考图是 2× 截图，值已折半。整卡实测 319×206：横向内边距 15、分段控件
    /// 162×26 居中、下拉行 32 高、按钮 26 高。**卡宽由字段决定**，不是由整行决定
    /// （见 `RowFrames`）——这是「比例」的关键，卡一宽就扁。
    private static let datePopupTopInset: CGFloat = 15
    private static let datePopupBottomInset: CGFloat = 15
    private static let dateSegmentGap: CGFloat = 26
    private static let dateFieldGap: CGFloat = 19
    private static let dateButtonGap: CGFloat = 31
    /// 分段控件的宽度。参考图里它比内容窄、居中——不是撑满。
    private static let dateSegmentWidth: CGFloat = 162
    /// 月/日/年下拉的高度。参考图的字段比面板行（34）矮一档。
    private static let dateFieldHeight: CGFloat = 32
    /// 「日期」浮层的内容高度（含自身内边距，不含浮层外壳的上下内边距）。
    ///
    /// `15 + 24 + 26 + 32 + 19 + 16 + 31 + 24 + 15`，逐段对应上面几个常量：
    /// 上内边距 / 分段控件 / 间距 / 下拉行 / 间距 / 忽略年份 / 间距 / 按钮 / 下内边距。
    /// 其中分段控件与按钮用的是**系统控件的实测高度**（24），不是参考图的 26——
    /// 这两颗是原生控件，硬掰高度会和系统外观打架。
    private static let datePopupContentHeight: CGFloat = 202

    init(store: CountdownStore, original: CountdownEvent?, defaultKind: CountdownKind = .anniversary) {
        self.store = store
        self.original = original
        let kind = original?.kind ?? defaultKind
        _kind = State(initialValue: kind)
        _name = State(initialValue: original?.name ?? "")
        _symbol = State(initialValue: original?.safeSymbol ?? kind.defaultSymbol)
        _colorIndex = State(initialValue: original?.colorIndex ?? kind.defaultColorIndex)
        // 编辑时把规则摊回浮层草稿（公历还是农历、哪个月/日、带不带年份）。
        //
        // 新建时**故意留空**：参考图的「日期」行是灰色的「选择日期」占位，
        // 「添加」按钮同时是禁用的——即日期属于必填，但初始不预设。
        let calendar = Calendar.current
        let today = Date()
        let seedDraft = Self.makeDraft(for: original, kind: kind, calendar: calendar, today: today)
        _baseline = State(initialValue: Baseline(draft: seedDraft, rule: original?.rule))
        _draft = State(initialValue: seedDraft)
        _editing = State(initialValue: seedDraft)
        _repeatSelection = State(initialValue: original?.repeatValue ?? kind.defaultRepeat)
        _reminders = State(initialValue: Set(original?.reminderOffsets
            ?? CountdownEvent.defaultReminderOffsets))
        _smartListDisplay = State(initialValue: original?.effectiveSmartListDisplay ?? .sameDay)
        _showsAge = State(initialValue: original?.showsAge ?? false)
        _symbolPickerOpen = State(initialValue: false)
        // 「自定义」两个输入框：存量里已经有非预设值的就回填，否则给 30。
        let presetDays = Set(CountdownEvent.reminderChoices.map { $0 / CountdownEvent.minutesPerDay })
        let existingCustomDays = (original?.reminderOffsets ?? [])
            .map { $0 / CountdownEvent.minutesPerDay }
            .first { !presetDays.contains($0) }
        _customReminderDays = State(initialValue: existingCustomDays ?? 30)
        let existingInterval: Int
        if let rule = original?.rule, case .interval(let days, _, _) = rule {
            existingInterval = days
        } else {
            existingInterval = 30
        }
        _customIntervalDays = State(initialValue: existingInterval)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "添加" : "编辑")
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 30)
                .padding(.bottom, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    nameRow
                    dateRow
                    reminderRow
                    repeatRow
                    kindRow
                    displayRow
                    if kind.hasAgeOption { ageRow }
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, WFSpace.xxl)
            }
            // 固定高度：下拉是浮层，不再把面板撑高（参考图的面板就是固定大小）。
            // 410 是「提醒」「重复」都能挂在行下方的最小高度（「显示」在最底下，
            // 无论如何都要翻到上面）。
            .frame(maxHeight: 410)
            Divider()
            footer
        }
        .frame(width: Self.panelWidth)
        .background(WFColors.canvas)
        // 下拉浮层：浮在对应行的旁边、盖在面板内容之上，**不参与布局**。
        // 锚点挂在字段上（见 `FieldAnchorKey`），所以浮层与字段左右对齐。
        .overlayPreferenceValue(FieldAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if let openRow, let anchor = anchors[openRow] {
                    popupLayer(row: openRow, rect: proxy[anchor], container: proxy.size)
                }
            }
        }
    }

    /// 一层浮层：按 `rect` 定宽、按上下余量定落点。
    @ViewBuilder
    private func popupLayer(row: Row, rect: CGRect, container: CGSize) -> some View {
        let height = popupHeight(for: row)
        let y = popupY(row: rect, height: height, containerHeight: container.height)
        popup {
            popupBody(for: row,
                      maxHeight: popupRoom(row: rect, y: y, containerHeight: container.height))
        }
        .frame(width: rect.width)
        .offset(x: rect.minX, y: y)
    }

    /// 浮层的纵向落点。
    ///
    /// 默认挂在行的正下方；下方放不下就翻到行的上方（底边贴着行上沿）。
    /// **必须留在面板里**：sheet 的边界就是面板边界，伸出去的部分会被裁掉
    /// （表现成「浮层被编辑框挡住」）；而面板又不能在展开时变高——那正是要修的毛病。
    private func popupY(row rect: CGRect, height: CGFloat, containerHeight: CGFloat) -> CGFloat {
        let gap: CGFloat = 6
        let top: CGFloat = 8
        let bottom = containerHeight - 8
        let below = rect.maxY + gap
        if below + height <= bottom { return below }
        let above = rect.minY - gap - height
        if above >= top { return above }
        // 两边都放不下（列表比面板还高）：贴着余量大的那一侧，超出的部分靠滚动。
        return (bottom - below) >= (rect.minY - top) ? below : top
    }

    /// 浮层实际能占的高度。
    private func popupRoom(row rect: CGRect, y: CGFloat, containerHeight: CGFloat) -> CGFloat {
        max(120, containerHeight - 8 - y)
    }

    /// 浮层的高度。
    ///
    /// 选项行高是固定的，所以能算出来——**不去量**：浮层伸出面板时会被裁，
    /// 量到的就是裁过之后的值，「放不下→翻上去」的判断会跟着反复横跳。
    private func popupHeight(for row: Row) -> CGFloat {
        // 上下内边距（WFSpace.xs × 2）+ 分隔线。估大了会让明明放得下的浮层翻上去。
        let chrome: CGFloat = 12
        switch row {
        case .date:
            // 内容是定高的：分段控件、一行下拉（最多三个，仍在同一行里）、
            // 忽略年份、按钮，逐段相加就是 `datePopupContentHeight`。
            return Self.datePopupContentHeight + chrome
        case .reminder:
            return CGFloat(7 + (isCustomReminder ? 1 : 0)) * Self.popupRowHeight + chrome
        case .recurrence:
            return CGFloat(6 + (repeatSelection == .custom ? 1 : 0)) * Self.popupRowHeight + chrome
        case .kind:
            return 4 * Self.popupRowHeight + chrome
        case .display:
            return 22 + 5 * Self.popupRowHeight + chrome
        }
    }

    /// 放不下时给浮层套一层滚动，别把内容裁掉。
    @ViewBuilder
    private func popupBody(for row: Row, maxHeight: CGFloat) -> some View {
        if popupHeight(for: row) > maxHeight {
            ScrollView { editor(for: row) }.frame(height: maxHeight)
        } else {
            editor(for: row)
        }
    }

    @ViewBuilder
    private func editor(for row: Row) -> some View {
        switch row {
        case .date: dateEditor
        case .reminder: reminderEditor
        case .recurrence: repeatEditor
        case .kind: kindEditor
        case .display: displayEditor
        }
    }

    /// 行 → 面板坐标系里**字段**的位置（不含左侧标签列）。下拉浮层要靠它定位。
    ///
    /// 刻意**不**用整行的 bounds：整行 = 54pt 标签 + 6pt 间距 + 字段，拿它定宽会让浮层
    /// 宽出 60pt、左边还盖住标签。参考图里浮层与字段左右对齐。
    ///
    /// 另注（踩过的坑）：`.anchorPreference` 是**覆盖**而不是合并——同 key 挂在 HStack 上的
    /// 那份会把子树（含 Button）挂的值整个盖掉，`reduce` 里逐字段并也没用（实测浮层宽度
    /// 纹丝不动）。所以这个锚点只挂一处：字段 Button。
    private struct FieldAnchorKey: PreferenceKey {
        static let defaultValue: [Row: Anchor<CGRect>] = [:]
        static func reduce(value: inout [Row: Anchor<CGRect>],
                           nextValue: () -> [Row: Anchor<CGRect>]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// 弹层外壳。
    ///
    /// 参考图里下拉是**浮在面板上的弹框**：带圆角边框和投影，盖住下面的行；左右与
    /// **字段**对齐（不是与整行）。原来是行内展开（会把面板撑高、把底部按钮推走），
    /// 用户明确指出「不是弹框、还把编辑框撑大了、边框也没有」，所以改成 overlay。
    private func popup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.vertical, WFSpace.xs)
            .frame(maxWidth: .infinity)
            .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(WFColors.border)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }

    // MARK: 名称

    private var nameRow: some View {
        HStack(spacing: WFSpace.lg) {
            ZStack {
                Circle().fill(countdownColor(colorIndex))
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .overlay(alignment: .bottomTrailing) {
                // 参考图里图标右下角挂着一支小铅笔（表示「点它换图标/颜色」）。
                Image(systemName: "pencil")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WFColors.secondaryText)
                    .frame(width: 13, height: 13)
                    .background(WFColors.canvas, in: Circle())
                    .overlay { Circle().stroke(WFColors.border) }
            }

            TextField(kind.namePlaceholder, text: $name)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .onSubmit { if canSubmit { submit() } }

            // 「节日」类型多一个目录入口：这一类的名称本来就是**从目录里挑**的，
            // 而目录里的规则（尤其除夕的 `.lunarEve`）没法靠手选月/日复现——
            // 在接上它之前，`CountdownFestival` 那 19 条谁都用不到。
            //
            // 做成名称框**旁边**的下拉而不是替换名称框：手输仍然可用。存量里可能
            // 有目录之外的节日名（比如地方性节日），为了用上目录而被迫改成目录项
            // 是净损失。
            if kind == .festival {
                festivalPicker
            }

            // 参考图里名称框右端有一个「书签里嵌一颗星」的按钮，点开是**图标选择器**。
            // 之前这里被猜成了备注的展开开关（图上确实看不出行为），代价是面板上凭空
            // 多出一个参考图里没有的备注行。真机点开确认行为之后改成图标选择器。
            //
            // 字形取舍：参考图是「书签 + 星」，SF Symbols 没有这个组合
            // （`bookmark.star` / `bookmark.star.fill` 都查过，不存在），
            // 取形状最接近的 `bookmark`——丝带的形状一样，只是里面没有那颗星。
            Button {
                symbolPickerOpen.toggle()
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 13))
                    .foregroundStyle(symbolPickerOpen ? WFColors.accent : WFColors.secondaryText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("图标")
            .accessibilityLabel("图标")
            .background(AnchoredPropertyPanel(isPresented: $symbolPickerOpen, width: 240) {
                symbolPicker
            })
        }
    }

    /// 图标选择器（名称框右端按钮的浮层）。
    ///
    /// 参考图里它是一列**带名字的预设图标**（旅行 / 演唱会 / 发工资 / 交房租 /
    /// 信用卡还款 / 房贷还款 / 保险缴费 / 定期体检 / 宠物体检 / 驾驶证到期 /
    /// 签证到期 / 考试 / 开学），每个预设自带图形与配色。
    ///
    /// 我们的域模型只存一个 SF Symbol 名（`symbol`），**没有「预设场景」这个概念**，
    /// 所以这里给的是符号网格——**这是取舍，不是对齐**。颜色仍在卡片菜单的
    /// 「样式」里改；面板里只挑图标，与参考图「点一下换个图标」的用法一致。
    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: WFSpace.md) {
            Text("图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: WFSpace.sm), count: 6),
                      spacing: WFSpace.sm) {
                ForEach(CountdownEvent.symbolOptions, id: \.self) { option in
                    Button {
                        symbol = option
                        symbolPickerOpen = false
                    } label: {
                        Image(systemName: option)
                            .font(.system(size: 14))
                            .foregroundStyle(option == symbol ? WFColors.accent : WFColors.secondaryText)
                            .frame(width: 30, height: 28)
                            .background(option == symbol ? WFColors.selection : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option)
                }
            }
        }
        .padding(WFSpace.lg)
        .frame(width: 240)
    }

    /// 「节日」类型的目录下拉（19 条，农历/公历规则都已在域模型里备好）。
    ///
    /// 这是 `CountdownFestival.all` 唯一的消费点。之前它整张表没有任何调用方，
    /// 连带 `.lunarEve`（除夕）也没有任何构造路径——域模型、投影、编辑器三处都在
    /// 认真支持它，却没有一条路能造出来。
    private var festivalPicker: some View {
        Menu {
            ForEach(CountdownFestival.all) { option in
                Button(option.name) { applyFestival(option) }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("从节日目录选择")
        .accessibilityLabel("选择节日")
    }

    // MARK: 属性行

    private func propertyRow(_ row: Row, label: String, value: String, isPlaceholder: Bool) -> some View {
        HStack(spacing: WFSpace.inline) {
            Text(label)
                .font(WFType.supporting)
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: Self.labelWidth, alignment: .leading)
            Button {
                let next: Row? = openRow == row ? nil : row
                // 每次打开日期浮层都从**已确定**的那份重新拷一份来编辑，
                // 这样「取消」不需要回滚——没按确定就什么也没发生。
                if next == .date { editing = draft }
                openRow = next
            } label: {
                HStack(spacing: WFSpace.xs) {
                    Text(value)
                        .font(WFType.supporting)
                        .foregroundStyle(isPlaceholder ? WFColors.tertiaryText : WFColors.text)
                        .lineLimit(1)
                    Spacer(minLength: WFSpace.xs)
                    Image(systemName: openRow == row ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.tertiaryText)
                }
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.rowHeight)
                .frame(maxWidth: .infinity)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(WFColors.border)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label)：\(value)")
            // 浮层按**字段**定位（见 `FieldAnchorKey`），不是按整行。
            .anchorPreference(key: FieldAnchorKey.self, value: .bounds) { [row: $0] }
        }
    }

    private var dateRow: some View {
        propertyRow(.date, label: "日期",
                    value: dateText ?? "选择日期", isPlaceholder: dateText == nil)
    }

    @ViewBuilder
    private var dateEditor: some View {
        // 与其余几行的浮层不同，这里**不是「点一个就收起」**：「忽略年份」是个开关，
        // 公历/农历切换后月/日的候选也跟着变，需要一个明确的提交动作。参考图里
        // 这个浮层自己带一对「取消 / 确定」，照做。
        //
        // 用 `VStack(spacing: 0)` + 逐段 `.padding(.top,)` 而不是一个统一的 spacing：
        // 参考图的段间距是不等的（见上面几个常量的注释），统一 spacing 表达不了。
        VStack(spacing: 0) {
            Picker("", selection: $editing.isLunar) {
                Text("公历").tag(false)
                Text("农历").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: Self.dateSegmentWidth)
            .frame(maxWidth: .infinity)
            .padding(.top, Self.datePopupTopInset)

            // 勾了「忽略年份」就只剩月/日两个字段，它们各自撑满一半——参考图里
            // 字段是**等宽铺满**这一行的，不是各自缩到文字宽再居中。
            HStack(spacing: WFSpace.control) {
                if !editing.ignoresYear { yearMenu }
                monthMenu
                dayMenu
            }
            .padding(.top, Self.dateSegmentGap)

            HStack {
                Toggle("忽略年份", isOn: $editing.ignoresYear)
                    .toggleStyle(.checkbox)
                    .font(WFType.supporting)
                Spacer(minLength: 0)
            }
            .padding(.top, Self.dateFieldGap)

            // 参考图这里**没有分隔线**：按钮靠段间距（28）与上面分开，不靠线。
            //
            // 按钮文案带「日期」二字是有意的：浮层打开时，sheet 底部那对
            // 「取消 / 确定」也在屏幕上，两对同名会让人分不清哪个撤的是日期、
            // 哪个撤的是整条记录。
            //
            // 不再单独写 `.accessibilityLabel`：文案即标签，一处写就够了。
            // 之前两处各写一份（读屏叫「取消日期」、眼睛看到「取消」），
            // 正是这个漂移造成了同名歧义。
            HStack(spacing: WFSpace.sm) {
                Spacer(minLength: 0)
                Button("取消日期") { openRow = nil }
                    .buttonStyle(.bordered)
                Button("确定日期") {
                    // 此刻才算数：日期行与「添加」的可用性都看 `draft`。
                    // 新建时 `editing.isSet` 还是 false（浮层打开时从空草稿拷的），
                    // 按下确定就等于「用户选好了日期」，补上。
                    var confirmed = editing
                    confirmed.isSet = true
                    draft = confirmed
                    openRow = nil
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, Self.dateButtonGap)
            .padding(.bottom, Self.datePopupBottomInset)
        }
        // 浮层外壳只给上下内边距（其余几行的浮层是满宽的选项列表，贴边才对）。
        // 日期浮层里是**字段**，字段贴到圆角边上会被切掉角——左右各让 16。
        .padding(.horizontal, WFSpace.lg)
        // 切公历/农历、换月份都会让原来的「日」越界（农历没有 31 日，
        // 公历 2 月没有 30 日），夹一下。
        .onChange(of: editing.isLunar) { _, _ in clampDraft() }
        .onChange(of: editing.month) { _, _ in clampDraft() }
        .onChange(of: editing.year) { _, _ in clampDraft() }
        .onChange(of: editing.ignoresYear) { _, ignores in
            // 「忽略年份」其实就是「每年重复」的另一面：勾上 = 不带年份（每年一次），
            // 勾掉 = 具体某一年。跟着改，免得留下「每年 + 带年份」这种自相矛盾的组合。
            if ignores, repeatSelection == .never { repeatSelection = .yearly }
            if !ignores, repeatSelection == .yearly { repeatSelection = .never }
        }
    }

    /// 浮层里的一个月/日/年下拉。
    ///
    /// 参考图里它是**中性灰底、无描边、文字左对齐、右端一个细箭头**的字段。
    /// 不用 `Picker(.menu)`：原生那颗会被全局 `.tint(WFColors.accent)`（见
    /// `WorkFollowApp`）染成强调色底 + 居中文字，与参考图差得远。所以用 `Menu`
    /// 自绘 label，候选项交给内嵌的 `Picker(.inline)`——勾选态由它负责。
    private func dateMenu<Options: View>(_ label: String, accessibility: String,
                                         @ViewBuilder options: () -> Options) -> some View {
        Menu {
            options()
        } label: {
            HStack(spacing: WFSpace.xs) {
                Text(label)
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.overlayText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WFColors.overlayTertiaryText)
            }
            .padding(.horizontal, WFSpace.control)
            .frame(maxWidth: .infinity)
            .frame(height: Self.dateFieldHeight)
            .background(WFColors.fieldFill, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // `Menu` 自己那颗内部按钮不接 `.accessibilityLabel`（实测读到的 desc 是空的）。
        // 用 `.combine` 而不是 `.ignore`：`.ignore` 会把元素降成 `AXUnknown`，
        // 标签是出来了，但 `AXPress` 变成静默 no-op——VoiceOver 也就打不开它了。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
    }

    private var monthMenu: some View {
        dateMenu(Self.monthLabel(editing.month, lunar: editing.isLunar),
                 accessibility: "月：\(Self.monthLabel(editing.month, lunar: editing.isLunar))") {
            Picker("", selection: $editing.month) {
                ForEach(1...12, id: \.self) { month in
                    Text(Self.monthLabel(month, lunar: editing.isLunar)).tag(month)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var dayMenu: some View {
        dateMenu(Self.dayLabel(editing.day, lunar: editing.isLunar),
                 accessibility: "日：\(Self.dayLabel(editing.day, lunar: editing.isLunar))") {
            Picker("", selection: $editing.day) {
                ForEach(1...Self.daysInDraftMonth(editing), id: \.self) { day in
                    Text(Self.dayLabel(day, lunar: editing.isLunar)).tag(day)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// 「忽略年份」没勾时才出现。往前 120 年够放生日，往后 50 年够放远期倒数日。
    private var yearMenu: some View {
        dateMenu("\(editing.year)年", accessibility: "年：\(editing.year)年") {
            Picker("", selection: $editing.year) {
                ForEach(Self.yearChoices, id: \.self) { year in
                    Text("\(year)年").tag(year)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    // MARK: 日期草稿

    /// 把一条已有规则摊回浮层草稿；`event == nil`（新建）时给一个**未选中**的初值。
    ///
    /// 初值的「公历/农历」与「忽略年份」跟类型走：节日按农历、且不带年份（春节
    /// 就是正月初一）；其余类型按公历、带年份——纪念日/倒数日要的是具体某一天，
    /// 生日还得靠那个年份算岁数。
    private static func makeDraft(for event: CountdownEvent?, kind: CountdownKind,
                                  calendar: Calendar, today: Date) -> DateDraft {
        makeDraft(forRule: event?.rule, kind: kind, calendar: calendar, today: today)
    }

    /// 按规则填草稿；`rule == nil` = 新建、还没选日期。
    ///
    /// 单独抽出来是为了让「从节日目录选一条」也能走同一套映射——目录里给的是
    /// `CountdownRule`，不是一个 `CountdownEvent`。两处各写一份映射，迟早会漂。
    private static func makeDraft(forRule rule: CountdownRule?, kind: CountdownKind,
                                  calendar: Calendar, today: Date) -> DateDraft {
        let currentYear = calendar.component(.year, from: today)
        guard let rule else {
            let lunar = kind == .festival
            let lunarParts = CountdownLunar.lunarComponents(of: today, calendar: calendar)
            return DateDraft(
                isSet: false,
                isLunar: lunar,
                month: lunar ? (lunarParts?.month ?? 1) : calendar.component(.month, from: today),
                day: lunar ? (lunarParts?.day ?? 1) : calendar.component(.day, from: today),
                year: currentYear,
                ignoresYear: lunar)
        }
        switch rule {
        case .solarYearly(let month, let day):
            return DateDraft(isSet: true, isLunar: false, month: month, day: day,
                             year: currentYear, ignoresYear: true)
        case .lunarYearly(let month, let day):
            return DateDraft(isSet: true, isLunar: true, month: month, day: day,
                             year: currentYear, ignoresYear: true)
        case .lunarOnce(let month, let day, let year):
            return DateDraft(isSet: true, isLunar: true, month: month, day: day,
                             year: year, ignoresYear: false)
        case .lunarEve:
            // 除夕没有固定的农历月/日，草稿只能填它**下一次**的月/日；靠
            // `draftDeviates` 保证没动过时保存回原规则。
            let anchor = CountdownEvent.occurrence(of: rule, onOrAfter: today,
                                                   calendar: calendar)
            let parts = CountdownLunar.lunarComponents(of: anchor, calendar: calendar)
                ?? (month: 12, day: 30)
            return DateDraft(isSet: true, isLunar: true, month: parts.month, day: parts.day,
                             year: calendar.component(.year, from: anchor), ignoresYear: true)
        case .birthday(let month, let day, let year):
            return DateDraft(isSet: true, isLunar: false, month: month, day: day,
                             year: year, ignoresYear: false)
        case .once(let date):
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return DateDraft(isSet: true, isLunar: false,
                             month: parts.month ?? 1, day: parts.day ?? 1,
                             year: parts.year ?? currentYear, ignoresYear: false)
        case .daily(let lunar, let anchor), .weekly(_, let lunar, let anchor),
             .monthly(_, let lunar, let anchor), .interval(_, let lunar, let anchor):
            // 这几种节奏的「日期」行显示的是锚点，草稿也照锚点填。
            let solar = calendar.dateComponents([.year, .month, .day], from: anchor)
            let lunarParts = CountdownLunar.lunarComponents(of: anchor, calendar: calendar)
            return DateDraft(
                isSet: true,
                isLunar: lunar,
                month: lunar ? (lunarParts?.month ?? 1) : (solar.month ?? 1),
                day: lunar ? (lunarParts?.day ?? 1) : (solar.day ?? 1),
                year: solar.year ?? currentYear,
                ignoresYear: false)
        }
    }

    /// 把草稿的月/日夹进当前模式的合法范围：农历没有 31 日，公历 2 月没有 30 日。
    private func clampDraft() {
        editing.month = min(max(editing.month, 1), 12)
        editing.day = min(max(editing.day, 1), Self.daysInDraftMonth(editing))
    }

    /// 草稿当前模式下这个月有几天。农历按 30 天封顶（小月廿九、大月三十）——
    /// 具体到某年某月有没有三十要查农历表，这里不细分，选了没有的日子由
    /// `CountdownEvent.lunarDate` 返回 nil、卡片退回今天。
    private static func daysInDraftMonth(_ draft: DateDraft) -> Int {
        if draft.isLunar { return 30 }
        let calendar = Calendar.current
        guard let first = calendar.date(from: DateComponents(year: draft.year,
                                                             month: draft.month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 31 }
        return range.count
    }

    private static func monthLabel(_ month: Int, lunar: Bool) -> String {
        lunar ? CountdownLunar.monthName(month) : "\(month)月"
    }

    private static func dayLabel(_ day: Int, lunar: Bool) -> String {
        lunar ? CountdownLunar.dayName(day) : "\(day)日"
    }

    /// 年份候选。往前 120 年够放生日，往后 50 年够放远期倒数日。
    private static var yearChoices: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 120)...(current + 50))
    }

    /// 「提醒」行。参考图里空集显示的是黑色的「无」，不是灰色占位。
    private var reminderRow: some View {
        propertyRow(.reminder, label: "提醒",
                    value: CountdownEvent.reminderText(Array(reminders)) ?? "无",
                    isPlaceholder: false)
    }

    /// 「提醒」下拉，照参考图：
    /// `无 / 当天 (09:00) / 提前 1 天 (09:00) / 提前 2 天 (09:00) /
    ///  提前 3 天 (09:00) / 提前 1 周 (09:00)` ── `自定义`。
    ///
    /// 「无」= 空集；中间几项是**多选**（参考图的「添加」面板实测默认值是
    /// `当天, 提前 3 天` 两条，所以不是单选）。
    private var reminderEditor: some View {
        VStack(spacing: 0) {
            optionRow("无", checked: reminders.isEmpty) {
                reminders.removeAll()
                openRow = nil
            }
            ForEach(CountdownEvent.reminderChoices, id: \.self) { minutes in
                optionRow(CountdownEvent.reminderOptionLabel(minutes),
                          checked: reminders.contains(minutes)) {
                    if !reminders.insert(minutes).inserted { reminders.remove(minutes) }
                }
            }
            optionSeparator
            optionRow("自定义", checked: isCustomReminder) {
                reminders = [customReminderDays * CountdownEvent.minutesPerDay]
            }
            if isCustomReminder {
                Stepper(value: $customReminderDays, in: 1...365) {
                    Text("提前 \(customReminderDays) 天 (\(CountdownEvent.reminderTimeText))")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.text)
                }
                .font(WFType.supporting)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.popupRowHeight)
                .onChange(of: customReminderDays) { _, days in
                    reminders = [days * CountdownEvent.minutesPerDay]
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 选中了预设项以外的整天提醒，就算「自定义」。
    private var isCustomReminder: Bool {
        let presets = Set(CountdownEvent.reminderChoices)
        return reminders.contains { !presets.contains($0) }
    }

    private var optionSeparator: some View {
        Divider().padding(.vertical, 2)
    }

    /// 「重复」行。参考图里的值是带括注的：`每周（周二）` / `每月（初一）` / `每年（正月初一）`。
    private var repeatRow: some View {
        propertyRow(.recurrence, label: "重复",
                    value: repeatLabel(repeatSelection),
                    isPlaceholder: false)
    }

    /// 括注是算出来的（见 `CountdownRepeat.label`）。规则优先用面板里**当前**的
    /// 选择，编辑时退回原记录——不然刚换完日期，括注还停在旧锚点上。
    private func repeatLabel(_ value: CountdownRepeat) -> String {
        CountdownRepeat.label(value, rule: resolvedRule ?? original?.rule,
                              asOf: Date(), calendar: calendar)
    }

    /// 「重复」下拉，照参考图：
    /// `无 / 每天 / 每周（周二）/ 每月（初一）/ 每年（正月初一）` ── `自定义`。
    ///
    /// 「自定义」在参考图里点开会是什么样**没有截图**，这里是自定的最小实现
    /// （「每 N 天」的步进器），属于**取舍**，不是对齐结果。
    private var repeatEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownRepeat.allCases) { option in
                if option == .custom { optionSeparator }
                optionRow(repeatLabel(option), checked: repeatSelection == option) {
                    repeatSelection = option
                    openRow = nil
                }
            }
            if repeatSelection == .custom {
                Stepper(value: $customIntervalDays, in: 1...365) {
                    Text("每 \(customIntervalDays) 天")
                        .font(WFType.supporting)
                        .foregroundStyle(WFColors.text)
                }
                .font(WFType.supporting)
                .padding(.horizontal, WFSpace.sm)
                .frame(height: Self.popupRowHeight)
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var kindRow: some View {
        propertyRow(.kind, label: "类型", value: kind.title, isPlaceholder: false)
    }

    private var kindEditor: some View {
        VStack(spacing: 0) {
            ForEach(CountdownKind.allCases) { option in
                optionRow(option.title, checked: kind == option) {
                    applyKind(option)
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    private var displayRow: some View {
        propertyRow(.display, label: "显示", value: smartListDisplay.rowText, isPlaceholder: false)
    }

    /// 「显示」下拉：一个「在智能清单中」分组标题，下面五项
    /// （当天显示 / 提前 3 天显示 / 提前 7 天显示 / 一直显示 / 不显示）。
    private var displayEditor: some View {
        VStack(spacing: 0) {
            Text(CountdownSmartListDisplay.groupTitle)
                .font(WFType.caption)
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, WFSpace.sm)
                .padding(.top, WFSpace.sm)
                .padding(.bottom, WFSpace.xs)
            ForEach(CountdownSmartListDisplay.allCases) { option in
                optionRow(option.title, checked: smartListDisplay == option) {
                    smartListDisplay = option
                    openRow = nil
                }
            }
        }
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 6))
    }

    /// 「显示岁数」这一行参考图里是**开关在左、文字在右**（和上面几行
    /// 「标签在左、控件在右」正好相反），而且开关落在标签列上、不再缩进。
    private var ageRow: some View {
        HStack(spacing: WFSpace.sm) {
            Toggle("", isOn: $showsAge)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("显示岁数")
            Text("显示岁数")
                .font(WFType.supporting)
                .foregroundStyle(WFColors.text)
            Spacer(minLength: 0)
        }
        .frame(height: Self.rowHeight)
    }

    private func optionRow(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: WFSpace.sm) {
                Text(title).font(WFType.supporting).lineLimit(1)
                Spacer(minLength: WFSpace.xs)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, WFSpace.sm)
            .frame(height: Self.popupRowHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: Self.rowGap) {
            Spacer()
            // 宽度得给到 label 上：`.frame(minWidth:)` 加在 Button 外面只撑布局框，
            // 撑不开 `.bordered` 自己画的那颗胶囊（实测仍是 54 宽）。
            Button { dismiss() } label: {
                Text("取消").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button { submit() } label: {
                // 参考图：新建面板的确认按钮是「添加」，编辑面板是「确定」。
                Text(isNew ? "添加" : "确定").frame(width: Self.buttonWidth - 24, height: 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 32)
    }

    // MARK: 派生

    /// 「日期」行显示的文本。
    ///
    /// 草稿没被动过时直接用原规则的写法：`除夕` 折成「腊月三十」再回显就失真了，
    /// 而它恰恰是草稿表达不了的那一类。
    private var dateText: String? {
        guard draft.isSet else { return nil }
        if !draftDeviates, let text = baseline.rule?.dateText { return text }
        return draftBaseRule?.dateText
    }

    /// 草稿偏离打开时的初值没有。
    private var draftDeviates: Bool { draft != baseline.draft }

    /// 草稿本身对应的基准规则：勾了「忽略年份」就是每年重复的月/日，
    /// 否则是具体某一天。「重复」再由 `combinedRule` 叠上去。
    private var draftBaseRule: CountdownRule? {
        guard draft.isSet else { return nil }
        if draft.ignoresYear {
            return draft.isLunar
                ? .lunarYearly(month: draft.month, day: draft.day)
                : .solarYearly(month: draft.month, day: draft.day)
        }
        if draft.isLunar {
            return .lunarOnce(month: draft.month, day: draft.day, year: draft.year)
        }
        guard let date = calendar.date(from: DateComponents(
            year: draft.year, month: draft.month, day: draft.day)) else { return nil }
        return .once(calendar.startOfDay(for: date))
    }

    /// 提交时的规则：把「日期」与「重复」两行合成一条。
    private var resolvedRule: CountdownRule? {
        guard draft.isSet else { return nil }
        // 没动过日期就沿用基准里的规则——`除夕` 这类没法从月/日重建的规则只有这条
        // 路才能原样活下来。基准同时覆盖两种来源：打开面板时的 `original?.rule`，
        // 以及刚从节日目录选中的那条（`applyFestival` 把两者一起换掉）。
        guard let base = (!draftDeviates ? baseline.rule : nil) ?? draftBaseRule else { return nil }
        return combinedRule(base: base, repeatSelection: repeatSelection)
    }

    /// 把「日期」（`base`）与「重复」合成一条规则。
    ///
    /// `重复 = 每年` 时**原样返回 base**：节日的 `.lunarEve`（除夕）这类规则没法
    /// 从月/日重建，只能留着。其余节奏都要一个锚点——单次日期用日期本身，
    /// 节日用目录规则的下一次落点。
    private func combinedRule(base: CountdownRule, repeatSelection: CountdownRepeat) -> CountdownRule? {
        let anchor: Date
        let lunar: Bool
        switch base {
        case .once(let date):
            anchor = date
            lunar = false
        case .lunarYearly, .lunarEve, .lunarOnce:
            anchor = nextOccurrence(of: base)
            lunar = true
        default:
            anchor = nextOccurrence(of: base)
            lunar = false
        }
        switch repeatSelection {
        case .never:
            // 农历的具体某一天要**原样留着**：折成公历日期就再也回不到
            // 「农历2027年正月初一」这个写法了（那正是 `.lunarOnce` 存在的理由）。
            if case .lunarOnce = base { return base }
            return .once(anchor)
        case .daily:
            return .daily(lunar: lunar, anchor: anchor)
        case .weekly:
            // 参考图的括注也是「今天」的星期（见 `CountdownRepeat.label`），
            // 这里让规则与括注指向同一天，免得两处各说各话。
            return .weekly(weekday: calendar.component(.weekday, from: Date()),
                           lunar: lunar, anchor: anchor)
        case .monthly:
            let day = lunar
                ? (CountdownLunar.lunarComponents(of: anchor, calendar: calendar)?.day ?? 1)
                : (calendar.dateComponents([.day], from: anchor).day ?? 1)
            return .monthly(day: day, lunar: lunar, anchor: anchor)
        case .yearly:
            if case .once(let date) = base {
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                guard let month = parts.month, let day = parts.day else { return .once(date) }
                // 生日要把出生年一起带上，岁数才算得出来。
                if kind == .birthday, let year = parts.year {
                    return .birthday(month: month, day: day, birthYear: year)
                }
                return .solarYearly(month: month, day: day)
            }
            // 农历同理：「每年」= 不带年份，落回 `.lunarYearly`。
            if case .lunarOnce(let month, let day, _) = base {
                return .lunarYearly(month: month, day: day)
            }
            return base
        case .custom:
            return .interval(days: customIntervalDays, lunar: lunar, anchor: anchor)
        }
    }

    private func nextOccurrence(of rule: CountdownRule) -> Date {
        CountdownEvent.occurrence(of: rule, onOrAfter: Date(), calendar: calendar)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedRule != nil
    }

    /// 切类型：换图标与颜色，并把「重复」带回该类型的默认值。
    /// 日期一律清空——参考图里换完类型「日期」仍是「选择日期」，
    /// 而且公历日期与农历节日本来就不是同一套落点，留着上一个只会误导。
    private func applyKind(_ next: CountdownKind) {
        kind = next
        symbol = next.defaultSymbol
        colorIndex = next.defaultColorIndex
        repeatSelection = next.defaultRepeat
        // 日期一律清空——参考图里换完类型「日期」仍是「选择日期」，
        // 而且公历日期与农历节日本来就不是同一套落点，留着上一个只会误导。
        let fresh = Self.makeDraft(for: nil, kind: next, calendar: calendar, today: Date())
        // 换类型要把目录选中的规则一起丢掉：留着它的话，从「节日→春节」换成
        // 「倒数日」，名称与日期都清了，规则却还是农历正月初一。
        baseline = Baseline(draft: fresh, rule: nil)
        draft = fresh
        editing = fresh
    }

    /// 从节日目录选一条：填名称，并把规则**原样**记进基准。
    ///
    /// 只把月/日填进草稿是不够的：除夕（`.lunarEve`）没有固定的农历月/日——它落在
    /// 腊月廿九或三十，逐年不同。折成月/日再重建，某些年份会落到不存在的日子上，
    /// 而且再也回不到「除夕」这个写法。
    ///
    /// 草稿照目录规则的落点填：日期行要有文本可显示，「添加」也要能点亮。
    /// 用户在日期行手动改过之后 `draftDeviates` 变真，基准里的规则就让位给草稿。
    private func applyFestival(_ option: CountdownFestival.Option) {
        name = option.name
        let filled = Self.makeDraft(forRule: option.rule, kind: kind,
                                    calendar: calendar, today: Date())
        // 基准与草稿**一起**换。只换草稿的话 `draftDeviates` 立刻为真，目录给的
        // 规则会被旁路——除夕就是这么被折成腊月廿九的。
        baseline = Baseline(draft: filled, rule: option.rule)
        draft = filled
        editing = filled
        openRow = nil
    }

    private func submit() {
        guard let rule = resolvedRule else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var original {
            original.name = trimmed
            original.kind = kind
            original.rule = rule
            original.symbol = symbol
            original.colorIndex = colorIndex
            original.reminderOffsets = Array(reminders)
            original.smartListDisplay = smartListDisplay
            // 老字段跟着新字段走，存量读的是它。
            original.showsInSmartList = smartListDisplay.showsInSmartList
            original.showsAge = showsAge
            // 刻意**不**碰 `original.note`：面板里已经没有备注入口了，
            // 这里若照旧写 `note` 就会把卡片菜单写进去的备注抹掉。
            store.update(original)
        } else {
            store.add(name: trimmed, kind: kind, rule: rule, symbol: symbol, colorIndex: colorIndex,
                      reminderOffsets: Array(reminders),
                      smartListDisplay: smartListDisplay,
                      showsAge: showsAge)
        }
        dismiss()
    }
}

// MARK: - 样式

/// 卡片菜单「样式」：只改符号与颜色，点即生效。参考图里这一项的界面不可见，
/// 这里是自定的最小实现（顺带补上了添加面板里那个改不了图标的缺口）。
struct CountdownStyleView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var symbol: String
    @State private var colorIndex: Int

    /// 预览卡用的「今天」。弹窗是短命的，开窗时算一次就够，不必每分钟跟着走。
    private let today: Date

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _symbol = State(initialValue: event.safeSymbol)
        _colorIndex = State(initialValue: event.colorIndex)
        today = Date()
    }

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: WFSpace.sm), count: 6)

    /// 预览卡：**与真卡片同一份渲染**（`CountdownCardFace`）+ 同一组尺寸，
    /// 所以是 1:1 的「所见即所得」，不是缩略图。
    ///
    /// 参照实现的第二步也有一张预览卡，但它是**按比例缩小**的（约 202×137pt）。
    /// 我们按原尺寸画，理由是卡片的内边距（上 34 / 下 30）与字号全是照参照图量出来的，
    /// 缩小就得另配一套数，两套数迟早会漂——而预览卡一旦和真卡片不一样，就没有意义了。
    /// 这是取舍，不是对齐。
    ///
    /// `symbol` / `colorIndex` 传的是**草稿值**，所以点颜色/图标时这里立刻跟着变。
    private var preview: some View {
        CountdownCardFace(event: event,
                          symbol: symbol,
                          colorIndex: colorIndex,
                          projection: event.projection(asOf: today, calendar: .current),
                          magnitude: event.magnitude(asOf: today,
                                                     unit: event.effectiveDisplayUnit,
                                                     calendar: .current),
                          ageText: event.ageText(asOf: today, calendar: .current))
            .padding(.horizontal, WFSpace.md)
            .padding(.top, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity)
            .frame(height: 193)
            .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(WFColors.overlayBorder)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("样式").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            VStack(alignment: .leading, spacing: WFSpace.md) {
                preview
                Text("颜色").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                // 12 格挤一行：间距取 `xs`（4）而不是 `sm`（8）。参照实现实测的格间距
                // 约 3.3pt，`xs` 反而更接近它；`sm` 会撑到 352pt，这一行放不下。
                HStack(spacing: WFSpace.xs) {
                    ForEach(0..<CountdownEvent.paletteSize, id: \.self) { index in
                        Button {
                            colorIndex = index
                            apply()
                        } label: {
                            ZStack {
                                Circle().fill(countdownColor(index)).frame(width: 22, height: 22)
                                if index == colorIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("颜色 \(index + 1)")
                    }
                    Spacer(minLength: 0)
                }
                Text("图标").font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
                LazyVGrid(columns: columns, spacing: WFSpace.sm) {
                    ForEach(CountdownEvent.symbolOptions, id: \.self) { option in
                        Button {
                            symbol = option
                            apply()
                        } label: {
                            Image(systemName: option)
                                .font(.system(size: 14))
                                .foregroundStyle(option == symbol ? WFColors.accent : WFColors.secondaryText)
                                .frame(width: 34, height: 30)
                                .background(option == symbol ? WFColors.selection : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                    }
                }
            }
            .padding(WFSpace.xl)
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        // 350 = 左右内边距各 20 + 预览卡 310（**与真卡片同宽**，1:1）。
        // 顺带让 12 格色板在 4pt 间距下正好排得下（12×22 + 11×4 = 308 ≤ 310）。
        .frame(width: 350)
        .background(WFColors.canvas)
    }

    private func apply() {
        store.setStyle(event.id, symbol: symbol, colorIndex: colorIndex)
    }
}

// MARK: - 备注

/// 卡片菜单「备注」。
struct CountdownNoteView: View {
    @ObservedObject var store: CountdownStore
    let event: CountdownEvent

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(store: CountdownStore, event: CountdownEvent) {
        self.store = store
        self.event = event
        _note = State(initialValue: event.note)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("备注").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            TextField("写点什么…", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(WFType.body)
                .lineLimit(6...12)
                .padding(WFSpace.md)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(WFColors.content, in: RoundedRectangle(cornerRadius: WFMetrics.corner))
                .overlay {
                    RoundedRectangle(cornerRadius: WFMetrics.corner).stroke(WFColors.border)
                }
                .padding(WFSpace.xl)
            Divider()
            HStack(spacing: WFSpace.sm) {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(.bordered)
                Button("保存") {
                    store.setNote(event.id, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 360)
        .background(WFColors.canvas)
    }
}

// MARK: - 已归档

/// 页头「更多 → 已归档」：恢复或彻底删除。
struct ArchivedCountdownsView: View {
    @ObservedObject var store: CountdownStore

    @Environment(\.dismiss) private var dismiss
    @State private var today = Date()

    var body: some View {
        VStack(spacing: 0) {
            // 参照物语言包：`archived_countdowns` = 已归档倒数纪念日
            Text("已归档倒数纪念日").font(.system(size: 14, weight: .semibold)).padding(.vertical, WFSpace.md)
            Divider()
            if store.archivedEvents.isEmpty {
                VStack(spacing: WFSpace.sm) {
                    // `no_archived_countdowns_dida` = 还没有已归档的纪念日
                    Text("还没有已归档的纪念日").font(WFType.body)
                }
                .foregroundStyle(WFColors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.archivedEvents) { event in
                            row(event)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(WFSpace.lg)
        }
        .frame(width: 380)
        .background(WFColors.canvas)
        .onAppear { today = Date() }
    }

    private func row(_ event: CountdownEvent) -> some View {
        let projection = event.projection(asOf: today)
        // 这一行**只有一句话的位置**，没有卡片上那个大数字兜底，所以必须用完整句：
        // 直接用 `captionPrefix` 会在屏幕上留下「距离 2026/10/2 还有」这种断句。
        let magnitude = event.magnitude(asOf: today, unit: event.effectiveDisplayUnit)
        return HStack(spacing: WFSpace.sm) {
            ZStack {
                Circle().fill(countdownColor(event.colorIndex))
                Image(systemName: event.safeSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.displayName).font(WFType.listTitle).lineLimit(1)
                Text(projection.sentence(with: magnitude)).font(WFType.caption)
                    .foregroundStyle(WFColors.secondaryText).lineLimit(1)
            }
            Spacer(minLength: WFSpace.sm)
            Button("恢复") { store.restore(event.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("删除") {
                if TaskNamePrompt.confirm("删除“\(event.displayName)”？", message: "删除后无法恢复。",
                                          action: "删除") {
                    _ = store.hardDelete(event.id)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, WFSpace.lg)
        .padding(.vertical, WFSpace.sm)
    }
}
