import SwiftUI

enum NoteDirectoryIcon: String, CaseIterable {
    case folder, document = "doc.text", briefcase, people = "person.2", calendar, checklist
    case book, bookmark, lightbulb, chart = "chart.bar", scope, pin
    case house, cart, airplane, paintbrush, sparkles, star

    var title: String {
        switch self {
        case .folder: "文件夹"
        case .document: "文档"
        case .briefcase: "工作"
        case .people: "会议"
        case .calendar: "日程"
        case .checklist: "清单"
        case .book: "阅读"
        case .bookmark: "资料"
        case .lightbulb: "灵感"
        case .chart: "数据"
        case .scope: "目标"
        case .pin: "图钉"
        case .house: "生活"
        case .cart: "购物"
        case .airplane: "旅行"
        case .paintbrush: "设计"
        case .sparkles: "创意"
        case .star: "重点"
        }
    }

    private static let legacyIcons: [String: Self] = [
        "📁": .folder, "💼": .briefcase, "🏠": .house, "📚": .book, "🎯": .scope,
        "🚀": .sparkles, "🛒": .cart, "💡": .lightbulb, "🍀": .sparkles, "✈️": .airplane,
        "🧪": .lightbulb, "🎨": .paintbrush, "📝": .document, "📄": .document,
        "📌": .pin, "🗓️": .calendar, "⭐": .star, "📊": .chart,
    ]

    static func resolve(_ value: String?) -> Self? {
        guard let value else { return nil }
        return Self(rawValue: value) ?? legacyIcons[value]
    }

    /// 目录树渲染用的 Phosphor 双色调资产（Assets.xcassets，模板渲染，
    /// 自动跟随深浅色与调用方的 foregroundStyle）。rawValue 是持久化键，不能动。
    var duotoneAssetName: String { "wf.dir.\(String(describing: self))" }

    /// 没有显式图标时的兜底：真文件夹与「未归档」托盘也走双色调
    /// （默认文件夹正是「太丑」的重灾区）；笔记的 doc.text 不在表里，
    /// 保持 SF Symbols——树里每行笔记都上双色调会太吵。
    static func defaultDuotoneAsset(symbol: String) -> String? {
        switch symbol {
        case "folder": return NoteDirectoryIcon.folder.duotoneAssetName
        case "tray": return "wf.dir.tray"
        default: return nil
        }
    }
}

/// Phosphor 双色调目录图标，三处共用：目录树行、图标选择网格、拖拽预览。
/// 有 `icon`（用户明确选择的枚举）或命中 `defaultDuotoneAsset(symbol:)`
/// 兜底时渲染资产；否则回退 SF Symbols。颜色由调用方 foregroundStyle 决定。
struct NoteDirectoryGlyph: View {
    let icon: NoteDirectoryIcon?
    let symbol: String
    var size: CGFloat = 16

    var body: some View {
        if let asset = icon?.duotoneAssetName
            ?? NoteDirectoryIcon.defaultDuotoneAsset(symbol: symbol) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size * 0.8, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

struct NoteDirectoryIconMenu: View {
    let icon: String?
    let select: (String?) -> Void

    var body: some View {
        BusinessMenu("更换图标", systemImage: "square.grid.2x2", width: 252) {
            NoteDirectoryIconGrid(selected: NoteDirectoryIcon.resolve(icon), select: select)
            Divider()
            Button("恢复默认") { select(nil) }.disabled(icon == nil)
        }
    }
}

struct NoteDirectoryIconGrid: View {
    let selected: NoteDirectoryIcon?
    let select: (String?) -> Void
    @Environment(\.dismissBusinessMenus) private var dismiss

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 6), spacing: 4) {
            ForEach(NoteDirectoryIcon.allCases, id: \.rawValue) { icon in
                NoteDirectoryIconButton(icon: icon, selected: selected == icon) {
                    dismiss()
                    select(icon.rawValue)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct NoteDirectoryIconButton: View {
    let icon: NoteDirectoryIcon
    let selected: Bool
    let select: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: select) {
            NoteDirectoryGlyph(icon: icon, symbol: icon.rawValue, size: 17)
                .foregroundStyle(selected ? WFColors.accent : WFColors.secondaryText)
                .frame(width: 34, height: 34)
                .background(selected ? WFColors.selection : hovered ? WFColors.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(WFColors.accent.opacity(0.32))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(icon.title)
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("note.icon.\(icon.rawValue)")
    }
}

/// 文件夹右键「编辑」弹窗：一处改图标与名称字体颜色。颜色与编辑器文字颜色
/// 共用同一张色板（`DocumentColorPalette`）；两者都为 nil 时跟随默认外观。
/// 草稿在弹窗内编辑，点「保存」才写回模型，「取消」丢弃。
struct NoteFolderEditSheet: View {
    let folderName: String
    let onSave: (_ icon: String?, _ colorHex: String?) -> Void
    let onCancel: () -> Void

    @State private var icon: String?
    @State private var colorHex: String?

    init(folderName: String, initialIcon: String?, initialColorHex: String?,
         onSave: @escaping (String?, String?) -> Void, onCancel: @escaping () -> Void) {
        self.folderName = folderName
        self.onSave = onSave
        self.onCancel = onCancel
        _icon = State(initialValue: initialIcon)
        _colorHex = State(initialValue: initialColorHex)
    }

    private var nameColor: Color? {
        colorHex.flatMap { NSColor(documentHex: $0) }.map { Color(nsColor: $0) }
    }

    private let colorColumns = Array(repeating: GridItem(.fixed(20), spacing: 4), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑文件夹").font(WFType.detailTitle).foregroundStyle(WFColors.text)

            // 实时预览：图标 + 上色后的名称，所见即所得。
            HStack(spacing: 5) {
                NoteDirectoryGlyph(icon: NoteDirectoryIcon.resolve(icon), symbol: "folder", size: 16)
                    .foregroundStyle(WFColors.secondaryText)
                Text(folderName).font(WFType.navigation).lineLimit(1)
                    .foregroundStyle(nameColor ?? WFColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 30)
            .background(WFColors.quickAddIdleFill, in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("图标", resetTitle: "默认图标", isDefault: icon == nil) { icon = nil }
                NoteDirectoryIconGrid(selected: NoteDirectoryIcon.resolve(icon)) { icon = $0 }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("名称颜色", resetTitle: "默认颜色", isDefault: colorHex == nil) { colorHex = nil }
                LazyVGrid(columns: colorColumns, spacing: 4) {
                    ForEach(DocumentColorPalette.swatches) { swatch in
                        Button { colorHex = swatch.hex } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: NSColor(documentHex: swatch.hex) ?? .clear))
                                .frame(width: 20, height: 20)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(WFColors.border.opacity(swatch.hex == "#ffffff" ? 1 : 0.25),
                                                lineWidth: 0.5)
                                }
                                .overlay {
                                    if colorHex == swatch.hex {
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(WFColors.accent, lineWidth: 1.5)
                                            .padding(-3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .hoverTip(swatch.hex)
                        .accessibilityLabel(swatch.hex)
                    }
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
                Button("保存") { onSave(icon, colorHex) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 280)
        .background(WFColors.content)
        .accessibilityIdentifier("note.folderEditSheet")
    }

    private func sectionHeader(_ title: String, resetTitle: String, isDefault: Bool,
                               reset: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(WFType.supporting).foregroundStyle(WFColors.secondaryText)
            Spacer()
            Button(resetTitle, action: reset)
                .buttonStyle(.plain).font(WFType.caption)
                .foregroundStyle(isDefault ? WFColors.tertiaryText : WFColors.accent)
                .disabled(isDefault)
        }
    }
}
