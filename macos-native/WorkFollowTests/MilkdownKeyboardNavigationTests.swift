import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class MilkdownKeyboardNavigationTests: XCTestCase {
    @MainActor private final class Model: ObservableObject {
        @Published var document = NativeDocument(plainText: "第一行1234567890\n第二行1234567890\n第三行1234567890")
        let id = UUID()
        let handle = DocumentEditorHandle()
    }
    private struct Host: View {
        @ObservedObject var model: Model
        var growing: Bool
        var body: some View {
            ScrollView {
                DocumentEditor(documentID: model.id, document: model.document,
                    onDocumentChange: { model.document = $0 }, onEscape: { .keepInspector },
                    onEditingChanged: { _ in }, contentSized: growing, handle: model.handle)
                    .frame(width: 700, height: growing ? nil : 460)
            }
            .frame(width: 720, height: 400)
        }
    }

    private func fixture(growing: Bool, document: NativeDocument? = nil) async throws -> (Model, MilkdownWebView, NSWindow) {
        let model = Model()
        if let document { model.document = document }
        let host = NSHostingView(rootView: Host(model: model, growing: growing))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 400)
        addTeardownBlock { @MainActor in window.contentView = nil; window.close() }
        let view = try await MilkdownTestSupport.editorAsync(in: host)
        try MilkdownTestSupport.command(view, "focus")
        try MilkdownTestSupport.select(view, NSRange(location: 4, length: 0))
        try recordKeys(view)
        return (model, view, window)
    }

    private func recordKeys(_ view: MilkdownWebView) throws {
        try MilkdownTestSupport.script(view, "window.navigationKeys=[]; document.addEventListener('keydown', e => navigationKeys.push({key:e.key,prevented:e.defaultPrevented}));")
    }

    private func arrow(_ down: Bool, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws {
        let character = down ? "\u{f701}" : "\u{f700}"
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero,
                modifierFlags: modifiers.union([.function, .numericPad]), timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: character,
                charactersIgnoringModifiers: character, isARepeat: false, keyCode: down ? 125 : 126))
            NSApp.sendEvent(event)
        }
    }

    private func waitForMovement(_ view: MilkdownWebView, from old: NSRange) async throws -> NSRange {
        for _ in 0..<50 {
            let range = try MilkdownTestSupport.range(view)
            if range != old { return range }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        let keys = try MilkdownTestSupport.script(view, "JSON.stringify(navigationKeys)")
        XCTFail("方向键未移动正文光标；收到按键：\(String(describing: keys))；焦点：\(MilkdownTestSupport.isFocused(view))")
        return try MilkdownTestSupport.range(view)
    }

    private func checkParagraphMovement(growing: Bool) async throws {
        let (model, view, window) = try await fixture(growing: growing)
        let original = model.document
        let start = try MilkdownTestSupport.range(view)
        try arrow(true, in: window)
        let down = try await waitForMovement(view, from: start)
        XCTAssertEqual(down.location, start.location + 14, "跨段落应保持文字列位置")
        XCTAssertEqual(down.length, 0)
        try arrow(false, in: window)
        let up = try await waitForMovement(view, from: down)
        XCTAssertEqual(up, start)
        try arrow(true, in: window, modifiers: .shift)
        let extended = try await waitForMovement(view, from: start)
        XCTAssertEqual(extended.location, start.location)
        XCTAssertGreaterThan(extended.length, 0)
        await view.flush()
        XCTAssertEqual(model.document, original)
    }

    func testNativeArrowKeysMoveAcrossParagraphsInFixedBody() async throws {
        try await checkParagraphMovement(growing: false)
    }

    func testNativeArrowKeysMoveAcrossParagraphsInGrowingBody() async throws {
        try await checkParagraphMovement(growing: true)
    }

    func testNativeArrowKeysMoveBetweenWrappedLinesWithinOneParagraph() async throws {
        let document = NativeDocument(plainText: String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789 ", count: 8))
        let (model, view, window) = try await fixture(growing: true, document: document)
        let start = try MilkdownTestSupport.range(view)
        try arrow(true, in: window)
        let down = try await waitForMovement(view, from: start)
        XCTAssertGreaterThan(down.location, start.location)
        XCTAssertLessThan(down.location, document.plainText.utf16.count)
        XCTAssertEqual(model.document.blocks.count, 1)
        try arrow(false, in: window)
        let up = try await waitForMovement(view, from: down)
        XCTAssertEqual(up, start)
        await view.flush()
        XCTAssertEqual(model.document, document)
    }

    func testNativeArrowKeysRemainInTaskAndNoteBodiesInTheFullWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("milkdown-keys-\(UUID())")
        let environment = AppEnvironment(directory: directory)
        let document = Model().document
        let taskID = try XCTUnwrap(environment.taskWorkspace.createTask(title: "方向键任务", in: .inbox).taskID)
        _ = environment.taskWorkspace.setDocument(taskID, document)
        let noteID = environment.notesWorkspace.create()
        environment.notesWorkspace.edit(noteID) { $0.title = "方向键笔记"; $0.document = document }
        environment.navigation.destination = .inbox
        environment.taskWorkspace.select(taskID)
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace,
            navigation: environment.navigation).environmentObject(environment))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 820)
        defer { window.contentView = nil; window.close(); try? FileManager.default.removeItem(at: directory) }
        for (destination, id) in [(NativeDestination.inbox, taskID), (.notes, noteID)] {
            environment.navigation.destination = destination
            if destination == .notes { environment.notesWorkspace.selectedID = noteID }
            let view = try await MilkdownTestSupport.editorAsync(in: host, id: id)
            try MilkdownTestSupport.command(view, "focus")
            try MilkdownTestSupport.select(view, NSRange(location: 4, length: 0))
            try recordKeys(view)
            let start = try MilkdownTestSupport.range(view)
            let selectedTaskBeforeArrow = environment.taskWorkspace.selectedTaskID
            try arrow(true, in: window)
            let down = try await waitForMovement(view, from: start)
            XCTAssertEqual(down.location, 18)
            try arrow(false, in: window)
            let up = try await waitForMovement(view, from: down)
            XCTAssertEqual(up, start)
            XCTAssertEqual(view.documentIdentity, id)
            XCTAssertEqual(view.document, document)
            XCTAssertEqual(environment.taskWorkspace.selectedTaskID, selectedTaskBeforeArrow,
                "正文方向键不能切换任务列表的选择")
        }
    }
}
