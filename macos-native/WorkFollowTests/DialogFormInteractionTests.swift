import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class DialogFormInteractionTests: XCTestCase {
    /// 这两条用例断言的是 Escape / Tab 在真实响应链上的行为，
    /// 需要 key window 与前台进程——显式声明，不随全局后台策略退化。
    private final class Frames { var values: [DialogActionAnchor: CGRect] = [:] }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecordValidationKeepsActionsFixedAndDoesNotPersistTheDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FocusStore(clock: { self.now }, directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var draft = FocusRecordDraft(now: now)
        draft.startedAt = now
        draft.endedAt = now.addingTimeInterval(-60)
        draft.note = "未保存的笔记"
        let frames = Frames()
        let host = dialog(FocusRecordEditor(store: store, workspace: nil, draft: draft), frames: frames)
        let window = InspectorPanelTestSupport.ownerWindow(for: host,
            width: FocusLayoutMetrics.recordEditorWidth, height: FocusLayoutMetrics.recordEditorHeight)
        defer { window.close() }
        let initial = frames.values
        XCTAssertTrue(CGRect(x: 0, y: 0, width: FocusLayoutMetrics.recordEditorWidth,
                             height: FocusLayoutMetrics.recordEditorHeight).contains(try XCTUnwrap(initial[.primary])))
        try click(.primary, frames: frames, host: host, window: window)
        XCTAssertNil(store.record(id: draft.id), "校验失败必须留在草稿，不产生记录")
        XCTAssertEqual(frames.values, initial, "错误出现后保存和取消按钮不移位")
        try click(.cancel, frames: frames, host: host, window: window)
        XCTAssertNil(store.record(id: draft.id))
    }

    func testRecordAndFilterSaveActionsCommitOnlyTheConfirmedDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let focus = FocusStore(clock: { self.now }, directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var draft = FocusRecordDraft(now: now)
        draft.note = "已确认的记录"
        let recordFrames = Frames()
        let recordHost = dialog(FocusRecordEditor(store: focus, workspace: nil, draft: draft), frames: recordFrames)
        let recordWindow = InspectorPanelTestSupport.ownerWindow(for: recordHost,
            width: FocusLayoutMetrics.recordEditorWidth, height: FocusLayoutMetrics.recordEditorHeight)
        defer { recordWindow.close() }
        try click(.primary, frames: recordFrames, host: recordHost, window: recordWindow)
        XCTAssertEqual(focus.record(id: draft.id)?.note, draft.note)

        let filters = FilterStore(directory: directory)
        let initial = SavedFilter(name: "已有过滤器", listNames: ["工作"])
        XCTAssertTrue(filters.add(initial))
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        var dismissals = 0
        let filterFrames = Frames()
        let filterHost = dialog(FilterEditorView(store: filters, workspace: workspace, initial: initial,
            onDismiss: { dismissals += 1 }), frames: filterFrames)
        let filterWindow = InspectorPanelTestSupport.ownerWindow(for: filterHost, width: 520, height: 600)
        defer { filterWindow.close() }
        try click(.cancel, frames: filterFrames, host: filterHost, window: filterWindow)
        XCTAssertEqual(filters.filter(withID: initial.id), initial)
        XCTAssertEqual(dismissals, 1)
        try click(.primary, frames: filterFrames, host: filterHost, window: filterWindow)
        XCTAssertEqual(dismissals, 2)
        XCTAssertEqual(filters.filters.count, 1)
        XCTAssertEqual(filters.filter(withID: initial.id)?.listNames, ["工作"])
    }

    func testNativeConfirmationUsesSafeDefaultAndEscapeWithoutChangingResponseOrder() throws {
        for key in ["\r", "\u{1b}"] { try checkConfirmationCancellation(key: key) }
    }

    private func checkConfirmationCancellation(key: String) throws {
        let alert = NSAlert()
        let remove = alert.addButton(withTitle: "删除清单")
        let cancel = alert.addButton(withTitle: "取消")
        NativeDialogActions.configure(alert, primary: remove, cancel: cancel, destructive: true)
        XCTAssertTrue(alert.buttons.first === remove)
        XCTAssertTrue(alert.window.defaultButtonCell === cancel.cell)
        XCTAssertEqual(remove.keyEquivalent, "")
        XCTAssertTrue(remove.hasDestructiveAction)
        // Test actual dispatch rather than relying on a key-equivalent string.
        let send = Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: alert.window.windowNumber, context: nil,
                    characters: key, charactersIgnoringModifiers: key, isARepeat: false,
                    keyCode: key == "\r" ? 36 : 53)!
                XCTAssertTrue(event.window === alert.window)
                NSApp.postEvent(event, atStart: true)
            }
        }
        let stop = Timer(timeInterval: 1, repeats: false) { _ in NSApp.abortModal() }
        RunLoop.main.add(send, forMode: .modalPanel)
        RunLoop.main.add(stop, forMode: .modalPanel)
        // 模态告警要真的收到 Escape，进程必须是 active（否则 key 事件进不到 alert 的响应链）。
        _ = NSApplication.shared
        NSApp.activate(ignoringOtherApps: true)
        let response = NativeDialogActions.runModal(alert, cancel: cancel)
        send.invalidate(); stop.invalidate()
        alert.window.orderOut(nil)
        XCTAssertEqual(response, .alertSecondButtonReturn, "按 \(key == "\r" ? "Return" : "Escape") 应取消")
    }

    func testEditedFormsFitTheirBoundsInBothAppearances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let focus = FocusStore(clock: { self.now }, directory: directory)
        let countdown = CountdownStore(directory: directory)
        let filters = FilterStore(directory: directory)
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(focus.addTimer(name: "阅读", emoji: "📚", stopwatch: false, minutes: 25))
        let preset = try XCTUnwrap(focus.timers.first)
        let items: [(String, AnyView, CGSize)] = [
            ("focus-record", AnyView(FocusRecordEditor(store: focus, workspace: workspace, draft: .init(now: now))),
             CGSize(width: FocusLayoutMetrics.recordEditorWidth, height: FocusLayoutMetrics.recordEditorHeight)),
            ("focus-preset", AnyView(FocusPresetEditor(store: focus, workspace: workspace, preset: preset)), CGSize(width: 400, height: 380)),
            ("filter", AnyView(FilterEditorView(store: filters, workspace: workspace, initial: nil, onDismiss: {})), CGSize(width: 520, height: 600)),
            ("countdown", AnyView(CountdownEditorView(store: countdown, original: nil)), CGSize(width: 460, height: 546))
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, content, size) in items {
                let frames = Frames()
                let host = dialog(content.environment(\.colorScheme, scheme), frames: frames)
                let window = InspectorPanelTestSupport.ownerWindow(for: host, width: size.width, height: size.height)
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                InspectorPanelTestSupport.settle(window)
                let bounds = CGRect(origin: .zero, size: size)
                for frame in frames.values.values { XCTAssertTrue(bounds.contains(frame), "\(name) 操作栏超出窗口") }
                XCTAssertNotNil(frames.values[.primary])
                XCTAssertGreaterThan(try XCTUnwrap(frames.values[.primary]).minY, size.height / 2)
                XCTAssertEqual(try XCTUnwrap(frames.values[.primary]).maxX, size.width - 24, accuracy: 1,
                               "\(name) 主动作始终右对齐，包括没有状态文字时")
                if let path = ProcessInfo.processInfo.environment["WORKFOLLOW_POPUP_RENDER_DIR"] {
                    let url = URL(fileURLWithPath: path, isDirectory: true)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: url.appendingPathComponent(name + (scheme == .light ? "-light.png" : "-dark.png")))
                }
                window.close()
            }
        }
    }

    private func dialog<V: View>(_ content: V, frames: Frames) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(content.coordinateSpace(name: "dialog-render")
            .onPreferenceChange(DialogActionFrames.self) { frames.values = $0 }))
    }
    private func click(_ anchor: DialogActionAnchor, frames: Frames, host: NSView, window: NSWindow) throws {
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames.values[anchor]), in: host, window: window)
    }
}
