import AppKit
import SwiftUI

/// Business menus share the property-panel window, focus and dismissal rules.
/// The application menu bar and macOS-owned dialogs remain native.
struct BusinessMenu<Label: View, Content: View>: View {
    let width: CGFloat
    let title: String
    let search: Binding<String>?
    let presentation: Binding<Bool>?
    private let label: Label
    private let content: () -> Content
    @Environment(\.businessMenuContext) private var parent
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var controller = BusinessMenuController()
    @StateObject private var presenter = PopupPresentingWindow()
    @State private var presented = false
    @State private var identity = UUID()

    init(width: CGFloat = PopupMetrics.menuWidth, title: String = "操作菜单", search: Binding<String>? = nil,
         isPresented: Binding<Bool>? = nil,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.width = width; self.title = title; self.search = search; self.presentation = isPresented
        self.content = content; self.label = label()
    }

    private var showing: Binding<Bool> {
        Binding(get: { parent.map { $0.controller.activeChild == identity } ?? (presentation?.wrappedValue ?? presented) },
                set: { value in
                    if let parent {
                        if value { parent.controller.activeChild = identity }
                        else if parent.controller.activeChild == identity { parent.controller.activeChild = nil }
                    } else if let presentation { presentation.wrappedValue = value }
                    else { presented = value }
                })
    }

    var body: some View {
        Group {
            if let parent {
                BusinessMenuRow(controller: parent.controller, id: identity, submenu: true,
                    activate: open, hover: { parent.controller.hoverChild(identity, entering: $0, open: open) }) {
                    HStack(spacing: 8) {
                        label
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WFColors.secondaryText)
                    }
                }
            } else {
                Button {
                    showing.wrappedValue.toggle()
                    if showing.wrappedValue { prepareOpening() }
                } label: { label.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            }
        }
        .background(PopupPresentingWindowReader(owner: presenter))
        .businessMenuTriggerProbe(title)
        .background {
            AnchoredPropertyPanel(isPresented: showing, width: width,
                placement: parent == nil ? .dropdown : .submenu,
                focusPolicy: search == nil ? .preservePresenter : .panel, title: title) {
                BusinessMenuContent(controller: controller, close: { showing.wrappedValue = false },
                    dismissAll: {
                        showing.wrappedValue = false
                        parent?.dismissAll()
                    }, search: search, searchLabel: "搜索" + title, content: content)
            }
        }
        .onDisappear { showing.wrappedValue = false; controller.reset() }
        .onChange(of: showing.wrappedValue) { _, visible in if !visible { controller.reset() } }
        .onChange(of: isEnabled) { _, enabled in if !enabled { showing.wrappedValue = false } }
    }

    private func prepareOpening() {
        PopupInteractionRegistry.shared.dismissOtherBranches(presentingFrom: presenter.window)
        controller.reset()
    }
    private func open() {
        guard isEnabled else { return }
        prepareOpening()
        showing.wrappedValue = true
    }
}

extension BusinessMenu where Label == BusinessMenuTitleLabel {
    init(_ title: String, width: CGFloat = PopupMetrics.menuWidth,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(width: width, title: title, content: content) { BusinessMenuTitleLabel(title: title) }
    }
    init(_ title: String, systemImage: String, width: CGFloat = PopupMetrics.menuWidth,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(width: width, title: title, content: content) { BusinessMenuTitleLabel(title: title, symbol: systemImage) }
    }
}

struct BusinessMenuTitleLabel: View {
    let title: String
    var symbol: String?
    @Environment(\.businessMenuContext) private var context
    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).frame(width: 16) }
            Text(title)
            if context == nil {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
        }
        .padding(.horizontal, context == nil ? 8 : 0)
        .frame(minHeight: context == nil ? 28 : nil)
        .background(context == nil ? WFColors.secondarySurface : .clear,
                    in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
    }
}

struct BusinessChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String?
    var color: Color?
    var id: Value { value }
    init(_ value: Value, _ title: String, symbol: String? = nil, color: Color? = nil) {
        self.value = value; self.title = title; self.symbol = symbol; self.color = color
    }
}

/// Explicit choices keep selection and labels in business code; no introspection
/// of SwiftUI's private Picker representation is needed.
struct BusinessPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [BusinessChoice<Value>]
    var width: CGFloat = PopupMetrics.menuWidth
    private var showsTitle = true
    @State private var query = ""
    private var selectedTitle: String { options.first { $0.value == selection }?.title ?? "请选择" }

    init(_ title: String, selection: Binding<Value>, options: [BusinessChoice<Value>],
         width: CGFloat = PopupMetrics.menuWidth) {
        self.title = title; _selection = selection; self.options = options; self.width = width
    }
    func labelsHidden() -> Self { var result = self; result.showsTitle = false; return result }

    var body: some View {
        HStack(spacing: 8) {
            if showsTitle { Text(title).foregroundStyle(WFColors.secondaryText) }
            BusinessMenu(width: width, title: title, search: options.count > 10 ? $query : nil) {
                BusinessMenuChoices(selection: $selection, options: filtered)
                if filtered.isEmpty {
                    Text("没有匹配项").font(WFType.supporting).foregroundStyle(WFColors.secondaryText).padding(10)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                }
                .font(WFType.body).foregroundStyle(WFColors.text)
                .padding(.horizontal, 8).frame(minHeight: 28)
                .background(WFColors.secondarySurface, in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
                .contentShape(Rectangle())
            }
            .accessibilityLabel(title).accessibilityValue(selectedTitle)
            .onDisappear { query = "" }
        }
        .onChange(of: selection) { _, _ in query = "" }
    }
    private var filtered: [BusinessChoice<Value>] {
        options.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }
}

struct BusinessMenuChoices<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [BusinessChoice<Value>]
    var body: some View {
        ForEach(options) { option in
            BusinessMenuOption(option.title, selected: selection == option.value,
                               symbol: option.symbol, color: option.color) { selection = option.value }
        }
    }
}

struct BusinessMenuOption: View {
    let title: String
    var selected: Bool
    var symbol: String?
    var color: Color?
    /// 选中时是否把整行文字染成强调色。
    /// 任务右键菜单的优先级/清单等选项一直是正文色 + 勾选，快速添加弹层要保持同一套观感。
    var tintsWhenSelected = true
    /// 是否显示右侧勾选。任务详情的优先级菜单靠「实心旗」表达当前值，没有勾选列。
    var showsCheckmark = true
    let action: () -> Void
    @Environment(\.businessMenuContext) private var context
    @State private var identity = UUID()
    init(_ title: String, selected: Bool = false, symbol: String? = nil, color: Color? = nil,
         tintsWhenSelected: Bool = true, showsCheckmark: Bool = true,
         action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.symbol = symbol; self.color = color
        self.tintsWhenSelected = tintsWhenSelected; self.showsCheckmark = showsCheckmark
        self.action = action
    }
    var body: some View {
        Group {
            if let context {
                BusinessMenuRow(controller: context.controller, id: identity, activate: {
                    context.dismissAll()
                    DispatchQueue.main.async(execute: action)
                }) { optionLabel }
                .onAppear {
                    if selected, context.controller.highlighted == nil {
                        context.controller.highlighted = identity
                        context.controller.scrollTarget = identity
                    }
                }
            } else {
                Button(action: action) { optionLabel }.buttonStyle(.plain)
            }
        }
        .accessibilityLabel(title).accessibilityValue(selected ? "已选择" : "未选择")
        .help(title)
    }
    private var optionLabel: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).frame(width: 16).foregroundStyle(color ?? WFColors.secondaryText) }
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                .frame(width: 14)
                .opacity(selected && showsCheckmark ? 1 : 0)
        }
        .foregroundStyle(selected && tintsWhenSelected ? WFColors.accent : WFColors.text)
    }
}

struct BusinessMenuSection: View {
    let title: String
    var body: some View {
        Text(title).font(WFType.caption).foregroundStyle(WFColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 5)
    }
}

private struct BusinessMenuContext {
    let controller: BusinessMenuController
    let dismissAll: () -> Void
}
private struct BusinessMenuContextKey: EnvironmentKey {
    static let defaultValue: BusinessMenuContext? = nil
}
private struct BusinessMenuSubmenuActionKey: EnvironmentKey {
    static let defaultValue = false
}
extension View {
    func businessMenuSubmenuAction() -> some View {
        environment(\.businessMenuSubmenuAction, true)
    }
}
private extension EnvironmentValues {
    var businessMenuSubmenuAction: Bool {
        get { self[BusinessMenuSubmenuActionKey.self] }
        set { self[BusinessMenuSubmenuActionKey.self] = newValue }
    }
}
private extension EnvironmentValues {
    var businessMenuContext: BusinessMenuContext? {
        get { self[BusinessMenuContextKey.self] }
        set { self[BusinessMenuContextKey.self] = newValue }
    }
}

/// Only the highlighted row and active child are observed. Mouse feedback has no
/// animation, and pending child openings are cancelled when the menu closes.
@MainActor
final class BusinessMenuController: ObservableObject {
    struct Action {
        var enabled: Bool
        var submenu: Bool
        var perform: () -> Void
        var openSubmenu: (() -> Void)? = nil
    }
    @Published var highlighted: UUID?
    @Published var scrollTarget: UUID?
    @Published var activeChild: UUID?
    var order: [UUID] = []
    var actions: [UUID: Action] = [:]
    private var pendingChild: UUID?
    private var pending: DispatchWorkItem?

    func reset() {
        pending?.cancel(); pending = nil; pendingChild = nil
        highlighted = nil; scrollTarget = nil; activeChild = nil
    }
    func hoverChild(_ id: UUID, entering: Bool, open: @escaping () -> Void) {
        if !entering {
            if pendingChild == id { pending?.cancel(); pending = nil; pendingChild = nil }
            return
        }
        highlighted = id
        pending?.cancel()
        guard activeChild != id else { return }
        if activeChild != nil { open(); return }
        pendingChild = id
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingChild == id else { return }
            self.pendingChild = nil; self.pending = nil; open()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PopupMetrics.submenuIntent, execute: work)
    }
    func hoverAction(_ id: UUID) {
        pending?.cancel(); pending = nil; pendingChild = nil
        highlighted = id; activeChild = nil
    }
    func move(_ delta: Int) {
        let enabled = order.filter { actions[$0]?.enabled == true }
        guard !enabled.isEmpty else { highlighted = nil; return }
        let next = highlighted.flatMap { enabled.firstIndex(of: $0) }.map {
            ($0 + delta + enabled.count) % enabled.count
        } ?? (delta < 0 ? enabled.count - 1 : 0)
        hoverAction(enabled[next])
        scrollTarget = enabled[next]
    }
    func perform(onlySubmenu: Bool = false) {
        let id = highlighted ?? order.first { actions[$0]?.enabled == true }
        guard let id, let action = actions[id], action.enabled, !onlySubmenu || action.submenu else { return }
        if onlySubmenu { (action.openSubmenu ?? action.perform)() }
        else { action.perform() }
    }
}

private struct BusinessMenuRowIDs: PreferenceKey {
    static var defaultValue: [UUID] = []
    static func reduce(value: inout [UUID], nextValue: () -> [UUID]) { value += nextValue() }
}

private struct BusinessMenuContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct BusinessMenuContent<Content: View>: View {
    @ObservedObject var controller: BusinessMenuController
    let close: () -> Void
    let dismissAll: () -> Void
    var search: Binding<String>? = nil
    var searchLabel = "搜索"
    var maximumHeight: CGFloat? = PopupMetrics.menuMaximumHeight
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = PopupMetrics.menuRowHeight
    var body: some View {
        VStack(spacing: 6) {
            if let search {
                TextField(searchLabel, text: search).textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 4).padding(.top, 4)
                    .accessibilityLabel(searchLabel)
            }
            if let maximumHeight {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: contentHeight > maximumHeight) {
                        rows
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: BusinessMenuContentHeight.self,
                                                   value: geometry.size.height)
                        })
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(contentHeight, maximumHeight))
                    .onChange(of: controller.scrollTarget) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
                }
            } else {
                rows
            }
        }
        .padding(PopupMetrics.menuInset)
        .font(WFType.body).foregroundStyle(WFColors.text)
        .environment(\.businessMenuContext, BusinessMenuContext(controller: controller, dismissAll: dismissAll))
        .environment(\.businessMenuSubmenuAction, false)
        .buttonStyle(BusinessMenuButtonStyle(controller: controller, dismissAll: dismissAll))
        .toggleStyle(BusinessMenuToggleStyle(controller: controller))
        .onPreferenceChange(BusinessMenuContentHeight.self) { updateHeight($0) }
        .onPreferenceChange(BusinessMenuRowIDs.self) { ids in
            controller.order = ids
            if let current = controller.highlighted, !ids.contains(current) { controller.highlighted = nil }
        }
        .background(BusinessMenuKeyboard(controller: controller, close: close))
        .transaction { $0.animation = nil }
        .onDisappear { controller.reset(); search?.wrappedValue = "" }
    }
    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) { content() }
            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
    }
    private func updateHeight(_ height: CGFloat) {
        guard height > 0, abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
    }
}

private struct BusinessMenuButtonStyle: PrimitiveButtonStyle {
    let controller: BusinessMenuController
    let dismissAll: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        BusinessMenuButton(controller: controller, role: configuration.role, action: {
            dismissAll()
            // Defer sheets and native modal actions until child windows detach.
            DispatchQueue.main.async { configuration.trigger() }
        }) { configuration.label }
    }
}
private struct BusinessMenuButton<Label: View>: View {
    let controller: BusinessMenuController
    let role: ButtonRole?
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var identity = UUID()
    @Environment(\.businessMenuSubmenuAction) private var isSubmenu
    var body: some View {
        BusinessMenuRow(controller: controller, id: identity, submenu: isSubmenu, activate: action) { label() }
            .foregroundStyle(role == .destructive ? WFColors.danger : WFColors.text)
    }
}
private struct BusinessMenuToggleStyle: ToggleStyle {
    let controller: BusinessMenuController
    func makeBody(configuration: Configuration) -> some View {
        BusinessMenuButton(controller: controller, role: nil, action: { configuration.isOn.toggle() }) {
            HStack(spacing: 8) {
                configuration.label
                Spacer(minLength: 8)
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WFColors.accent).opacity(configuration.isOn ? 1 : 0)
            }
        }.accessibilityValue(configuration.isOn ? "已选择" : "未选择")
    }
}

struct BusinessMenuRow<Label: View>: View {
    @ObservedObject var controller: BusinessMenuController
    let id: UUID
    var submenu = false
    let activate: () -> Void
    var hover: ((Bool) -> Void)?
    var openSubmenu: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        HStack(spacing: 0) {
            Button(action: activate) {
                HStack(spacing: 8) { label(); Spacer(minLength: 0) }
                    .frame(maxWidth: .infinity, minHeight: PopupMetrics.menuRowHeight, alignment: .leading)
                    .padding(.horizontal, 10).contentShape(Rectangle())
            }
            if let openSubmenu {
                Button(action: openSubmenu) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WFColors.secondaryText)
                        .frame(width: 24, height: PopupMetrics.menuRowHeight).contentShape(Rectangle())
                }.accessibilityLabel("展开子菜单")
            }
        }
        .buttonStyle(.plain).opacity(enabled ? 1 : 0.4)
        .background(enabled && controller.highlighted == id ? WFColors.hover : .clear,
                    in: RoundedRectangle(cornerRadius: PopupMetrics.buttonCornerRadius))
        .onHover { inside in
            guard enabled else { return }
            if let hover { hover(inside) }
            else if inside { controller.hoverAction(id) }
        }
        .background(BusinessMenuActionRegistration(controller: controller, id: id,
            action: .init(enabled: enabled, submenu: submenu, perform: activate, openSubmenu: openSubmenu)))
        .preference(key: BusinessMenuRowIDs.self, value: [id])
        .id(id)
        .businessMenuRowProbe(id, highlighted: controller.highlighted == id)
    }
}

private struct BusinessMenuActionRegistration: NSViewRepresentable {
    let controller: BusinessMenuController
    let id: UUID
    let action: BusinessMenuController.Action
    final class Registration { var controller: BusinessMenuController?; var id: UUID? }
    func makeCoordinator() -> Registration { Registration() }
    final class RegistrationView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView { RegistrationView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.controller = controller; context.coordinator.id = id
        controller.actions[id] = action
    }
    static func dismantleNSView(_ view: NSView, coordinator: Registration) {
        if let id = coordinator.id { coordinator.controller?.actions.removeValue(forKey: id) }
    }
}

private struct BusinessMenuKeyboard: NSViewRepresentable {
    let controller: BusinessMenuController
    let close: () -> Void
    final class KeyView: NSView {
        var controller: BusinessMenuController?
        var close: () -> Void = {}
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated { self?.handle(event) == true }
                return handled ? nil : event
            }
        }
        func handle(_ event: NSEvent) -> Bool {
            guard let window, window.isVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  NSApp.modalWindow == nil, window.attachedSheet == nil else { return false }
            var ancestor: NSWindow? = window
            var ownsEvent = false
            while let current = ancestor {
                if current === event.window { ownsEvent = true; break }
                ancestor = current.parent
            }
            guard ownsEvent, !(window.childWindows ?? []).contains(where: \.isVisible) else { return false }
            if let input = event.window?.firstResponder as? NSTextInputClient, input.hasMarkedText() { return false }
            if event.window === window, window.firstResponder is NSTextView,
               event.keyCode == 123 || event.keyCode == 124 { return false }
            switch event.keyCode {
            case 125: controller?.move(1)
            case 126: controller?.move(-1)
            case 124: controller?.perform(onlySubmenu: true)
            case 123: close()
            case 36, 76: controller?.perform()
            case 49:
                guard !(window.firstResponder is NSTextView) else { return false }
                controller?.perform()
            default: return false
            }
            return true
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.controller = controller; view.close = close }
}

#if DEBUG
struct BusinessMenuRowFrame: Equatable { let id: UUID; let rect: CGRect; let highlighted: Bool }
struct BusinessMenuRowFrames: PreferenceKey {
    static var defaultValue: [BusinessMenuRowFrame] = []
    static func reduce(value: inout [BusinessMenuRowFrame], nextValue: () -> [BusinessMenuRowFrame]) { value += nextValue() }
}
struct BusinessMenuTriggerFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif
private extension View {
    @ViewBuilder func businessMenuTriggerProbe(_ title: String) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: BusinessMenuTriggerFrames.self,
                value: [title: geometry.frame(in: .named("business-menu"))])
        })
        #else
        self
        #endif
    }
    @ViewBuilder func businessMenuRowProbe(_ id: UUID, highlighted: Bool) -> some View {
        #if DEBUG
        background(GeometryReader { geometry in
            Color.clear.preference(key: BusinessMenuRowFrames.self,
                value: [.init(id: id, rect: geometry.frame(in: .named("business-menu")), highlighted: highlighted)])
        })
        #else
        self
        #endif
    }
}
