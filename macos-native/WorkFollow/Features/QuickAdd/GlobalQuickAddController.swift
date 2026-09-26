import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// 纯"解析 → 建任务"接缝：全局快速添加面板与测试共用。
/// 注入 TaskWorkspaceModel，完整复用 QuickAddParser 的全部词表能力。
@MainActor
struct GlobalQuickAddComposer {
    let workspace: TaskWorkspaceModel

    func parse(_ text: String) -> QuickAddParseResult {
        QuickAddParser.parse(text, now: workspace.clock(), calendar: workspace.calendar,
                             availableLists: workspace.allListNames)
    }

    /// 把解析结果映射到 TaskWorkspaceModel 现有创建 API。与快速添加"不悄悄改
    /// 语义"一致：解析不到清单时进收集箱，无日期则不设日期。
    @discardableResult
    func submit(text: String) -> UUID? {
        let parsed = parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let timing = QuickAddScheduleDraft(parsed: parsed, defaultDueAt: nil)
        let result = workspace.createDraft(title: parsed.title,
                                           list: parsed.listName ?? TaskList.inbox.name,
                                           schedule: timing.schedule,
                                           priority: parsed.priority,
                                           tags: parsed.tags,
                                           reminder: timing.reminderAt,
                                           repeatFrequency: timing.repeatFrequency,
                                           recurrenceRule: timing.recurrenceRule)
        return result.taskID
    }
}

/// 全局快速添加：Carbon 全局热键（无需系统权限）+ 无边框 NSPanel 输入卡片。
/// 开关状态持久化在 UserDefaults；实例由 WorkFollowApp 持有，生命周期同应用。
@MainActor
final class GlobalQuickAddController: NSObject, ObservableObject {
    static let enabledDefaultsKey = "globalQuickAddEnabled"
    static let keyCodeDefaultsKey = "globalQuickAddKeyCode"
    static let modifiersDefaultsKey = "globalQuickAddModifiers"
    static let defaultKeyCode = UInt32(kVK_ANSI_A)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)
    static let panelSize = CGSize(width: 480, height: 88)

    private static let hotKeySignature = OSType(0x5746_4144) // 'WFAD'
    private static let hotKeyID: UInt32 = 1

    @Published private(set) var isEnabled: Bool
    let composer: GlobalQuickAddComposer

    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(workspace: TaskWorkspaceModel, defaults: UserDefaults = .standard) {
        self.composer = GlobalQuickAddComposer(workspace: workspace)
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
        super.init()
        if isEnabled { registerHotKey() }
    }

    // MARK: 开关（菜单项驱动，状态落 UserDefaults）

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        if enabled { registerHotKey() } else { hidePanel(); unregisterHotKey() }
    }

    // MARK: 全局热键

    private var hotKeyCode: UInt32 {
        UInt32(defaults.object(forKey: Self.keyCodeDefaultsKey) as? Int ?? Int(Self.defaultKeyCode))
    }
    private var hotKeyModifiers: UInt32 {
        UInt32(defaults.object(forKey: Self.modifiersDefaultsKey) as? Int ?? Int(Self.defaultModifiers))
    }

    /// C 回调里拿不到上下文，经 Unmanaged 取回控制器后派发回主线程弹出/隐藏面板。
    private static let hotKeyEventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let controller = Unmanaged<GlobalQuickAddController>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
            MainActor.assumeIsolated { controller.handleHotKeyPressed() }
        }
        return noErr
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        let installed = InstallEventHandler(GetApplicationEventTarget(), Self.hotKeyEventHandler,
                                            1, &eventType,
                                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        if installed == noErr { eventHandlerRef = handlerRef }
        var registered: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(hotKeyCode, hotKeyModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &registered)
        if status == noErr { hotKeyRef = registered }
    }

    private func unregisterHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
    }

    func handleHotKeyPressed() {
        guard isEnabled else { return }
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    // MARK: 面板

    func showPanel() {
        guard isEnabled else { return }
        hidePanel() // 重建面板，保证每次弹出输入框状态干净
        let panel = makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(x: visible.midX - Self.panelSize.width / 2,
                                 y: visible.maxY - Self.panelSize.height - visible.height * 0.22)
            panel.setFrameOrigin(origin)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 面板回车提交：创建任务后关闭面板并清空（面板随下次弹出重建）。
    func submit(_ text: String) {
        _ = composer.submit(text: text)
        hidePanel()
    }

    private func makePanel() -> NSPanel {
        let panel = QuickAddPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = FirstResponderHostingView(rootView: GlobalQuickAddPanelView(
            composer: composer,
            submit: { [weak self] text in self?.submit(text) },
            close: { [weak self] in self?.hidePanel() }))
        panel.contentView = hosting
        panel.initialFirstResponder = hosting
        return panel
    }
}

/// 无边框面板默认不能成为 key window；快速添加必须接收键盘输入。
private final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 让宿主视图可成为第一响应者，配合 FocusState 把焦点交给输入框。
private final class FirstResponderHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
}

@MainActor
private struct GlobalQuickAddPanelView: View {
    let composer: GlobalQuickAddComposer
    let submit: (String) -> Void
    let close: () -> Void

    @State private var text = ""
    @FocusState private var inputFocused: Bool

    private var parsed: QuickAddParseResult { composer.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            HStack(spacing: WFSpace.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(WFType.detailTitle)
                    .foregroundStyle(WFColors.accent)
                TextField("新建任务：明天下午3点 开会 @工作 !! #周报", text: $text)
                    .textFieldStyle(.plain)
                    .font(WFType.body)
                    .focused($inputFocused)
                    .onSubmit { submit(text) }
            }
            if !parsed.tokens.isEmpty {
                HStack(spacing: WFSpace.xs) {
                    ForEach(parsed.tokens) { token in
                        Text(token.label)
                            .font(WFType.supporting)
                            .foregroundStyle(WFColors.accent)
                            .padding(.horizontal, WFSpace.sm)
                            .padding(.vertical, WFSpace.xs / 2)
                            .background(WFColors.selection, in: Capsule())
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(WFSpace.lg)
        .frame(width: GlobalQuickAddController.panelSize.width,
               height: GlobalQuickAddController.panelSize.height,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: WFMetrics.corner + 2, style: .continuous)
                .fill(WFColors.content)
                .overlay(
                    RoundedRectangle(cornerRadius: WFMetrics.corner + 2, style: .continuous)
                        .strokeBorder(WFColors.border)
                )
        )
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
        .onExitCommand { close() }
    }
}
