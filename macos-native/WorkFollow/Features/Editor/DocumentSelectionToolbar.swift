import AppKit
import SwiftUI

/// Round B2 迁移说明：Flutter 侧的 document_selection_toolbar（选区工具条）与
/// document_editor_toolbar（浮动格式工具条）在此合并落地——本次迁移只允许新增一个
/// Editor 文件，且两者共用同一命令通道（DocumentFormatCommand / DocumentEditorHandle /
/// DocumentProfile.selectionActions），不绕过现有命令层。

/// 选中文本时浮现在选区上方的小工具条（迁移自 Flutter DocumentSelectionToolbar）。
/// 笔记 profile 提供“创建任务”，这里追加常用内联样式；Escape 或收起选区即关闭
/// （面板生命周期由 NativeTextView 管理）。
struct DocumentSelectionToolbarView: View {
    let actions: [DocumentSelectionAction]
    let onInvoke: (DocumentSelectionAction) -> Void
    let onFormat: (DocumentFormatCommand) -> Void
    let onLink: () -> Void

    /// 常用内联样式：粗体/斜体/下划线/删除线/高亮/行内代码。
    private var inlineCommands: [DocumentFormatCommand] {
        [DocumentMark.bold, .italic, .underline, .strikethrough, .highlight, .code].compactMap { mark in
            DocumentFormatCommand.commands.first { $0.mark == mark }
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button {
                    onInvoke(action)
                } label: {
                    Label(selectionTitle(action), systemImage: "text.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 6)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.accent)
                .help(action.title).accessibilityLabel(action.title)
            }
            Divider().frame(height: 16)
            ForEach(inlineCommands, id: \.title) { command in
                Button { onFormat(command) } label: {
                    Image(systemName: symbol(for: command))
                        .frame(width: 24, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(WFColors.text)
                .help(command.title).accessibilityLabel(command.title)
            }
            Divider().frame(height: 16)
            Button { onLink() } label: {
                Image(systemName: "link").frame(width: 24, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(WFColors.text)
            .help("链接").accessibilityLabel("链接")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    /// 右键菜单沿用 profile 的完整标题；浮动条上用短文案（对齐 Flutter “创建任务”）。
    private func selectionTitle(_ action: DocumentSelectionAction) -> String {
        action.id == "note.createTask" ? "创建任务" : action.title
    }

    private func symbol(for command: DocumentFormatCommand) -> String {
        switch command.mark {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .highlight: "highlighter"
        case .code: "chevron.left.forwardslash.chevron.right"
        default: "textformat"
        }
    }
}

/// 笔记页脚的浮动格式工具条（迁移自 Flutter DocumentEditorToolbar 的全集）。
/// 与任务检查器的格式条走同一 Handle/命令通道：标题 H、粗体、高亮、检查项、
/// 无序/有序列表、斜体、下划线、删除线、分割线、插入当前时间（日期/日期时间/时刻）、
/// 链接、行内代码、引用、上传附件。
struct DocumentFormatToolbarView: View {
    let handle: DocumentEditorHandle

    private static let headingCommands = [DocumentBlockKind.paragraph, .heading(1), .heading(2), .heading(3)]
        .compactMap { kind in DocumentFormatCommand.commands.first { $0.block == kind } }

    private static func block(_ kind: DocumentBlockKind) -> DocumentFormatCommand? {
        DocumentFormatCommand.commands.first { $0.block == kind }
    }

    private static func mark(_ mark: DocumentMark) -> DocumentFormatCommand? {
        DocumentFormatCommand.commands.first { $0.mark == mark }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                Menu {
                    ForEach(Self.headingCommands, id: \.title) { command in
                        Button(command.title) { handle.format(command) }
                    }
                } label: {
                    Image(systemName: "textformat.size").frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("标题").accessibilityLabel("标题格式")
                formatButton("粗体", "bold", Self.mark(.bold))
                formatButton("高亮", "highlighter", Self.mark(.highlight))
                formatButton("检查项", "checklist", Self.block(.checklist(false)))
                formatButton("无序列表", "list.bullet", Self.block(.bullet))
                formatButton("有序列表", "list.number", Self.block(.ordered))
                Divider().frame(height: 18)
                formatButton("斜体", "italic", Self.mark(.italic))
                formatButton("下划线", "underline", Self.mark(.underline))
                formatButton("删除线", "strikethrough", Self.mark(.strikethrough))
                Button { handle.insertDivider() } label: {
                    Image(systemName: "minus").frame(width: 26, height: 30)
                }.help("分割线").accessibilityLabel("分割线")
                Menu {
                    Button("日期") { handle.insertTime(format: "yyyy年M月d日") }
                    Button("日期时间") { handle.insertTime(format: "yyyy年M月d日 HH:mm") }
                    Button("时刻") { handle.insertTime(format: "HH:mm") }
                } label: {
                    Image(systemName: "clock").frame(width: 26, height: 30)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("插入当前时间").accessibilityLabel("插入当前时间")
                Button { handle.editLink() } label: {
                    Image(systemName: "link").frame(width: 30, height: 30)
                }.help("链接").accessibilityLabel("链接")
                formatButton("行内代码", "chevron.left.forwardslash.chevron.right", Self.mark(.code))
                formatButton("引用", "text.quote", Self.block(.quote))
                Button { handle.insertAttachment() } label: {
                    Image(systemName: "paperclip").frame(width: 30, height: 30)
                }.help("上传附件").accessibilityLabel("上传附件")
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(maxWidth: 470)
        .frame(height: 38)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.border))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func formatButton(_ title: String, _ symbol: String, _ command: DocumentFormatCommand?) -> some View {
        Button {
            if let command { handle.format(command) }
        } label: {
            Image(systemName: symbol).frame(width: 26, height: 30)
        }
        .disabled(command == nil)
        .help(title).accessibilityLabel(title)
    }
}
