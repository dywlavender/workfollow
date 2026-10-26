import AppKit
import Combine
import SwiftUI

/// A document keeps its own editor even when the main workspace changes selection.
enum FloatingEditorID: Hashable {
    case task(UUID)
    case note(UUID)

    var documentID: UUID {
        switch self {
        case .task(let id), .note(let id): return id
        }
    }

    var frameAutosaveName: String {
        switch self {
        case .task: return "WorkFollowFloatingTask"
        case .note: return "WorkFollowFloatingNote"
        }
    }
}

/// Window policy shared by task and note adapters. Stores retain responsibility
/// for document transactions, undo and persistence.
@MainActor
final class FloatingEditorWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = FloatingEditorWindowController()
    static let defaultSize = NSSize(width: 440, height: 600)
    static let minimumSize = NSSize(width: 340, height: 380)

    @Published private(set) var openIDs: Set<FloatingEditorID> = []
    private var panels: [FloatingEditorID: FloatingEditorPanel] = [:]
    private var closeActions: [FloatingEditorID: () -> Void] = [:]
    private var closingIDs: Set<FloatingEditorID> = []

    func panel(for id: FloatingEditorID) -> FloatingEditorPanel? { panels[id] }

    func open<Content: View>(id: FloatingEditorID, title: String,
                             appearance: NativeAppearance = .system,
                             onClose: @escaping () -> Void = {},
                             @ViewBuilder content: (DocumentEditorHandle) -> Content) {
        if panels[id] != nil {
            bringToFront(id)
            return
        }
        let handle = DocumentEditorHandle()
        let panel = FloatingEditorPanel(id: id, title: title, editorHandle: handle)
        panel.delegate = self
        installFrame(for: panel)
        panel.appearance = resolve(appearance)
        let hosting = NSHostingView(rootView: AnyView(content(handle)))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panels[id] = panel
        closeActions[id] = onClose
        openIDs.insert(id)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringToFront(_ id: FloatingEditorID) {
        guard let panel = panels[id] else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.editorHandle.focusEditor()
    }

    func close(_ id: FloatingEditorID) {
        guard !closingIDs.contains(id) else { return }
        panels[id]?.close()
    }

    func closeAll() {
        for id in Array(panels.keys) { close(id) }
    }

    func applyAppearance(_ appearance: NativeAppearance, to ids: Set<FloatingEditorID>) {
        for id in ids { panels[id]?.appearance = resolve(appearance) }
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? FloatingEditorPanel,
              panels[panel.editorID] === panel,
              closingIDs.insert(panel.editorID).inserted else { return }
        let id = panel.editorID
        panel.editorHandle.flushPendingComposition()
        panel.makeFirstResponder(nil)
        panel.saveFrame(usingName: id.frameAutosaveName)
        panels[id] = nil
        let onClose = closeActions.removeValue(forKey: id)
        openIDs.remove(id)
        closingIDs.remove(id)
        // A callback can mutate the store and publish a revision; unregister the
        // editor first so that the revision cannot re-enter a closing window.
        onClose?()
    }

    private func resolve(_ appearance: NativeAppearance) -> NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private func installFrame(for panel: FloatingEditorPanel) {
        let name = panel.editorID.frameAutosaveName
        panel.setFrameAutosaveName(name)
        if !panel.setFrameUsingName(name) {
            let size = Self.defaultSize
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
            panel.setFrame(NSRect(x: visible.midX - size.width / 2,
                                  y: visible.midY - size.height / 2 + 40,
                                  width: size.width, height: size.height), display: false)
        }
        var origin = panel.frame.origin
        while panels.values.contains(where: {
            abs($0.frame.minX - origin.x) < 1 && abs($0.frame.minY - origin.y) < 1
        }) {
            origin.x += 26
            origin.y -= 26
        }
        panel.setFrameOrigin(origin)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(max(frame.width, Self.minimumSize.width), visible.width)
        frame.size.height = min(max(frame.height, Self.minimumSize.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }
}

final class FloatingEditorPanel: NSPanel {
    let editorID: FloatingEditorID
    let editorHandle: DocumentEditorHandle

    init(id: FloatingEditorID, title: String, editorHandle: DocumentEditorHandle) {
        self.editorID = id
        self.editorHandle = editorHandle
        super.init(contentRect: NSRect(origin: .zero, size: FloatingEditorWindowController.defaultSize),
                   styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        self.title = title
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = false
        minSize = FloatingEditorWindowController.minimumSize
        backgroundColor = NSColor(WFColors.content)
        hasShadow = true
        animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not intended") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func resignKey() {
        super.resignKey()
        editorHandle.flushPendingComposition()
    }
    override func performClose(_ sender: Any?) { close() }
}
