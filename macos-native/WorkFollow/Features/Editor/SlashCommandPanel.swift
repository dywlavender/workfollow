import AppKit
import SwiftUI

extension NativeTextView {
    func dismissSlash() {
        slashSession = nil
        if let panel = slashPanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        slashPanel = nil
    }

    func refreshSlash() {
        guard var session = slashSession else { return }
        // Do not replace candidates or consume keys while an input method owns them.
        guard !hasMarkedText() else { slashPanel?.orderOut(nil); return }
        guard session.update(text: string, selection: selectedRange(), allowsQuery: !profile.compactSlash) else { dismissSlash(); return }
        slashSession = session
        guard let window else { return }
        let commands = session.results(in: profile.slashCommands)
        let panel: NSPanel
        if let existing = slashPanel { panel = existing }
        else {
            panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hasShadow = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.appearance = window.effectiveAppearance
            window.addChildWindow(panel, ordered: .above)
            slashPanel = panel
        }
        panel.contentView = NSHostingView(rootView: SlashCommandList(
            commands: commands, selected: session.selectedIndex, compact: profile.compactSlash,
            onSelect: { [weak self] index in self?.executeSlash(at: index) }))
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let bounds = (window.screen?.visibleFrame ?? window.frame).intersection(window.frame).insetBy(dx: 8, dy: 8)
        let desiredHeight = profile.compactSlash ? CGFloat(commands.count * 32 + 17) : CGFloat(min(max(commands.count, 1), 8) * 44 + 34)
        let height = min(desiredHeight, max(32, max(caret.minY - bounds.minY - 4, bounds.maxY - caret.maxY - 4)))
        let width: CGFloat = min(profile.compactSlash ? 160 : 300, bounds.width)
        let x = min(max(caret.minX, bounds.minX), bounds.maxX - width)
        let y = caret.minY - height - 4 >= bounds.minY ? caret.minY - height - 4 : min(caret.maxY + 4, bounds.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFront(nil)
    }

    func moveSlash(_ offset: Int) {
        guard var session = slashSession else { return }
        session.move(offset, count: session.results(in: profile.slashCommands).count)
        slashSession = session
        refreshSlash()
    }

    func executeSlash(at index: Int? = nil) {
        guard let session = slashSession, !hasMarkedText() else { return }
        let commands = session.results(in: profile.slashCommands)
        let index = index ?? session.selectedIndex
        guard commands.indices.contains(index) else { return }
        let command = commands[index]
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: session.start, length: 0))
        let invocation = SlashCommandInvocation(lineStart: paragraph.location, slashOffset: session.start)
        dismissSlash()
        breakUndoCoalescing()
        // Remove only this session's /query; Escape deliberately leaves it intact.
        undoManager?.beginUndoGrouping()
        insertText("", replacementRange: session.range)
        if let performSlash = command.performSlash {
            performSlash(self, invocation)
        } else {
            command.perform(self)
        }
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }
}

private struct SlashCommandList: View {
    let commands: [DocumentCommand]
    let selected: Int
    let compact: Bool
    let onSelect: (Int) -> Void

    private func symbol(_ command: DocumentCommand) -> String {
        switch command.id {
        case "task.format.0", "task.format.1", "task.format.2": "textformat.size"
        case "task.format.3": "list.bullet"
        case "task.format.4": "list.number"
        case "task.format.5": "checklist"
        case "task.format.6": "text.quote"
        case "shared.divider": "minus"
        case "shared.attachment": "paperclip"
        case "task.child": "list.bullet.indent"
        case "task.tags": "tag"
        case "task.relation": "link"
        default: "text.alignleft"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !compact { Text("输入搜索 · ↑↓ 选择 · Enter 确认 · Esc 关闭")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(9)
            }
            if commands.isEmpty {
                Text("没有匹配的命令").font(.callout).foregroundStyle(.secondary).padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                if compact && index > 0 && command.group != commands[index - 1].group {
                                    Divider().padding(.vertical, 4)
                                }
                                Button { onSelect(index) } label: {
                                    HStack(spacing: 8) {
                                        if compact { Image(systemName: symbol(command)).frame(width: 18) }
                                        Text(command.title)
                                        Spacer()
                                        if !compact { Text(command.group).font(.caption).foregroundStyle(.secondary) }
                                    }.padding(.horizontal, compact ? 8 : 12).frame(height: compact ? 32 : 44)
                                        .contentShape(Rectangle())
                                        .background(index == selected ? Color.accentColor.opacity(0.16) : .clear)
                                }.buttonStyle(.plain).id(index)
                            }
                        }
                    }
                    .onChange(of: selected) { _, value in proxy.scrollTo(value) }
                    .onAppear { proxy.scrollTo(selected) }
                }
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(WFColors.text)
        .background(WFColors.content, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WFColors.border, lineWidth: 1))
    }
}
