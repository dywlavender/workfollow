import AppKit
import SwiftUI

/// `#` 标签补全会话（TI2-08）。
///
/// 滴答证据：`TTTaskDetailMarkdownCell.shouldShowQuickTag`、
/// `existedTagNamesForTagCandidate`、`markdownText:didSelectTag:`。
/// 本地只做"输入 `#` 后列出宿主已有标签，回车/点击落成 `#tag ` 并挂到任务上"。
struct TagCompletionSession: Equatable {
    /// `#` 在全文里的位置。
    let start: Int
    /// `#query` 的替换区间。
    var range: NSRange
    var query: String
    var candidates: [String]
    var selectedIndex = 0
}

extension NativeTextView {

    /// 依据光标前的 `#query` 刷新候选面板；任何前提不满足就收起。
    func refreshTagCompletion() {
        guard isEditable, !hasMarkedText(), window != nil, selectedRange().length == 0 else {
            dismissTagCompletion(); return
        }
        let allTags = profile.tagCandidates()
        guard !allTags.isEmpty else { dismissTagCompletion(); return }
        let source = string as NSString
        guard source.length > 0 else { dismissTagCompletion(); return }
        let caret = min(max(selectedRange().location, 0), source.length)
        guard caret > 0 else { dismissTagCompletion(); return }
        let anchor = min(caret, source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: anchor, length: 0))
        // 代码块 / 分割线里不触发（`#` 在那里是字面字符）。
        if let token = textStorage?.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                              effectiveRange: nil) as? String,
           token == "code" || token == "divider" {
            dismissTagCompletion(); return
        }
        let prefixLength = caret - paragraph.location
        guard prefixLength > 0 else { dismissTagCompletion(); return }
        let prefix = source.substring(with: NSRange(location: paragraph.location, length: prefixLength))
        guard let regex = try? NSRegularExpression(pattern: "#([^\\s#]*)$"),
              let match = regex.firstMatch(in: prefix,
                                          range: NSRange(location: 0, length: (prefix as NSString).length))
        else { dismissTagCompletion(); return }
        // `#` 必须在行首或空白之后（`a#b` 不算标签）。
        if match.range.location > 0 {
            let before = source.character(at: paragraph.location + match.range.location - 1)
            guard before == 0x20 || before == 0x09 else { dismissTagCompletion(); return }
        }
        let query = (prefix as NSString).substring(with: match.range(at: 1))
        let filtered = allTags.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        guard !filtered.isEmpty else { dismissTagCompletion(); return }
        let candidates = Array(filtered.prefix(6))
        let selected = min(tagSession?.selectedIndex ?? 0, candidates.count - 1)
        let start = paragraph.location + match.range.location
        tagSession = TagCompletionSession(start: start,
                                          range: NSRange(location: start,
                                                         length: (query as NSString).length + 1),
                                          query: query, candidates: candidates,
                                          selectedIndex: selected)
        presentTagPanel()
    }

    func dismissTagCompletion() {
        tagSession = nil
        if let tagPanel {
            tagPanel.parent?.removeChildWindow(tagPanel)
            tagPanel.orderOut(nil)
        }
        tagPanel = nil
    }

    func moveTagCompletion(_ offset: Int) {
        guard var session = tagSession, !session.candidates.isEmpty else { return }
        let count = session.candidates.count
        session.selectedIndex = (session.selectedIndex + offset + count) % count
        tagSession = session
        presentTagPanel()
    }

    func hoverTagCompletion(_ index: Int) {
        guard var session = tagSession, index != session.selectedIndex,
              session.candidates.indices.contains(index) else { return }
        session.selectedIndex = index
        tagSession = session
        presentTagPanel()
    }

    func commitTagCompletion(at index: Int? = nil) {
        guard let session = tagSession else { return }
        let selected = index ?? session.selectedIndex
        guard session.candidates.indices.contains(selected) else { dismissTagCompletion(); return }
        let tag = session.candidates[selected]
        let range = session.range
        dismissTagCompletion()
        breakUndoCoalescing()
        insertText("#\(tag) ", replacementRange: range)
        profile.onTagInserted(tag)
    }

    // MARK: 面板

    private func presentTagPanel() {
        guard let session = tagSession, let window else { return }
        let panel: NSPanel
        if let existing = tagPanel { panel = existing }
        else {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.appearance = window.effectiveAppearance
            window.addChildWindow(panel, ordered: .above)
            tagPanel = panel
        }
        let list = TagCandidateList(tags: session.candidates, selected: session.selectedIndex,
                                    onSelect: { [weak self] index in self?.commitTagCompletion(at: index) },
                                    onHover: { [weak self] index in self?.hoverTagCompletion(index) })
        if let hosting = panel.contentView as? NSHostingView<TagCandidateList> {
            hosting.rootView = list
        } else {
            panel.contentView = NSHostingView(rootView: list)
        }
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let bounds = window.frame.insetBy(dx: 12, dy: 12)
        let size = NSSize(width: 160, height: CGFloat(session.candidates.count) * 28 + 8)
        let x = min(max(caret.minX, bounds.minX), bounds.maxX - size.width)
        let y = caret.minY - size.height - 6 >= bounds.minY
            ? caret.minY - size.height - 6
            : min(caret.maxY + 6, bounds.maxY - size.height)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.orderFront(nil)
    }
}

/// 候选列表：与 Slash 菜单同一套行高/圆角，图标用 `number`（`#`）。
private struct TagCandidateList: View {
    let tags: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                Button { onSelect(index) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.system(size: 11))
                            .foregroundStyle(WFColors.secondaryText)
                            .frame(width: 14)
                        Text(tag)
                            .font(.system(size: 13))
                            .foregroundStyle(WFColors.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(index == selected ? WFColors.hover : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { onHover(index) } }
            }
        }
        .padding(4)
        .frame(width: 160)
        .background(WFColors.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WFColors.overlayBorder))
    }
}
