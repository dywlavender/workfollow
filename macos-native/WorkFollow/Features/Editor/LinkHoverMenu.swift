import AppKit
import SwiftUI

/// 链接悬停菜单（TI2-08 的下半项）。
///
/// 滴答证据：`TTTaskDetailMarkdownCell.hideLinkHoverMenu`、
/// `TTMarkdownLinkViewController`、资源 `md_link_copy` / `md_link_edit`。
/// 鼠标停到链接上给出「复制 / 编辑 / 移除」三个动作；面板是独立子窗口，
/// 不抢焦点，移开/点击/编辑文本都会收起。
extension NativeTextView {

    /// 鼠标点所在的链接范围（命中字符本身或左邻字符，覆盖字形右半边的边界情况）。
    func linkRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let index = characterIndexForInsertion(at: point)
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange()
            if storage.attribute(.link, at: candidate, effectiveRange: &range) != nil,
               range.length > 0 {
                return range
            }
        }
        return nil
    }

    func linkTarget(in range: NSRange) -> String? {
        guard let storage = textStorage, range.location >= 0, range.location < storage.length else { return nil }
        guard let value = storage.attribute(.link, at: range.location, effectiveRange: nil) else { return nil }
        return value as? String ?? String(describing: value)
    }

    @discardableResult
    func copyLink(in range: NSRange) -> Bool {
        guard let target = linkTarget(in: range) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target, forType: .string)
        return true
    }

    func editLink(in range: NSRange) {
        guard isEditable else { return }
        window?.makeFirstResponder(self)
        setSelectedRange(range)
        editDocumentLink(nil)
    }

    func removeLink(in range: NSRange) {
        guard isEditable else { return }
        window?.makeFirstResponder(self)
        setSelectedRange(range)
        removeDocumentLink(nil)
    }

    // MARK: 面板

    func showLinkHoverMenu(for range: NSRange) {
        guard let window, isEditable, range.length > 0,
              let line = viewRect(forCharacterAt: range.location) else { return }
        let panel: NSPanel
        if let existing = linkHoverPanel { panel = existing }
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
            linkHoverPanel = panel
        }
        let content = LinkHoverMenuView(
            onCopy: { [weak self] in self?.copyLink(in: range); self?.hideLinkHoverMenu() },
            onEdit: { [weak self] in self?.hideLinkHoverMenu(); self?.editLink(in: range) },
            onRemove: { [weak self] in self?.hideLinkHoverMenu(); self?.removeLink(in: range) })
        if let hosting = panel.contentView as? NSHostingView<LinkHoverMenuView> {
            hosting.rootView = content
        } else {
            panel.contentView = NSHostingView(rootView: content)
        }
        let size = NSSize(width: 178, height: 30)
        let screenLine = window.convertToScreen(convert(line, to: nil))
        let bounds = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(screenLine.minX, bounds.minX + 8), bounds.maxX - size.width - 8)
        let below = screenLine.minY - size.height - 4
        let y = below >= bounds.minY + 8 ? below : min(screenLine.maxY + 4, bounds.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        panel.orderFront(nil)
    }

    func hideLinkHoverMenu() {
        hoveredLinkRange = nil
        if let linkHoverPanel {
            linkHoverPanel.parent?.removeChildWindow(linkHoverPanel)
            linkHoverPanel.orderOut(nil)
        }
        linkHoverPanel = nil
    }
}

private struct LinkHoverMenuView: View {
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("复制", symbol: "doc.on.doc", action: onCopy)
            button("编辑", symbol: "pencil", action: onEdit)
            button("移除", symbol: "link.badge.minus", action: onRemove)
        }
        .padding(3)
        .background(WFColors.overlay)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WFColors.overlayBorder))
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(WFColors.text)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
