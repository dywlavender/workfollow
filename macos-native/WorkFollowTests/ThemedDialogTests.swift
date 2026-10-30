import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
private final class DialogProbeModel: ObservableObject {
    @Published var presented = false
    @Published var ran = false
}

private struct DialogProbe: View {
    @ObservedObject var model: DialogProbeModel

    var body: some View {
        Color.clear.frame(width: 10, height: 10)
            .workfollowAlert("确认操作？", isPresented: Binding(
                get: { model.presented },
                set: { model.presented = $0 }
            ), actions: [
                .cancel(),
                .primary("继续") { model.ran = true }
            ])
    }
}

@MainActor
final class ThemedDialogTests: XCTestCase {
    func testKeyboardDefaultsKeepDestructiveActionsOffReturn() throws {
        _ = NSApplication.shared
        XCTAssertEqual(runModal(posting: 53, actions: [.cancel(), .primary("继续")]), 0)
        XCTAssertEqual(runModal(posting: 36, actions: [.cancel(), .primary("继续")]), 1)
        XCTAssertEqual(runModal(posting: 36, actions: [.cancel(), .destructive("删除")]), 0)
    }

    func testPromptReturnsTextTypedIntoThemedField() throws {
        _ = NSApplication.shared
        var typed: String?
        let timer = Timer(timeInterval: 0.4, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let window = NSApp.modalWindow,
                      let editor = window.firstResponder as? NSTextView else {
                    NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 1))
                    return
                }
                editor.selectAll(nil)
                editor.insertText("设计评审", replacementRange: editor.selectedRange())
                typed = editor.string
                NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 1))
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let value = WorkfollowDialog.prompt("移动到新清单", placeholder: "清单名称",
                                            value: "旧名称", confirm: "移动")
        XCTAssertEqual(typed, "设计评审")
        XCTAssertEqual(value, "设计评审")
    }

    func testSwiftUIAlertModifierPresentsThemedDialogAndRunsAction() throws {
        _ = NSApplication.shared
        let model = DialogProbeModel()
        var anchors: [String: NSView] = [:]
        let window = InspectorPanelTestSupport.ownerWindow(
            for: NSHostingView(rootView: DialogProbe(model: model)
                .environment(\.workflowActionObservation, { anchors[$0] = $1 })),
            width: 200, height: 200)
        defer {
            window.contentView = nil
            window.close()
        }

        DispatchQueue.main.async { model.presented = true }
        try InspectorPanelTestSupport.waitUntil(timeout: 3) {
            (window.childWindows ?? []).contains { $0.title == "确认操作？" && $0.isVisible }
        }
        let dialog = try XCTUnwrap((window.childWindows ?? [])
            .first { $0.title == "确认操作？" && $0.isVisible })
        InspectorPanelTestSupport.settle(dialog)
        try InspectorPanelTestSupport.waitUntil(timeout: 2) {
            guard let anchor = anchors["dialog.button.继续"] else { return false }
            return anchor.window === dialog && !anchor.bounds.isEmpty
        }
        let confirm = try XCTUnwrap(anchors["dialog.button.继续"])
        try InspectorPanelTestSupport.click(confirm.bounds, in: confirm, window: dialog)
        try InspectorPanelTestSupport.waitUntil(timeout: 2) { model.ran && !model.presented }
        XCTAssertTrue(model.ran)
        XCTAssertFalse(model.presented)
        InspectorPanelTestSupport.settle(window)
    }

    private func runModal(posting keyCode: UInt16,
                          actions: [WorkfollowDialogAction]) -> Int {
        let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard let window = NSApp.modalWindow else { return }
                guard let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: keyCode == 36 ? "\r" : "\u{1b}",
                    charactersIgnoringModifiers: keyCode == 36 ? "\r" : "\u{1b}",
                    isARepeat: false, keyCode: keyCode) else { return }
                NSApp.postEvent(event, atStart: false)
            }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        return WorkfollowDialog.runModal(title: "键盘确认", actions: actions)
    }
}
