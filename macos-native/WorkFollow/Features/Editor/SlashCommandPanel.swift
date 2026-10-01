import AppKit
import SwiftUI

/// 斜杠面板现有度量，最初来自 Flutter `DocumentSlashMenuMetrics`。
///
/// 原版是一张 160 宽的命令卡：行高 34、上下各 4 内边距；行内是"左缩进 4 + 图标槽
/// 14 + 图标与文字间距 11 + 标签 + 右 12"；两段之间一条全宽 1pt 细线（上下各 4，
/// 共 9）；选中行是**中性灰**底 + 1pt 强调色细描边 + 6 圆角。12 项卡面高 425
/// （12×34 + 9 + 8）。保留此基线；TickTick 像素验收需独立截图证据。
enum SlashMenuMetrics {
    static let width: CGFloat = 160
    static let rowHeight: CGFloat = 34
    static let padding: CGFloat = 4
    static let itemInset: CGFloat = 4
    static let itemLeading: CGFloat = 14
    static let glyphSlot: CGFloat = 14
    static let glyphGap: CGFloat = 11
    static let itemTrailing: CGFloat = 12
    /// 4 above the hairline, 1 for the hairline, 4 below.
    static let dividerBlock: CGFloat = 9
    static let radius: CGFloat = 12
    static let rowRadius: CGFloat = 6
    static let labelSize: CGFloat = 13

    /// 与原版 `DocumentSlashMenu.heightFor` 同一算法：行 × 34 + 分组细线 9 +
    /// 上下内边距 8。
    static func height(for commands: [DocumentCommand]) -> CGFloat {
        guard !commands.isEmpty else { return 0 }
        let hasDivider = commands.contains { $0.group != commands[0].group }
        return CGFloat(commands.count) * rowHeight
            + (hasDivider ? dividerBlock : 0)
            + padding * 2
    }
}

/// 原版 `PopoverPlacement` 的默认间距 6 与 `WorkFollowSpacing.popoverSafeArea` 12，
/// 以及"面板高度最多夹到 max(220, 窗口高 - 24)，超出滚动"。
private enum SlashLayout {
    static let gap = WFPlanningOverlayMetrics.gap
    static let safeArea = WFPlanningOverlayMetrics.safeArea
    static let minHeight: CGFloat = 220
}

extension NativeTextView {
    func dismissSlash() {
        slashSession = nil
        stopFollowingSlash()
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
        let isFirstPresentation = slashPanel == nil
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
        let list = SlashCommandList(
            commands: commands, selected: session.selectedIndex, compact: profile.compactSlash,
            onSelect: { [weak self] index in self?.executeSlash(at: index) },
            onHover: { [weak self] index in self?.hoverSlash(index) })
        // 只换 rootView，不重建 hosting view：指针每移到一行都会走这里（悬停即选中），
        // 重建整棵树会让高亮闪一下。
        if let hosting = panel.contentView as? NSHostingView<SlashCommandList> {
            hosting.rootView = list
        } else {
            panel.contentView = NSHostingView(rootView: list)
        }
        let caret = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        // 夹取范围取**窗口**（原版是窗口内的浮层，安全边距 12），不是屏幕可视区。
        let bounds = window.frame.insetBy(dx: SlashLayout.safeArea, dy: SlashLayout.safeArea)
        let width = min(profile.compactSlash ? SlashMenuMetrics.width : 300, bounds.width)
        let desiredHeight = profile.compactSlash
            ? SlashMenuMetrics.height(for: commands)
            : CGFloat(min(max(commands.count, 1), 8) * 44 + 34)
        let height = min(desiredHeight, max(SlashLayout.minHeight, bounds.height))
        let x = min(max(caret.minX, bounds.minX), bounds.maxX - width)
        // 原版是 `bottomStart`：光标**下方**优先（AppKit 的 y 是窗口底边），放不下才翻到上方。
        let y = caret.minY - height - SlashLayout.gap >= bounds.minY
            ? caret.minY - height - SlashLayout.gap
            : min(caret.maxY + SlashLayout.gap, bounds.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFront(nil)
        startFollowingSlash()
        if isFirstPresentation {
            let identity = documentIdentity
            // TextKit/clip-view caret reveal can finish after insertText returns.
            // Re-anchor once after layout; never revive a closed/rebound session.
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel, self.slashPanel === panel,
                      self.documentIdentity == identity, self.slashSession != nil else { return }
                self.window?.contentView?.layoutSubtreeIfNeeded()
                self.refreshSlash()
            }
        }
    }

    /// 面板要**跟着滚动与窗口变化走**：原版在滚动容器的 position 变化和窗口尺寸
    /// 变化时都会重新定位（`document_editor.dart:213` 的 `_ancestorScrollPosition`
    /// 监听与 `didChangeMetrics`），否则一滚动面板就与光标脱钩。
    ///
    /// 这里盯两处：包着正文的 `NSClipView`（SwiftUI 的 `ScrollView` 背后也是它）
    /// 和窗口的移动/缩放。
    private func startFollowingSlash() {
        guard slashObservers.isEmpty else { return }
        let recenter: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSlash() }
        }
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            slashObservers.append(NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main,
                using: recenter))
        }
        if let window {
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                slashObservers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main, using: recenter))
            }
        }
    }

    private func stopFollowingSlash() {
        for observer in slashObservers { NotificationCenter.default.removeObserver(observer) }
        slashObservers.removeAll()
    }

    func moveSlash(_ offset: Int) {
        guard var session = slashSession else { return }
        session.move(offset, count: session.results(in: profile.slashCommands).count)
        slashSession = session
        refreshSlash()
    }

    /// 指针移到某一行就把高亮移过去（原版 `MouseRegion.onEnter` → `_hover`）。
    /// 已在那一行就什么都不做——否则悬停会引起"重绘 → 再次 hover"的循环。
    func hoverSlash(_ index: Int) {
        guard var session = slashSession, session.selectedIndex != index else { return }
        session.select(index)
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
        // Remove only this session's trigger/query; Escape deliberately leaves it intact.
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
    let onHover: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        if compact && index > 0 && command.group != commands[index - 1].group {
                            divider
                        }
                        row(index: index, command: command)
                    }
                }
                .padding(.vertical, compact ? SlashMenuMetrics.padding : 0)
            }
            .onChange(of: selected) { _, value in proxy.scrollTo(value, anchor: nil) }
            .onAppear { proxy.scrollTo(selected, anchor: nil) }
        }
        .font(.system(size: compact ? SlashMenuMetrics.labelSize : 14))
        .foregroundStyle(WFColors.text)
        // 卡面是浮层：底色 `overlay` + 描边 + 圆角 12（原版 `WorkFollowRadii.popover`），
        // 阴影由面板自己画（`hasShadow`，原版是 level2 elevation）。
        .background(WFColors.overlay, in: RoundedRectangle(cornerRadius: SlashMenuMetrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: SlashMenuMetrics.radius)
                .stroke(WFColors.border, lineWidth: 1)
        }
    }

    /// 分组细线：全宽 1pt `menuDivider`，上下各 4（原版 `_divider`）。
    private var divider: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: (SlashMenuMetrics.dividerBlock - 1) / 2)
            Rectangle().fill(WFColors.menuDivider).frame(height: 1)
            Color.clear.frame(height: (SlashMenuMetrics.dividerBlock - 1) / 2)
        }
    }

    @ViewBuilder
    private func row(index: Int, command: DocumentCommand) -> some View {
        let active = index == selected
        Button { onSelect(index) } label: {
            HStack(spacing: 0) {
                Color.clear.frame(width: compact ? SlashMenuMetrics.itemLeading : WFSpace.md)
                glyph(command)
                Color.clear.frame(width: compact ? SlashMenuMetrics.glyphGap : WFSpace.sm)
                Text(command.title).lineLimit(1)
                Spacer(minLength: 0)
                if !compact {
                    Text(command.group).font(.system(size: 11)).foregroundStyle(WFColors.secondaryText)
                }
                Color.clear.frame(width: compact ? SlashMenuMetrics.itemTrailing : WFSpace.md)
            }
            .frame(height: compact ? SlashMenuMetrics.rowHeight : 44)
            .contentShape(Rectangle())
            // 选中底是中性灰，不是强调色：菜单是中性表面，行不该在指针移过时"跳"一下。
            .background(active ? WFColors.menuSelected : Color.clear,
                        in: RoundedRectangle(cornerRadius: SlashMenuMetrics.rowRadius))
            // 选中行除灰底之外还有一圈 1pt 强调色细描边（原版 `focusBorder`：
            // `focusRing` = 强调色 35%）。
            .overlay {
                RoundedRectangle(cornerRadius: SlashMenuMetrics.rowRadius)
                    .stroke(active ? WFColors.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, compact ? SlashMenuMetrics.itemInset : 0)
        // 指针移到哪一行，高亮就到哪一行。
        .onHover { inside in if inside { onHover(index) } }
        .id(index)
    }

    @ViewBuilder
    private func glyph(_ command: DocumentCommand) -> some View {
        // 图形按原版手绘（见 `SlashMenuGlyph`）：面板这一栏是原版自己画的图标集，
        // SF Symbols 只有语义相近、笔画不同的替代品。
        SlashMenuGlyph(kind: command.resolvedGlyph)
    }
}
