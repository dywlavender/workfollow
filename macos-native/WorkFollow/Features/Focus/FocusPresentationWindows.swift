import AppKit
import Combine
import SwiftUI

@MainActor
final class FocusWindowAppearance: ObservableObject {
    @Published private(set) var selection: NativeAppearance = .system
    var appKitName: NSAppearance.Name? {
        switch selection {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
    func update(_ selection: NativeAppearance) { self.selection = selection }
}

/// Mini 与沉浸只是同一 Store 的展示面，不持有第二个计时引擎。
@MainActor
final class FocusPresentationWindows: NSWindowController {
    private static var mini: FocusPresentationWindows?
    private static var immersive: FocusPresentationWindows?
    private static let appearance = FocusWindowAppearance()
    private static var appearanceSubscription: AnyCancellable?
    private let store: FocusStore

    static func attachAppearance(_ environment: AppEnvironment) {
        appearanceSubscription = environment.$appearance.sink { selection in
            appearance.update(selection)
            let native = appearance.appKitName.flatMap { NSAppearance(named: $0) }
            mini?.window?.appearance = native
            immersive?.window?.appearance = native
        }
    }

    static func showMini(store: FocusStore) { show(store: store, immersive: false) }
    static func showImmersive(store: FocusStore) { show(store: store, immersive: true) }
    private static func show(store: FocusStore, immersive isImmersive: Bool) {
        let existing = isImmersive ? immersive : mini
        let controller: FocusPresentationWindows
        if let existing, existing.store === store { controller = existing }
        else {
            existing?.close(); controller = FocusPresentationWindows(store: store, immersive: isImmersive)
            if isImmersive { immersive = controller } else { mini = controller }
        }
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
        if isImmersive, controller.window?.styleMask.contains(.fullScreen) != true {
            controller.window?.toggleFullScreen(nil)
        }
    }
    init(store: FocusStore, immersive: Bool) {
        self.store = store
        let window: NSWindow
        if immersive {
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 640),
                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.collectionBehavior = [.fullScreenPrimary]
        } else {
            window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 300, height: 260),
                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.level = .floating
            (window as? NSPanel)?.hidesOnDeactivate = false
        }
        window.title = immersive ? "沉浸专注" : "Mini 专注"
        window.isReleasedWhenClosed = false
        window.appearance = Self.appearance.appKitName.flatMap { NSAppearance(named: $0) }
        window.contentView = NSHostingView(rootView: FocusWindowRoot(store: store, immersive: immersive,
                                                                   appearance: Self.appearance))
        window.center(); super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
}

private struct FocusWindowRoot: View {
    @ObservedObject var store: FocusStore
    let immersive: Bool
    @ObservedObject var appearance: FocusWindowAppearance
    var body: some View {
        FocusCompactPresentation(store: store, immersive: immersive)
            .preferredColorScheme(appearance.selection.colorScheme)
            .hidesSystemFocusEffect()
    }
}

struct FocusCompactPresentation: View {
    @ObservedObject var store: FocusStore
    let immersive: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = store.presentation
        let theme = FocusTheme(scheme)
        VStack(spacing: immersive ? 26 : 16) {
            Text(p.mode.title).font(immersive ? .title2 : .headline).foregroundStyle(theme.text2)
            Text(FocusViewLogic.clockText(p.displaySeconds))
                .font(.system(size: immersive ? 110 : 44, weight: .light)).monospacedDigit()
                .accessibilityIdentifier("focus-compact-clock")
            Text(store.completionContext?.extraTimeStartedAt != nil ? "追加专注中" : p.phaseTitle)
                .font(.caption).foregroundStyle(theme.text2)
            HStack(spacing: 12) {
                ForEach(p.availableActions.filter { $0 != .abandon }, id: \.self) { action in
                    Button(action.title) { _ = store.perform(action) }
                        .accessibilityIdentifier("focus-compact-\(action.rawValue)")
                }
            }
            if p.availableActions.contains(.abandon) {
                Button("放弃专注") { _ = store.perform(.abandon) }.buttonStyle(.plain)
                    .font(.caption).foregroundStyle(theme.text3)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.canvas)
    }
}
