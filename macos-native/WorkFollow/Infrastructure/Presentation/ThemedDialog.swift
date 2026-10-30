import AppKit
import SwiftUI

/// 主题化确认对话框。系统 `NSAlert` / SwiftUI `alert` 的材质底不跟随主题，
/// 这里用同样的文案结构和按钮顺序重建，底色取不透明的 `popupFill`，因此在
/// 任意页面、浮层或独立窗口上都不会透出后面的文字。
struct WorkfollowDialogAction {
    enum Role { case primary, secondary, destructive, cancel }

    let title: String
    let role: Role
    let identifier: String?
    /// 只在 `.workfollowAlert` 的异步路径执行；`runModal` 的调用方按返回下标处理。
    let handler: (() -> Void)?

    static func primary(_ title: String, id: String? = nil,
                        action: @escaping () -> Void = {}) -> Self {
        Self(title: title, role: .primary, identifier: id, handler: action)
    }

    static func secondary(_ title: String, id: String? = nil,
                          action: @escaping () -> Void = {}) -> Self {
        Self(title: title, role: .secondary, identifier: id, handler: action)
    }

    static func destructive(_ title: String, id: String? = nil,
                            action: @escaping () -> Void = {}) -> Self {
        Self(title: title, role: .destructive, identifier: id, handler: action)
    }

    static func cancel(_ title: String = "取消", id: String? = nil,
                       action: @escaping () -> Void = {}) -> Self {
        Self(title: title, role: .cancel, identifier: id, handler: action)
    }
}

struct WorkfollowDialogField {
    var placeholder: String
    var value: String
    var requiresContent: Bool = true
}

/// SwiftUI 里的文本框确认框。`text` 在每次按键时写回调用方状态，
/// 因此对话框关掉后按钮动作读到的就是用户刚输入的内容。
struct WorkfollowDialogTextField {
    var placeholder: String
    @Binding var text: String
    var requiresContent: Bool = true
}

@MainActor
enum WorkfollowDialog {
    private static var activeControllers: [ObjectIdentifier: WorkfollowDialogController] = [:]

    /// 同步模态会话，替代 `NSAlert.runModal()`。返回被点按钮的下标。
    static func runModal(title: String,
                         message: String? = nil,
                         field: WorkfollowDialogField? = nil,
                         actions: [WorkfollowDialogAction],
                         textDidChange: ((String) -> Void)? = nil) -> Int {
        guard !actions.isEmpty else { return -1 }
        let controller = WorkfollowDialogController(title: title, message: message,
                                                   field: field, actions: actions,
                                                   textDidChange: textDidChange, over: nil)
        controller.presentModal()
        let response = NSApp.runModal(for: controller.window)
        controller.close()
        return response.rawValue
    }

    /// 非阻塞呈现：SwiftUI 的 `.workfollowAlert` 用这条路径，避免模态循环
    /// 占住主线程，页面状态和测试里的异步等待都能继续推进。
    static func present(title: String,
                        message: String? = nil,
                        field: WorkfollowDialogField? = nil,
                        actions: [WorkfollowDialogAction],
                        textDidChange: ((String) -> Void)? = nil,
                        over window: NSWindow? = nil,
                        observation: ((String, NSView) -> Void)? = nil,
                        completion: @escaping (Int) -> Void) {
        guard !actions.isEmpty else { completion(-1); return }
        let controller = WorkfollowDialogController(title: title, message: message,
                                                   field: field, actions: actions,
                                                   textDidChange: textDidChange, over: window,
                                                   observation: observation)
        let id = ObjectIdentifier(controller)
        activeControllers[id] = controller
        controller.presentAsync { index in
            activeControllers[id] = nil
            completion(index)
        }
    }

    @discardableResult
    static func notice(_ title: String, message: String? = nil, button: String = "好") -> Int {
        runModal(title: title, message: message,
                 actions: [.primary(button)])
    }

    /// 二次确认。`action` 是确认按钮的文案；破坏性动作不占 Return，
    /// 与原先 `NativeDialogActions` 的键盘语义一致。
    @discardableResult
    static func confirm(_ title: String, message: String? = nil,
                        action: String, destructive: Bool = true) -> Bool {
        let actions: [WorkfollowDialogAction] = destructive
            ? [.cancel(), .destructive(action)]
            : [.cancel(), .primary(action)]
        return runModal(title: title, message: message, actions: actions) == 1
    }

    /// 单行输入确认框，替代带 `accessoryView` 的 NSAlert。
    static func prompt(_ title: String, message: String? = nil,
                       placeholder: String = "", value: String = "",
                       confirm: String) -> String? {
        var latest = value
        let field = WorkfollowDialogField(placeholder: placeholder, value: value,
                                          requiresContent: false)
        let index = runModal(title: title, message: message, field: field,
                             actions: [.cancel(), .primary(confirm)],
                             textDidChange: { latest = $0 })
        guard index == 1 else { return nil }
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension View {
    /// SwiftUI `alert` / `confirmationDialog` 的主题化替代。
    /// 动作按数组顺序从左往右排：`[.cancel(), .primary("保存")]` 得到「取消 | 保存」。
    func workfollowAlert(_ title: String,
                         message: String? = nil,
                         isPresented: Binding<Bool>,
                         textField: WorkfollowDialogTextField? = nil,
                         actions: [WorkfollowDialogAction]) -> some View {
        modifier(WorkfollowAlertModifier(title: title, message: message,
                                         isPresented: isPresented, textField: textField,
                                         actions: actions))
    }
}

private struct WorkfollowAlertModifier: ViewModifier {
    let title: String
    let message: String?
    let isPresented: Binding<Bool>
    let textField: WorkfollowDialogTextField?
    let actions: [WorkfollowDialogAction]

    @State private var presenting = false
    @State private var windowRef = WorkfollowDialogWindowRef()
    #if DEBUG
    @Environment(\.workflowActionObservation) private var workflowObservation

    private var dialogObservation: ((String, NSView) -> Void)? { workflowObservation }
    #else
    private var dialogObservation: ((String, NSView) -> Void)? { nil }
    #endif

    func body(content: Content) -> some View {
        content
            .background(WorkfollowDialogWindowReader(ref: windowRef))
            .onAppear { if isPresented.wrappedValue { start() } }
            .onChange(of: isPresented.wrappedValue) { _, presented in
                if presented { start() }
            }
    }

    private func start() {
        guard !presenting else { return }
        presenting = true
        let field = textField
        let fieldModel = field.map {
            WorkfollowDialogField(placeholder: $0.placeholder, value: $0.text,
                                  requiresContent: $0.requiresContent)
        }
        let snapshot = actions
        _Concurrency.Task { @MainActor in
            WorkfollowDialog.present(
                title: title, message: message, field: fieldModel,
                actions: snapshot,
                textDidChange: { value in
                    if let field { field.text = value }
                },
                over: windowRef.window,
                observation: dialogObservation,
                completion: { index in
                    guard snapshot.indices.contains(index) else {
                        presenting = false
                        isPresented.wrappedValue = false
                        return
                    }
                    // 先跑按钮动作，再复位呈现状态：动作里常要读取被清空前
                    // 的目标对象（例如待删除的会话）。
                    snapshot[index].handler?()
                    presenting = false
                    isPresented.wrappedValue = false
                })
        }
    }
}

@MainActor
private final class WorkfollowDialogWindowRef {
    weak var window: NSWindow?
}

private struct WorkfollowDialogWindowReader: NSViewRepresentable {
    let ref: WorkfollowDialogWindowRef

    final class Reader: NSView {
        weak var ref: WorkfollowDialogWindowRef?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ref?.window = window
        }
    }

    func makeNSView(context: Context) -> Reader {
        let view = Reader()
        view.ref = ref
        return view
    }

    func updateNSView(_ nsView: Reader, context: Context) {
        nsView.ref = ref
        ref.window = nsView.window
    }
}

@MainActor
private final class WorkfollowDialogPanel: NSPanel {
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}

@MainActor
private final class WorkfollowDialogController: NSObject, NSWindowDelegate {
    let window: WorkfollowDialogPanel
    private let actions: [WorkfollowDialogAction]
    private let field: WorkfollowDialogField?
    private let onTextChange: ((String) -> Void)?
    private let observation: ((String, NSView) -> Void)?
    private let host: NSHostingView<AnyView>
    private var text: String
    private var monitor: Any?
    private var finished = false
    private var completion: ((Int) -> Void)?
    private weak var previousKeyWindow: NSWindow?
    private var disabledWindows: [NSWindow] = []

    private var cancelIndex: Int {
        actions.firstIndex { $0.role == .cancel } ?? defaultIndex
    }

    /// Return 只触发明确的主动作；破坏性动作和普通选项都不抢 Return，
    /// 没有主动作时落在「取消」上。
    private var defaultIndex: Int {
        if let primary = actions.firstIndex(where: { $0.role == .primary }) { return primary }
        if let cancel = actions.firstIndex(where: { $0.role == .cancel }) { return cancel }
        return 0
    }

    private var primaryDisabled: Bool {
        guard field?.requiresContent == true else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(title: String,
         message: String?,
         field: WorkfollowDialogField?,
         actions: [WorkfollowDialogAction],
         textDidChange: ((String) -> Void)?,
         over window: NSWindow?,
         observation: ((String, NSView) -> Void)? = nil) {
        self.actions = actions
        self.field = field
        self.onTextChange = textDidChange
        self.observation = observation
        self.text = field?.value ?? ""

        let panel = WorkfollowDialogPanel(contentRect: .zero, styleMask: [.borderless],
                                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.title = title
        panel.identifier = NSUserInterfaceItemIdentifier("WorkFollowThemedDialog")
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let parent = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        panel.appearance = parent?.effectiveAppearance ?? NSApp.effectiveAppearance
        self.window = panel

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        self.host = host
        super.init()

        var card = AnyView(WorkfollowDialogCard(
            title: title, message: message, field: field, actions: actions,
            onAction: { [weak self] index in self?.finish(index) },
            onTextChange: { [weak self] value in
                guard let self else { return }
                self.text = value
                self.onTextChange?(value)
            })
            .workfollowNativeTheme())
        #if DEBUG
        if let observation {
            card = AnyView(card.environment(\.workflowActionObservation, observation))
        }
        #endif
        host.rootView = card
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        panel.delegate = self
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(CGSize(width: max(size.width, 1), height: max(size.height, 1)))
        panel.cancelHandler = { [weak self] in self?.cancel() }
        position(over: parent)
        // 作为当前窗口的子窗口呈现：从日期浮层里弹出的确认框不会因为
        // 焦点切到对话框而把浮层一起关掉。
        if let parent, parent.isVisible {
            parent.addChildWindow(panel, ordered: .above)
        }
    }

    func presentModal() {
        installMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if field != nil { window.makeFirstResponder(host) }
        window.invalidateShadow()
    }

    func presentAsync(completion: @escaping (Int) -> Void) {
        self.completion = completion
        // 子窗口盖住父窗口，但不启动模态循环：父窗口（以及它所在的根窗口）
        // 不响应点击，键盘交给对话框。
        previousKeyWindow = NSApp.keyWindow
        var root = window.parent
        while let next = root?.parent { root = next }
        for owner in [window.parent, root].compactMap({ $0 }) where !disabledWindows.contains(where: { $0 === owner }) {
            owner.ignoresMouseEvents = true
            disabledWindows.append(owner)
        }
        installMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if field != nil { window.makeFirstResponder(host) }
        window.invalidateShadow()
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow === window {
            NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: cancelIndex))
            return
        }
        restoreOwner()
        guard !finished, let completion else { return }
        finished = true
        self.completion = nil
        let index = cancelIndex
        DispatchQueue.main.async { completion(index) }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window.cancelHandler = nil
        window.delegate = nil
        restoreOwner()
        if let owner = window.parent { owner.removeChildWindow(window) }
        window.close()
    }

    private func restoreOwner() {
        disabledWindows.forEach { $0.ignoresMouseEvents = false }
        disabledWindows.removeAll()
        if let previousKeyWindow, previousKeyWindow.isVisible, NSApp.isActive {
            previousKeyWindow.makeKey()
        }
        previousKeyWindow = nil
    }

    private func position(over parent: NSWindow?) {
        let size = window.frame.size
        var root = parent
        while let next = root?.parent { root = next }
        let anchor = root?.frame
        let screen = root?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var origin: CGPoint
        if let anchor, root?.isVisible == true {
            origin = CGPoint(x: anchor.midX - size.width / 2,
                             y: anchor.midY - size.height / 2 + min(56, anchor.height * 0.08))
        } else if let screen {
            origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        } else {
            window.center()
            return
        }
        if let screen {
            origin.x = min(max(origin.x, screen.minX + 16), screen.maxX - size.width - 16)
            origin.y = min(max(origin.y, screen.minY + 16), screen.maxY - size.height - 16)
        }
        window.setFrameOrigin(origin)
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window, self.window.isVisible else { return event }
                // 输入法组合中的 Esc/Return 属于候选词，不能顺手关窗。
                if let input = self.window.firstResponder as? NSTextView, input.hasMarkedText() {
                    return event
                }
                switch event.keyCode {
                case 53:
                    self.cancel()
                case 36, 76:
                    guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
                        return event
                    }
                    self.submitDefault()
                default:
                    return event
                }
                return nil
            }
        }
    }

    private func cancel() {
        finish(cancelIndex)
    }

    private func submitDefault() {
        let index = defaultIndex
        if actions[index].role == .primary, primaryDisabled {
            NSSound.beep()
            return
        }
        finish(index)
    }

    private func finish(_ index: Int) {
        guard !finished, actions.indices.contains(index) else { return }
        finished = true
        if NSApp.modalWindow === window {
            NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: index))
            return
        }
        let completion = completion
        self.completion = nil
        close()
        completion?(index)
    }
}

private struct WorkfollowDialogCard: View {
    let title: String
    let message: String?
    let field: WorkfollowDialogField?
    let actions: [WorkfollowDialogAction]
    let onAction: (Int) -> Void
    let onTextChange: (String) -> Void

    @Environment(\.workfollowBackgroundTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(title: String, message: String?, field: WorkfollowDialogField?,
         actions: [WorkfollowDialogAction],
         onAction: @escaping (Int) -> Void,
         onTextChange: @escaping (String) -> Void) {
        self.title = title
        self.message = message
        self.field = field
        self.actions = actions
        self.onAction = onAction
        self.onTextChange = onTextChange
        _text = State(initialValue: field?.value ?? "")
    }

    private func disabled(_ action: WorkfollowDialogAction) -> Bool {
        guard action.role == .primary, field?.requiresContent == true else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WFColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(WFColors.secondaryText)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let field {
                TextField(field.placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($fieldFocused)
                    .onChange(of: text) { _, value in onTextChange(value) }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    button(action, index: index)
                }
            }
        }
        .padding(22)
        .frame(width: 400, alignment: .leading)
        .background(theme.popupFill(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WFColors.border, lineWidth: 1)
        }
        .onAppear { if field != nil { fieldFocused = true } }
    }

    private func button(_ action: WorkfollowDialogAction, index: Int) -> some View {
        let filled = action.role == .primary || action.role == .destructive
        return Button {
            onAction(index)
        } label: {
            Text(action.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(filled ? Color.white : WFColors.text)
                .padding(.horizontal, 14)
                .frame(minWidth: 68, minHeight: 30)
                .background {
                    if filled {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(action.role == .destructive ? WFColors.danger : WFColors.accent)
                    } else {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(WFColors.fieldFill)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(WFColors.border, lineWidth: 1)
                            }
                    }
                }
                .opacity(disabled(action) ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled(action))
        .workflowActionAnchor("dialog.button.\(action.identifier ?? action.title)")
        .accessibilityIdentifier(action.identifier ?? action.title)
    }
}
