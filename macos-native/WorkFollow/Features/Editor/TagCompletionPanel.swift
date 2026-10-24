import AppKit
import SwiftUI

/// 输入期候选补全（TI2-08）：`#` 标签、`~` 清单。
///
/// 滴答证据：`TTTaskDetailMarkdownCell.shouldShowQuickTag` / `shouldShowQuickList`
/// 两个开关并列；各候选浮层的 `prefixSymbal` getter 反汇编出立即数——
/// `TTTagCandidatePopover` = `0x23`(`#`)、`TTListCandidatePopover` = `0x7e`(`~`)、
/// `TTMentionCandidatePopover` = `0x40`(`@`)、`TTDateCandidatePopover` = `0x2a`(`*`)、
/// `TTPriorityCandidatePopover` = `0x21`(`!`)。本地只落 `#` 与 `~` 两种：
/// 另外三种的候选源/插入语义没有证据，不做。
///
/// 两种前缀共用同一条会话（同一时刻只会有一个面板），用 `kind` 区分替换文本与回写。
struct TagCompletionSession: Equatable {
    enum Kind: Equatable {
        /// `#tag`：插成 `#tag ` 并把标签挂到任务上。
        case tag
        /// `~清单`：插成 `~清单 ` 并把任务移进该清单。
        case list
    }
    var kind: Kind = .tag
    /// 前缀字符在全文里的位置。
    let start: Int
    /// `#query` / `~query` 的替换区间。
    var range: NSRange
    var query: String
    var candidates: [String]
    var selectedIndex = 0
}

extension NativeTextView {

    /// 依据光标前的 `#query` / `~query` 刷新候选面板；任何前提不满足就收起。
    func refreshTagCompletion() {
        guard isEditable, !hasMarkedText(), window != nil, selectedRange().length == 0 else {
            dismissTagCompletion(); return
        }
        // 两种前缀并排探测：同一位置只会命中一个（字符不同），命中顺序即优先级。
        if refreshCompletion(kind: .tag, prefix: "#", candidates: profile.tagCandidates()) { return }
        if refreshCompletion(kind: .list, prefix: "~", candidates: profile.listCandidates()) { return }
        dismissTagCompletion()
    }

    /// 单个前缀的探测与面板刷新。命中返回 true。
    private func refreshCompletion(kind: TagCompletionSession.Kind, prefix: Character,
                                   candidates all: [String]) -> Bool {
        guard !all.isEmpty else { return false }
        let source = string as NSString
        guard source.length > 0 else { return false }
        let caret = min(max(selectedRange().location, 0), source.length)
        guard caret > 0 else { return false }
        let anchor = min(caret, source.length - 1)
        let paragraph = source.paragraphRange(for: NSRange(location: anchor, length: 0))
        // 代码块 / 分割线里不触发（前缀字符在那里是字面字符）。
        if let token = textStorage?.attribute(DocumentTextCodec.blockKey, at: paragraph.location,
                                              effectiveRange: nil) as? String,
           token == "code" || token == "divider" {
            return false
        }
        let prefixLength = caret - paragraph.location
        guard prefixLength > 0 else { return false }
        let paragraphPrefix = source.substring(with: NSRange(location: paragraph.location, length: prefixLength))
        let escaped = NSRegularExpression.escapedPattern(for: String(prefix))
        guard let regex = try? NSRegularExpression(pattern: escaped + "([^\\s" + escaped + "]*)$"),
              let match = regex.firstMatch(in: paragraphPrefix,
                                          range: NSRange(location: 0, length: (paragraphPrefix as NSString).length))
        else { return false }
        // 前缀字符必须在行首或空白之后（`a#b` / `a~b` 不算触发）。
        if match.range.location > 0 {
            let before = source.character(at: paragraph.location + match.range.location - 1)
            guard before == 0x20 || before == 0x09 else { return false }
        }
        let query = (paragraphPrefix as NSString).substring(with: match.range(at: 1))
        let filtered = all.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        guard !filtered.isEmpty else { return false }
        let candidates = Array(filtered.prefix(6))
        let selected = min(tagSession?.selectedIndex ?? 0, candidates.count - 1)
        let start = paragraph.location + match.range.location
        tagSession = TagCompletionSession(kind: kind, start: start,
                                          range: NSRange(location: start,
                                                         length: (query as NSString).length + 1),
                                          query: query, candidates: candidates,
                                          selectedIndex: selected)
        presentTagPanel()
        return true
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
        let candidate = session.candidates[selected]
        let range = session.range
        let kind = session.kind
        dismissTagCompletion()
        breakUndoCoalescing()
        switch kind {
        case .tag:
            insertText("#\(candidate) ", replacementRange: range)
            profile.onTagInserted(candidate)
        case .list:
            // 清单不是正文标记：插成 `~清单 ` 只为了让用户看到"已经填进去了"，
            // 真正的效果是把任务移进该清单（滴答的候选选中即回写清单）。
            insertText("~\(candidate) ", replacementRange: range)
            profile.onListInserted(candidate)
        }
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
                                    symbol: session.kind == .tag ? "number" : "list.bullet",
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

/// 候选列表：与 Slash 菜单同一套行高/圆角，图标按前缀区分（`#` 用 number，`~` 用 list）。
private struct TagCandidateList: View {
    let tags: [String]
    let selected: Int
    let symbol: String
    let onSelect: (Int) -> Void
    let onHover: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                Button { onSelect(index) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
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
        .frame(width: PopupMetrics.completionWidth)
        .background(WFColors.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WFColors.overlayBorder))
    }
}
