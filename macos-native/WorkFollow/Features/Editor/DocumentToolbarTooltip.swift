import AppKit
import SwiftUI

/// Real control geometry for render contracts; does not participate in sizing.
struct EditorToolbarCommandFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// 工具条悬停提示的状态：谁正被悬停，以及各控件在工具条坐标系里的矩形。
///
/// 为什么要自己收矩形：SwiftUI 的 `ScrollView` 会裁掉超出边界的内容，所以提示卡不能
/// 画在按钮自己的 `overlay` 里（工具条处在窗口底部，提示要往上出），只能由**工具条
/// 这一层**统一画，那就得知道每个按钮的横坐标。
@MainActor
final class ToolbarTooltipState: ObservableObject {
    /// 当前被悬停的控件标题；nil 表示没有。
    @Published var hovered: String?
    /// 键是标题（同一工具条内标题唯一）。
    @Published private(set) var frames: [String: CGRect] = [:]

    func updateFrame(_ frame: CGRect, for title: String) {
        guard frames[title] != frame else { return }
        frames[title] = frame
    }

    /// 指针落在一个控件上。
    func enter(_ title: String) { hovered = title }

    /// 指针离开一个控件。只有它仍是"当前那个"时才清空，避免从 A 划到 B 时闪一下。
    func leave(_ title: String) { if hovered == title { hovered = nil } }
}

/// 自绘的悬停提示。
///
/// 不用系统 `.help` 的原因有三个，都是需求里点明的：位置（系统提示固定出现在控件
/// **下方**，而编辑器工具条贴着窗口底部，下方没位置）、即时性（系统提示要等约 1 秒）、
/// 以及"每个按钮都要有"。样式则照抄原版 `TooltipThemeData`：底 `feedbackSurface`
/// （#2C2C2E）、字 `feedbackText`（#F5FFFFFF）11 medium、圆角 6（`WorkFollowRadii.sm`）。
struct DocumentToolbarTooltip {
    /// 工具条坐标系的名字：各控件在这里报矩形，提示层也画在这里。
    static let space = "document-toolbar-tooltip"
    /// 提示卡与控件之间的间距，以及卡自身的固定高度；样式与全局 `HoverTipCard` 一致。
    static let gap = HoverTipMetrics.gap
    static let cardHeight = HoverTipMetrics.height

    static func width(for title: String) -> CGFloat {
        HoverTipMetrics.width(for: title)
    }
}

/// 挂在工具条每个控件上：报矩形 + 收悬停。
private struct ToolbarTooltipTarget: ViewModifier {
    let title: String
    @ObservedObject var state: ToolbarTooltipState

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(DocumentToolbarTooltip.space))
                    Color.clear
                        .onAppear { state.updateFrame(frame, for: title) }
                        .onChange(of: frame) { _, value in state.updateFrame(value, for: title) }
                }
            }
            .onHover { inside in
                if inside { state.enter(title) } else { state.leave(title) }
            }
    }
}

/// 提示卡本身：深色小圆角面 + 11 medium 白字。
struct ToolbarTooltipCard: View {
    let title: String
    var maximumWidth: CGFloat = .infinity

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WFColors.tooltipText)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, HoverTipMetrics.horizontalPadding)
            .frame(height: DocumentToolbarTooltip.cardHeight)
            .frame(maxWidth: maximumWidth)
            .background(WFColors.tooltipSurface,
                        in: RoundedRectangle(cornerRadius: HoverTipMetrics.cornerRadius))
            .allowsHitTesting(false)
    }
}

extension View {
    func editorCommandFrame(_ id: String, space: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: EditorToolbarCommandFramesKey.self,
                                       value: [id: proxy.frame(in: .named(space))])
            }
        }
    }

    /// 给工具条控件挂上"指针一放上去就在**上方**显示功能名称"的提示。
    func toolbarTooltip(_ title: String, state: ToolbarTooltipState) -> some View {
        modifier(ToolbarTooltipTarget(title: title, state: state))
    }
}

// MARK: - 按钮往上弹出的两个小面板

/// 工具条上"点开会往上弹出小面板"的两个按钮：标题级别、插入时间。
///
/// 原版这两个不是系统菜单，而是 `showTaskEditorPopover` 锚定面板：宽度固定
/// （`DocumentEditorMetrics.headingPickerWidth` 150 / `timePickerWidth` 222）、
/// **在按钮上方**弹出（标题贴按钮左缘 `topStart`、时间贴按钮右缘 `topEnd`）、
/// 行高 36（`pickerRowHeight`）、上下各 6（`inlineGap`）内边距。
enum DocumentToolbarPicker: Equatable {
    case heading
    case time
    case textColor
    case highlightColor
    case alignment

    /// 与 `ToolbarTooltipState.frames` 的键一致——用它取按钮矩形来定位。
    var tooltipTitle: String {
        switch self {
        case .heading: "标题"
        case .time: "插入当前时间"
        case .textColor: "文字颜色"
        case .highlightColor: "高亮颜色"
        case .alignment: "对齐方式"
        }
    }

    /// 子面板的窗口标题（不参与界面文案）。
    var panelTitle: String {
        switch self {
        case .heading: "正文标题格式"
        case .time: "正文插入时间"
        case .textColor: "文字颜色"
        case .highlightColor: "背景颜色"
        case .alignment: "段落对齐"
        }
    }

    var width: CGFloat {
        switch self {
        case .heading: 150
        case .time: 222
        case .textColor, .highlightColor: Self.textColorWidth
        case .alignment: 150
        }
    }

    /// 标题贴按钮左缘，时间贴按钮右缘（原版 `topStart` / `topEnd`）。
    var alignedToEnd: Bool { self == .time }

    var rowHeight: CGFloat { 36 }
    var verticalPadding: CGFloat { 6 }

    var height: CGFloat {
        switch self {
        case .textColor, .highlightColor: Self.textColorHeight
        case .heading, .time, .alignment: rowHeight * CGFloat(titles.count) + verticalPadding * 2
        }
    }

    var titles: [String] {
        switch self {
        case .heading: return EditorCommandCatalog.headingPickerIDs.compactMap {
            EditorCommandCatalog.format($0)?.descriptor.title
        }
        case .time: return Self.timeValues()
        case .alignment: return DocumentAlignment.allCases.map(\.title)
        case .textColor, .highlightColor: return []
        }
    }

    /// 插入时的格式串；标题菜单则不需要。
    static let timeFormats = ["yyyy年M月d日 HH:mm", "yyyy年M月d日", "yyyy/M/d", "HH:mm"]

    /// Decorative labels never become document text or command identities.
    /// 字号档位在角标列显示实际 pt，标题显示 H₁–H₅（六级标题已移除）。
    static let headingBadges: [String: String] = [
        "format.body1": "12", "format.body2": "16", "format.body3": "18",
        "format.heading1": "H₁", "format.heading2": "H₂", "format.heading3": "H₃",
        "format.heading4": "H₄", "format.heading5": "H₅"
    ]

    func headingBadge(at index: Int) -> String? {
        guard self == .heading,
              EditorCommandCatalog.headingPickerIDs.indices.contains(index) else { return nil }
        return Self.headingBadges[EditorCommandCatalog.headingPickerIDs[index]]
    }

    /// 时间菜单显示的是**此刻的值**（原版把值当标签用：`2026年9月27日` /
    /// `2026年9月27日 21:05` / `21:05`），不是「日期 / 日期时间 / 时刻」这些词。
    static func timeValues(now: Date = Date()) -> [String] {
        timeFormats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            return formatter.string(from: now)
        }
    }

    /// 面板左上角在工具条坐标系里的横坐标：先按对齐方式贴边，再夹进工具条。
    func originX(anchor: CGRect, containerWidth: CGFloat) -> CGFloat {
        let raw = alignedToEnd ? anchor.maxX - width : anchor.minX
        return min(max(0, raw), max(0, containerWidth - width))
    }
}

/// Existing picker content keeps its row dimensions; the shared child host owns
/// shadow and focus, and the viewport scrolls when the window limits its height.
struct DocumentToolbarPickerCard: View {
    let picker: DocumentToolbarPicker
    /// 标题菜单用来给当前级别打勾；时间菜单没有选中项。
    let selectedIndex: Int?
    let onPick: (Int) -> Void
    var viewportHeight: CGFloat? = nil

    var body: some View {
        ScrollView {
        VStack(spacing: 0) {
            ForEach(Array(picker.titles.enumerated()), id: \.offset) { index, title in
                DocumentToolbarPickerRow(title: title,
                                         badge: picker.headingBadge(at: index),
                                         symbol: picker == .alignment ? DocumentAlignment.allCases[index].symbol : nil,
                                         selected: selectedIndex == index) {
                    onPick(index)
                }
            }
        }
        .padding(.vertical, picker.verticalPadding)
        .compactScrollbars()
        }
        .frame(height: viewportHeight ?? picker.height)
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius).stroke(WFColors.overlayBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
    }
}

/// 文字 / 高亮颜色调色板（仿 ima：无颜色 + 6×10 色格）。
struct DocumentColorPickerCard: View {
    let title: String
    /// 清空这一行：文字颜色是恢复默认墨色，背景色才是真正的“无颜色”。
    var defaultTitle = "无颜色"
    let selectedHex: String?
    let onPick: (String?) -> Void
    @State private var hovering: Int?

    private let columns = Array(repeating: GridItem(.fixed(20), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(WFColors.secondaryText)
            Button { onPick(nil) } label: {
                Text(defaultTitle)
                    .font(WFType.menu)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedHex == nil ? WFColors.accent : WFColors.border,
                                    lineWidth: selectedHex == nil ? 1.5 : 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.text)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(DocumentColorPalette.swatches) { swatch in
                    Button { onPick(swatch.hex) } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: NSColor(documentHex: swatch.hex) ?? .clear))
                            .frame(width: 20, height: 20)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(WFColors.border.opacity(swatch.hex == "#ffffff" ? 1 : 0.25),
                                            lineWidth: 0.5)
                            }
                            .overlay {
                                if selectedHex == swatch.hex {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(WFColors.accent, lineWidth: 1.5)
                                        .padding(-3)
                                } else if hovering == swatch.id {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(WFColors.secondaryText.opacity(0.5), lineWidth: 1)
                                        .padding(-2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside { hovering = swatch.id }
                        else if hovering == swatch.id { hovering = nil }
                    }
                    .help(swatch.hex)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: DocumentToolbarPicker.textColorWidth, height: DocumentToolbarPicker.textColorHeight,
               alignment: .top)
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius)
                .stroke(WFColors.overlayBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cornerRadius))
    }
}

extension DocumentToolbarPicker {
    static let textColorWidth: CGFloat = 260
    static let textColorHeight: CGFloat = 250
}

/// 面板里的一行：14 regular，选中转强调色并在行尾打勾，悬停染中性灰
/// （原版 `_PickerRow` + `WorkFollowInteractionStyles.overlay(menu: true)`）。
struct DocumentToolbarPickerRow: View {
    let title: String
    var badge: String? = nil
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 26, alignment: .leading)
                        .accessibilityHidden(true)
                }
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                        .frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(WFType.menu)
                    .foregroundStyle(selected ? WFColors.accent : WFColors.text)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15))
                        .foregroundStyle(WFColors.accent)
                }
            }
            .padding(.horizontal, WFSpace.relaxed)
            .frame(height: 36)
            .contentShape(Rectangle())
            .background(hovering ? WFColors.menuSelected : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
