import AppKit
import SwiftUI

/// Menus live outside the WebKit body bounds, including short growing bodies.
/// The Web editor keeps the query, selection and command execution.
@MainActor
final class MilkdownMenuPresenter {
    struct Item: Decodable {
        var id: String?
        var title: String
        var group: String?
    }
    struct State: Decodable {
        struct Anchor: Decodable { var x: CGFloat; var y: CGFloat; var width: CGFloat; var height: CGFloat }
        var session: Int
        var items: [Item]
        var selected: Int
        var anchor: Anchor
        var query: String?
    }
    private weak var editor: MilkdownWebView?
    private var state: State?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private(set) var panel: EditorCompletionPanel?

    init(editor: MilkdownWebView) {
        self.editor = editor
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let editor = self.editor, self.panel?.isVisible == true,
                  event.window !== self.panel else { return event }
            if !EditorHostScrollRouting.contains(event, in: editor) { self.cancel() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } }
    }

    func show(_ value: State) {
        guard let editor, let owner = editor.window, !value.items.isEmpty else { dismiss(); return }
        state = value
        let panel: EditorCompletionPanel
        if let existing = self.panel { panel = existing }
        else {
            panel = EditorCompletionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            panel.title = "正文命令菜单"; panel.isReleasedWhenClosed = false
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
            panel.becomesKeyOnlyIfNeeded = true
            self.panel = panel
        }
        if panel.parent !== owner { panel.parent?.removeChildWindow(panel); owner.addChildWindow(panel, ordered: .above) }
        panel.appearance = owner.effectiveAppearance
        EditorPopupWindowLevel.apply(to: panel, owner: owner)
        let commands = descriptors(value)
        let content = AnyView(SlashCommandList(commands: commands, selected: value.selected, compact: true,
            onSelect: { [weak self] index in self?.send("popupChoose", index: index) },
            onHover: { [weak self] index in self?.send("popupHover", index: index) }).workfollowNativeTheme())
        if let host = panel.contentView as? NSHostingView<AnyView> { host.rootView = content }
        else { panel.contentView = NSHostingView(rootView: content) }
        panel.followGeometry(of: editor) { [weak self] in self?.reposition() }
        reposition(); panel.orderFront(nil)
    }

    private func descriptors(_ value: State) -> [DocumentCommand] {
        let known = (editor?.active?.profile.slashCommands ?? []) + (editor?.active?.profile.blockMenuCommands ?? [])
        return value.items.enumerated().map { index, item in
            var command = DocumentCommand(id: item.id ?? "row.\(index)", title: item.title, group: item.group ?? "", perform: { _ in })
            command.glyph = known.first { $0.id == item.id }?.resolvedGlyph
            if item.id == nil { command.glyph = .symbol(value.query?.hasPrefix("#") == true ? "tag" : "list.bullet") }
            return command
        }
    }
    private func reposition() {
        guard let editor, let owner = editor.window, let panel, let state else { return }
        let anchor = state.anchor
        let webRect = NSRect(x: anchor.x,
            y: editor.webView.isFlipped ? anchor.y : editor.webView.bounds.height - anchor.y - anchor.height,
            width: max(1, anchor.width), height: max(1, anchor.height))
        let screenRect = owner.convertToScreen(editor.webView.convert(webRect, to: nil))
        let frame = EditorPopupGeometry.frame(anchor: screenRect,
            size: NSSize(width: SlashMenuMetrics.width, height: SlashMenuMetrics.height(for: descriptors(state))),
            bounds: EditorPopupGeometry.bounds(in: owner))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
    private func send(_ name: String, index: Int) {
        guard let state else { return }
        editor?.perform(name, payload: ["session": state.session, "index": index])
    }
    func cancel() {
        guard let state else { return }
        editor?.perform("popupDismiss", payload: ["session": state.session])
        dismiss()
    }
    func dismiss() {
        state = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
    }
    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
