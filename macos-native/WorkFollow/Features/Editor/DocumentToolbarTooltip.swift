import SwiftUI

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
    var frames: [String: CGRect] = [:]

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
    /// 提示卡与控件之间的间距，以及卡自身的固定高度（标题宽度不定，高度恒定）。
    static let gap: CGFloat = 6
    static let cardHeight: CGFloat = 22
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
                        .onAppear { state.frames[title] = frame }
                        .onChange(of: frame) { _, value in state.frames[title] = value }
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

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(WFColors.tooltipText)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, WFSpace.sm)
            .frame(height: DocumentToolbarTooltip.cardHeight)
            .background(WFColors.tooltipSurface,
                        in: RoundedRectangle(cornerRadius: WFSpace.inline))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}

extension View {
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

    /// 与 `ToolbarTooltipState.frames` 的键一致——用它取按钮矩形来定位。
    var tooltipTitle: String {
        self == .heading ? "标题" : "插入当前时间"
    }

    var width: CGFloat {
        self == .heading ? 150 : 222
    }

    /// 标题贴按钮左缘，时间贴按钮右缘（原版 `topStart` / `topEnd`）。
    var alignedToEnd: Bool { self == .time }

    var rowHeight: CGFloat { 36 }
    var verticalPadding: CGFloat { 6 }

    var height: CGFloat { rowHeight * CGFloat(titles.count) + verticalPadding * 2 }

    var titles: [String] {
        switch self {
        case .heading: return ["正文", "一级标题", "二级标题", "三级标题"]
        case .time: return Self.timeValues()
        }
    }

    /// 插入时的格式串；标题菜单则不需要。
    static let timeFormats = ["yyyy年M月d日", "yyyy年M月d日 HH:mm", "HH:mm"]

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

/// 上面两个面板的卡面：浮层底 + 描边 + level2 阴影，行按 36 高竖排。
struct DocumentToolbarPickerCard: View {
    let picker: DocumentToolbarPicker
    /// 标题菜单用来给当前级别打勾；时间菜单没有选中项。
    let selectedIndex: Int?
    let onPick: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(picker.titles.enumerated()), id: \.offset) { index, title in
                DocumentToolbarPickerRow(title: title,
                                         selected: selectedIndex == index) {
                    onPick(index)
                }
            }
        }
        .padding(.vertical, picker.verticalPadding)
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(WFColors.overlayBorder, lineWidth: 1)
        }
        .shadow(color: WFColors.overlayShadow, radius: 18, y: 6)
    }
}

/// 面板里的一行：14 regular，选中转强调色并在行尾打勾，悬停染中性灰
/// （原版 `_PickerRow` + `WorkFollowInteractionStyles.overlay(menu: true)`）。
struct DocumentToolbarPickerRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
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
