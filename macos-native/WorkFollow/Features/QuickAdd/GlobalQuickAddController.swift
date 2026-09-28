import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// 纯"解析 → 建任务"接缝：全局快速添加面板与测试共用。
/// 注入 TaskWorkspaceModel，完整复用 QuickAddParser 的全部词表能力。
@MainActor
struct GlobalQuickAddComposer {
    let workspace: TaskWorkspaceModel

    /// `dismissedTokenIDs` 与列表条同源：面板里把识别错的 chip 点掉之后，
    /// 重解析要忽略那一段，否则「点掉」只是视觉上消失、任务上仍然带着它。
    func parse(_ text: String, dismissedTokenIDs: Set<String> = []) -> QuickAddParseResult {
        QuickAddParser.parse(text, now: workspace.clock(), calendar: workspace.calendar,
                             knownLists: Set(workspace.allListNames),
                             dismissedTokenIDs: dismissedTokenIDs)
    }

    /// 把草稿映射到 TaskWorkspaceModel 现有创建 API，返回**第一条**任务的 ID。
    ///
    /// 组合规则与列表快速添加条完全一致（同一个 `QuickAddComposition`）：换行拆成
    /// 多条任务，描述只跟随单条创建。返回首条 ID 而不是条数，是为了保住原有的
    /// `UUID?` 契约——调用方只需要知道「有没有建成」；批量条数由
    /// `QuickAddComposition.batchLines` 决定，不在这里另算一份。
    ///
    /// **落点与列表条对齐**（审计 §三）：`清单 = 解析出的 @清单 ?? 当前清单 ?? 收集箱`、
    /// `标签 = 当前标签 ∪ 解析出的 #标签`。面板是个全局浮层，用户看不出它「属于」
    /// 哪个视图，所以这两个上下文必须从 workspace 读，否则面板建的任务会莫名
    /// 掉进收集箱、且丢掉用户当前正筛着的标签——那是会丢数据的差异。
    ///
    /// **默认日期是刻意取的取舍，不是漏抄**：列表条在 `.today` 视图下默认今天，
    /// 而全局面板没有视图上下文，无法推断「用户此刻在哪个视图」，所以恒为
    /// `defaultDueAt: nil`（不预设日期）。对齐参照物也没有全局入口可比。
    @discardableResult
    func submit(text: String, description: String = "",
                dismissedTokenIDs: Set<String> = []) -> UUID? {
        let lines = QuickAddComposition.batchLines(in: text)
        guard !lines.isEmpty else { return nil }
        let batch = lines.count > 1
        let note = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var firstID: UUID?

        for line in lines {
            // 单行时沿用整条草稿的解析结果（只有它带着 chip 点掉的忽略状态）；
            // 批量时逐行独立解析，行与行之间不互相污染。
            let parsed = batch ? parse(line) : parse(text, dismissedTokenIDs: dismissedTokenIDs)
            guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let timing = QuickAddScheduleDraft(parsed: parsed, defaultDueAt: nil)
            let list = parsed.listName ?? workspace.activeList ?? TaskList.inbox.name
            var tags = workspace.activeTag.map { [$0] } ?? []
            tags.append(contentsOf: parsed.tags)
            tags = tags.reduce(into: []) { values, tag in
                if !values.contains(tag) { values.append(tag) }
            }
            let result = workspace.createDraft(title: parsed.title,
                                               list: list,
                                               schedule: timing.schedule,
                                               priority: parsed.priority,
                                               tags: tags,
                                               reminder: timing.reminderAt,
                                               repeatFrequency: timing.repeatFrequency,
                                               recurrenceRule: timing.recurrenceRule,
                                               document: batch ? NativeDocument.empty
                                                               : NativeDocument(plainText: note))
            if let id = result.taskID, firstID == nil { firstID = id }
        }
        return firstID
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

    /// 面板宽度固定；高度由 SwiftUI 内容实测上报——描述行、候选列表、批量提示
    /// 都会把面板撑高。写死高度会让候选列表被窗口边缘裁掉，而给一个「够大」的
    /// 固定高度又会留出一块透明区域吃掉本该落到其它应用的点击。
    static let panelWidth: CGFloat = 480
    static let panelMinHeight: CGFloat = 76
    static let panelMaxHeight: CGFloat = 460
    static let panelSize = CGSize(width: panelWidth, height: panelMinHeight)

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
            let size = panel.frame.size
            // 面板按「顶边固定、向下生长」布局，所以位置一次算好顶边即可。
            let topEdge = visible.maxY - visible.height * 0.22
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: topEdge - size.height))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 面板回车提交：建成任务后关闭面板并清空（面板随下次弹出重建）。
    ///
    /// 一条都没建成时**不关面板**：草稿里只有「明天」这类纯 token 时提交是空操作，
    /// 直接关掉会让人以为任务建好了。留着面板，用户能接着补标题。
    func submit(_ text: String, description: String,
                dismissedTokenIDs: Set<String> = []) {
        let created = composer.submit(text: text, description: description,
                                      dismissedTokenIDs: dismissedTokenIDs)
        if created != nil { hidePanel() }
    }

    /// SwiftUI 内容实测高度回传：只改高度，顶边不动，避免面板「跳一下」。
    private func resizePanel(toHeight height: CGFloat) {
        guard let panel else { return }
        let target = min(max(height, Self.panelMinHeight), Self.panelMaxHeight)
        let current = panel.frame.height
        guard abs(target - current) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - target
        frame.size.height = target
        panel.setFrame(frame, display: true)
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
            submit: { [weak self] text, description, dismissed in
                self?.submit(text, description: description, dismissedTokenIDs: dismissed)
            },
            close: { [weak self] in self?.hidePanel() },
            onHeightChange: { [weak self] height in
                // 偏好回调发生在布局过程中，改窗口尺寸要等这一帧排完。
                DispatchQueue.main.async { self?.resizePanel(toHeight: height) }
            }))
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

/// 内容实测高度：面板要按它调窗口大小，所以只能量真实布局，不能在控制器里
/// 另写一套「行高 × 行数」的算式——那正是两处尺寸迟早对不上的经典来源。
private struct GlobalPanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
private struct GlobalQuickAddPanelView: View {
    let composer: GlobalQuickAddComposer
    let submit: (String, String, Set<String>) -> Void
    let close: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var text = ""
    /// Tab 拉出来的任务描述。只跟随单条创建；批量时每一行各自成任务，不带描述。
    @State private var descriptionDraft = ""
    /// 与列表快速添加条共用同一套候选/描述状态机：同一串按键在两个入口必须同解。
    @State private var candidate = QuickAddCandidateState()
    /// 被点掉的识别 chip。与列表条同源：点掉后重解析要忽略那一段。
    @State private var dismissedTokens: Set<String> = []
    /// 输入框是否持有焦点。**两个方向共用的唯一真值。**
    ///
    /// 这里曾经是 `@FocusState`（死信号，见 `QuickAddTextField.focused` 的说明）
    /// 外加一路 `fieldFocused` 兜底，于是 `.onAppear` 里那句「打开面板自动聚焦
    /// 输入框」是无效写——面板弹出来焦点还在宿主视图上，打字没反应。
    /// 换成普通 `@State` 之后，`updateNSView` 的正向分支才会真的执行。
    @State private var inputFocused = false
    @FocusState private var descriptionFocused: Bool

    private var parsed: QuickAddParseResult {
        composer.parse(text, dismissedTokenIDs: dismissedTokens)
    }
    /// 粘贴进来的多行草稿会按行拆成多个任务；>1 时给出明确提示。
    private var batchCount: Int { QuickAddComposition.batchLines(in: text).count }

    var body: some View {
        VStack(alignment: .leading, spacing: WFSpace.sm) {
            inputRow
            if candidate.descriptionVisible || !descriptionDraft.isEmpty { descriptionRow }
            if batchCount > 1 {
                Text("换行将创建 \(batchCount) 个任务")
                    .font(WFType.supporting)
                    .foregroundStyle(WFColors.secondaryText)
                    .padding(.leading, 24)
            }
            if isCandidateListVisible { candidateList }
            if !parsed.tokens.isEmpty { tokenStrip }
        }
        .padding(WFSpace.lg)
        .frame(width: GlobalQuickAddController.panelWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: GlobalPanelHeightKey.self, value: proxy.size.height)
        })
        .background(
            RoundedRectangle(cornerRadius: WFMetrics.corner + 2, style: .continuous)
                .fill(WFColors.content)
                .overlay(
                    RoundedRectangle(cornerRadius: WFMetrics.corner + 2, style: .continuous)
                        .strokeBorder(WFColors.border)
                )
        )
        .onPreferenceChange(GlobalPanelHeightKey.self) { onHeightChange($0) }
        .onChange(of: text) { _, _ in candidate.textDidChange() }
        // 面板一弹出就把焦点交给输入框。以前这行是无效写（`@FocusState` 死信号），
        // 面板弹出来焦点还停在宿主视图上，打字没反应。
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
        .onExitCommand(perform: handleEscape)
    }

    // MARK: 输入行

    private var inputRow: some View {
        HStack(spacing: WFSpace.sm) {
            Image(systemName: "plus.circle.fill")
                .font(WFType.detailTitle)
                .foregroundStyle(WFColors.accent)
            // 与列表快速添加条同一个 AppKit 桥：智能识别着色、Tab/上下键、粘贴保换行
            // 全部复用，面板只换字号（14 vs 13）。
            QuickAddTextField(
                text: $text,
                placeholder: "新建任务：明天下午3点 开会 @工作 !! #周报",
                tokens: parsed.tokens,
                focused: $inputFocused,
                onSubmit: { submit(text, descriptionDraft, dismissedTokens) },
                onEscape: handleEscape,
                onTab: handleTab,
                onShiftReturn: openDescription,
                onMoveUp: { moveSelection(by: -1) },
                onMoveDown: { moveSelection(by: 1) },
                onFieldFocusChange: { inputFocused = $0 },
                fontSize: 14
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var descriptionRow: some View {
        HStack(spacing: WFSpace.sm) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 11))
                .foregroundStyle(WFColors.secondaryText)
                .frame(width: 12)
            TextField("添加描述", text: $descriptionDraft)
                .textFieldStyle(.plain)
                .font(WFType.control)
                .foregroundStyle(WFColors.text)
                .focused($descriptionFocused)
                .onSubmit { submit(text, descriptionDraft, dismissedTokens) }
                .onExitCommand { closeDescriptionRow() }
        }
        .padding(.leading, 24)
    }

    private var tokenStrip: some View {
        QuickAddTokenFlowLayout(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(parsed.tokens) { token in
                // 与列表条一致：识别错了要能撤销。面板原先这里是纯 `Text`，
                // 点不掉——用户在面板里打错一个「明天」就只能整个重打。
                Button {
                    dismissedTokens.insert(token.id)
                } label: {
                    let color = QuickAddTokenColor.swiftUIColor(for: token.kind)
                    HStack(spacing: 3) {
                        Text(token.label)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                    }
                    .font(WFType.supporting)
                    .foregroundStyle(color)
                    .padding(.horizontal, WFSpace.sm)
                    .padding(.vertical, WFSpace.xs / 2)
                    .background(color.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("移除识别项：\(token.label)")
            }
        }
        .padding(.leading, 24)
    }

    // MARK: `#` / `@` 候选

    @ViewBuilder
    private var candidateList: some View {
        if let marker = activeMarker {
            QuickAddCandidateList(
                names: candidateNames,
                selectedIndex: min(candidate.selection, max(0, candidateNames.count - 1)),
                emptyMessage: marker.kind == .tag ? "没有匹配的标签" : "没有匹配的清单",
                icon: marker.kind == .tag ? "tag" : "list.bullet",
                onHover: { candidate.selection = $0 },
                onCommit: { commitCandidate($0) }
            )
            .padding(.leading, 24)
        }
    }

    /// 输入末尾的标记片段，且没被 Esc 忽略过。
    /// 焦点判据就是输入框的聚焦真值，与列表条同一套。
    private var activeMarker: QuickAddComposition.MarkerQuery? {
        candidate.marker(in: text, isFocused: inputFocused)
    }

    /// 候选来源：`#` 查已有标签、`@` 查已有清单。
    private func candidateSource(_ kind: QuickAddComposition.MarkerQuery.Kind) -> [String] {
        kind == .tag ? composer.workspace.tagNames : composer.workspace.allListNames
    }

    private var candidateNames: [String] {
        guard let marker = activeMarker else { return [] }
        return QuickAddComposition.candidates(candidateSource(marker.kind), matching: marker.query)
    }

    private var isCandidateListVisible: Bool {
        candidate.isListVisible(marker: activeMarker, names: candidateNames)
    }

    /// Tab：候选列表开着就先提交候选，否则把焦点送进描述行。
    private func handleTab() {
        if isCandidateListVisible, candidate.selection >= 0, candidate.selection < candidateNames.count {
            commitCandidate(candidateNames[candidate.selection])
            return
        }
        openDescription()
    }

    /// Shift+↩︎：按字面意思就是「加描述」，不参与候选提交；候选列表让位收起。
    private func openDescription() {
        if isCandidateListVisible { candidate.dismiss(draft: text) }
        candidate.descriptionVisible = true
        DispatchQueue.main.async { descriptionFocused = true }
    }

    /// 上下键：只有候选列表开着时才消费按键，否则让插入点照常移动。
    private func moveSelection(by delta: Int) -> Bool {
        guard isCandidateListVisible else { return false }
        return candidate.move(by: delta, count: candidateNames.count)
    }

    private func commitCandidate(_ name: String) {
        text = QuickAddComposition.replacingTrailingMarker(in: text, with: name)
        candidate.textDidChange()
        inputFocused = true
    }

    private func closeDescriptionRow() {
        descriptionFocused = false
        if descriptionDraft.isEmpty { candidate.descriptionVisible = false }
        DispatchQueue.main.async { inputFocused = true }
    }

    /// Esc 分层：候选列表 → 描述行 → 关面板。一次只收一层，不顺手丢掉草稿。
    ///
    /// 终态与列表条不同（列表条第一下只收起、不清空），这是**有意的取舍**：
    /// 面板是个即用即走的浮层，每次弹出都会重建，草稿本来就活不过一次隐藏，
    /// 所以「先收起再清空」两级在这里没有可承载的中间态。参照物也没有全局入口可比。
    private func handleEscape() {
        if isCandidateListVisible {
            candidate.dismiss(draft: text)
            return
        }
        if candidate.descriptionVisible || descriptionFocused {
            closeDescriptionRow()
            return
        }
        close()
    }
}
