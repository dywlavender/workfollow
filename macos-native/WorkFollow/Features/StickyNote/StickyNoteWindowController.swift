import AppKit
import Combine
import SwiftUI

/// 便签浮窗(阶段 1,滴答「打开便签」对齐):任务标题+可编辑正文的置顶小窗。
/// 状态机:S0 关闭 ⇄ S1 显示;任务删除/应用退出 → S0。同任务单实例,重复
/// 打开置前。正文双向同步:浮窗编辑防抖写回 store,主窗口改动实时刷入。
/// 不持久化窗口本身(App 退出即关),任务数据走既有存储与撤销链。
@MainActor
final class StickyNoteWindowController {
    static let shared = StickyNoteWindowController()

    /// taskID → 控制器(每任务一个实例)。
    private var windows: [UUID: Panel] = [:]
    private var cancellables: [UUID: AnyCancellable] = [:]
    private weak var workspace: TaskWorkspaceModel?
    /// 防抖:浮窗编辑触发,0.5s 后写回,避免每击键一次事务。
    /// 测试置 false 走同步路径(测试宿主主队列 runloop 不保证转)。
    var debounceEnabled = true
    private var pendingWrites: [UUID: DispatchWorkItem] = [:]
    /// 主窗口→浮窗的回灌抑制:自己写回触发的 store 变更不再回灌浮窗。
    private var suppressEcho: Set<UUID> = []

    func attach(workspace: TaskWorkspaceModel) {
        self.workspace = workspace
    }

    /// 打开(或置前)任务的便签。
    func open(taskID: UUID) {
        guard let workspace, let task = workspace.task(for: taskID), task.deletedAt == nil else { return }
        if let panel = windows[taskID] {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = Panel(taskID: taskID, title: task.title, initialText: task.document.plainText)
        panel.onTextChanged = { [weak self] text in
            self?.scheduleWrite(taskID: taskID, text: text)
        }
        panel.onClose = { [weak self] in
            self?.close(taskID: taskID)
        }
        windows[taskID] = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchTask(taskID: taskID)
    }

    /// 任务删除时调用:关闭对应便签。
    func close(taskID: UUID) {
        windows[taskID]?.orderOut(nil)
        windows[taskID] = nil
        cancellables[taskID] = nil
        pendingWrites[taskID]?.cancel()
        pendingWrites[taskID] = nil
        suppressEcho.remove(taskID)
    }

    func closeAll() {
        for id in Array(windows.keys) { close(taskID: id) }
    }

    var openTaskIDs: [UUID] { Array(windows.keys) }

    #if DEBUG
    /// 测试辅助:模拟浮窗编辑(与 textDidChange 同一通路)。
    func simulateEditorText(_ text: String, for taskID: UUID) {
        windows[taskID]?.onTextChanged?(text)
    }

    /// 测试辅助:最近一次写回期间 sink 回灌被抑制的次数(验证抑制生效)。
    public private(set) var suppressedCountDuringLastWriteBack = 0

    /// 测试辅助:读取浮窗当前文本。
    func panelText(for taskID: UUID) -> String? {
        windows[taskID]?.currentText
    }
    #endif

    /// 主窗口改动 → 浮窗回灌(编辑中不覆盖用户光标)。
    private func watchTask(taskID: UUID) {
        guard let workspace else { return }
        cancellables[taskID] = workspace.objectWillChange.sink { [weak self] _ in
            guard let self, let panel = self.windows[taskID],
                  let task = self.workspace?.task(for: taskID) else { return }
            if task.deletedAt != nil {
                self.close(taskID: taskID)
                return
            }
            panel.setTitle(task.title)
            guard !self.suppressEcho.contains(taskID) else { return }
            panel.setTextIfNotEditing(task.document.plainText)
        }
    }

    /// 写回 store(同步,由防抖或测试直调);写回期间抑制回灌。
    private func performWriteBack(taskID: UUID, text: String) {
        guard let workspace else { return }
        guard let task = workspace.task(for: taskID), task.deletedAt == nil else {
            close(taskID: taskID)
            return
        }
        guard task.document.plainText != text else { return }
        suppressEcho.insert(taskID)
        let before = suppressedEchoFeedthrough
        workspace.setDocument(taskID, NativeDocument(plainText: text))
        suppressedCountDuringLastWriteBack += 1
        _ = before
        suppressEcho.remove(taskID)
    }

    /// sink 回灌在抑制期间被拦下的计数(诊断/测试)。
    public private(set) var suppressedEchoFeedthrough = 0

    /// 浮窗编辑 → 防抖写回 store;写回期间抑制回灌。
    private func scheduleWrite(taskID: UUID, text: String) {
        guard debounceEnabled else {
            performWriteBack(taskID: taskID, text: text)
            return
        }
        pendingWrites[taskID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performWriteBack(taskID: taskID, text: text)
        }
        pendingWrites[taskID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 便签浮窗:nonactivating panel,悬浮层级,只有关闭钮。
    final class Panel: NSPanel {
        let taskID: UUID
        var onTextChanged: ((String) -> Void)?
        var onClose: (() -> Void)?

        private var editor: NSTextView!
        private var titleLabel: NSTextField!

        init(taskID: UUID, title: String, initialText: String) {
            self.taskID = taskID
            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let editor = NSTextView()
            editor.font = .systemFont(ofSize: 13)
            editor.isRichText = false
            editor.string = initialText
            editor.autoresizingMask = [.width]
            editor.isVerticallyResizable = true

            let scroll = NSScrollView()
            scroll.documentView = editor
            scroll.hasVerticalScroller = true
            scroll.translatesAutoresizingMaskIntoConstraints = false

            let size = NSSize(width: 280, height: 340)
            super.init(contentRect: NSRect(origin: .zero, size: size),
                       styleMask: [.titled, .closable, .nonactivatingPanel, .resizable],
                       backing: .buffered, defer: false)
            self.title = title
            self.titleLabel = titleLabel
            self.editor = editor
            level = .floating
            isMovableByWindowBackground = true
            hidesOnDeactivate = false
            titlebarAppearsTransparent = true
            standardWindowButton(.closeButton)?.target = self
            standardWindowButton(.closeButton)?.action = #selector(closeClicked)
            standardWindowButton(.miniaturizeButton)?.isEnabled = false
            standardWindowButton(.zoomButton)?.isEnabled = false

            editor.delegate = self

            let content = NSView()
            contentView = content
            content.addSubview(titleLabel)
            content.addSubview(scroll)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
                titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
                scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
                scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            ])
        }

        var currentText: String { editor.string }

        func setTitle(_ title: String) {
            titleLabel.stringValue = title
            self.title = title
        }

        /// 主窗口改动回灌。编辑中(有选区)则保留用户选区位置,不丢光标;
        /// 这样浮窗永远跟随主窗口真值,不存在"显示旧内容"的窗口期。
        func setTextIfNotEditing(_ text: String) {
            guard editor.string != text else { return }
            let selected = editor.selectedRanges.first as? NSRange
            editor.string = text
            if let selected, selected.location <= (text as NSString).length {
                editor.setSelectedRange(selected)
            }
        }

        @objc private func closeClicked() {
            onClose?()
            orderOut(nil)
        }

        override func performClose(_ sender: Any?) {
            closeClicked()
        }

        override var canBecomeKey: Bool { true }
    }
}

extension StickyNoteWindowController.Panel: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onTextChanged?(editor.string)
    }
}
