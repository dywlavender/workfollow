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
        guard session.update(text: string, selection: selectedRange()) else { dismissSlash(); return }
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
            window.addChildWindow(panel, ordered: .above)
            slashPanel = panel
        }
        panel.contentView = NSHostingView(rootView: SlashCommandList(
            commands: commands, selected: session.selectedIndex,
            onSelect: { [weak self] index in self?.executeSlash(at: index) }))
        let height = CGFloat(min(max(commands.count, 1), 8) * 44 + 34)
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let bounds = window.screen?.visibleFrame ?? window.frame
        let width: CGFloat = min(300, bounds.width)
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
        dismissSlash()
        breakUndoCoalescing()
        // Remove only this session's /query; Escape deliberately leaves it intact.
        undoManager?.beginUndoGrouping()
        insertText("", replacementRange: session.range)
        command.perform(self)
        undoManager?.endUndoGrouping()
        breakUndoCoalescing()
    }
}

private struct SlashCommandList: View {
    let commands: [DocumentCommand]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("输入搜索 · ↑↓ 选择 · Enter 确认 · Esc 关闭")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(9)
            if commands.isEmpty {
                Text("没有匹配的命令").font(.callout).foregroundStyle(.secondary).padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                                Button { onSelect(index) } label: {
                                    HStack {
                                        Text(command.title)
                                        Spacer()
                                        Text(command.group).font(.caption).foregroundStyle(.secondary)
                                    }.padding(.horizontal, 12).frame(height: 44)
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
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
