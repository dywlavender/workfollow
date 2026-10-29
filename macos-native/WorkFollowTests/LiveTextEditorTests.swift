import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class LiveTextEditorTests: XCTestCase {
    private struct Harness: View {
        @State var text: String
        let onLiveEmpty: (Bool) -> Void
        let onChange: (String) -> Void
        var body: some View {
            LiveTextEditor(text: $text, onLiveTextIsEmptyChange: onLiveEmpty)
                .onChange(of: text) { _, value in onChange(value) }
        }
    }

    private func textView(in view: NSView, where predicate: (NSTextView) -> Bool) -> NSTextView? {
        if let textView = view as? NSTextView, predicate(textView) { return textView }
        for subview in view.subviews {
            if let found = textView(in: subview, where: predicate) { return found }
        }
        return nil
    }

    private func editableEditor(in view: NSView) -> NSTextView? {
        textView(in: view) { $0.isEditable && !$0.isFieldEditor }
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testBindingStaysEmptyDuringCompositionAndSyncsOnUnmark() throws {
        var texts: [String] = []
        var live: [Bool] = []
        let host = NSHostingView(rootView: Harness(text: "",
            onLiveEmpty: { live.append($0) },
            onChange: { texts.append($0) }))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 420, height: 220)
        defer { window.close() }
        try InspectorPanelTestSupport.waitUntil("初始空态应回传") { live.last == true }

        let editor = try XCTUnwrap(editableEditor(in: host))
        window.makeFirstResponder(editor)
        editor.setMarkedText("xing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(texts.contains { !$0.isEmpty }, "组合串不能进入模型")
        XCTAssertEqual(live.last, false, "组合串一出现就要报告非空")

        editor.unmarkText()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(texts.last, "xing", "上屏后组合串要落到模型")

        editor.selectAll(nil)
        editor.deleteBackward(nil)
        try InspectorPanelTestSupport.waitUntil("删空后空态应恢复") { live.last == true }
    }

    func testMeetingMinutesPlaceholderYieldsToLiveComposition() throws {
        let directory = temporaryDirectory("live-text-meeting")
        let store = MeetingStore(directory: directory, automaticallyUpdate: false)
        store.create()
        var placeholders: [String] = []
        let environment = AppEnvironment(directory: directory)
        let host = NSHostingView(rootView: MeetingWorkspaceView(store: store)
            .environmentObject(environment)
            .onPreferenceChange(LivePlaceholderTitles.self) { placeholders = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.close() }

        try InspectorPanelTestSupport.waitUntil("空纪要应先显示占位") {
            placeholders.contains("meeting.minutes.placeholder")
        }
        let editor = try XCTUnwrap(editableEditor(in: host))
        window.makeFirstResponder(editor)
        editor.setMarkedText("xing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(store.selected?.minutes, "", "组合阶段模型里还没有字")
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(placeholders.contains("meeting.minutes.placeholder"),
                       "拼音组合阶段会议纪要占位就该让位")

        editor.unmarkText()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(store.selected?.minutes, "xing")
        XCTAssertFalse(placeholders.contains("meeting.minutes.placeholder"))

        editor.selectAll(nil)
        editor.deleteBackward(nil)
        try InspectorPanelTestSupport.waitUntil("删空纪要后占位应恢复") {
            placeholders.contains("meeting.minutes.placeholder")
        }
    }

    func testFocusNotePlaceholderYieldsToLiveComposition() throws {
        let directory = temporaryDirectory("live-text-focus")
        let store = FocusStore(clock: { Date(timeIntervalSince1970: 1_800_000_000) },
                               directory: directory)
        XCTAssertTrue(store.start(minutes: 25))
        var placeholders: [String] = []
        let host = NSHostingView(rootView: FocusActiveSessionPane(store: store)
            .onPreferenceChange(LivePlaceholderTitles.self) { placeholders = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 520, height: 820)
        defer { window.close() }

        try InspectorPanelTestSupport.waitUntil("空专注笔记应先显示占位") {
            placeholders.contains("focus.note.placeholder")
        }
        let editor = try XCTUnwrap(editableEditor(in: host))
        window.makeFirstResponder(editor)
        editor.setMarkedText("xing", selectedRange: NSRange(location: 4, length: 0),
                             replacementRange: editor.selectedRange())
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(store.currentSessionNote, "", "组合阶段模型里还没有字")
        InspectorPanelTestSupport.settle(window)
        XCTAssertFalse(placeholders.contains("focus.note.placeholder"),
                       "拼音组合阶段专注笔记占位就该让位")

        editor.unmarkText()
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(store.currentSessionNote, "xing")
        XCTAssertFalse(placeholders.contains("focus.note.placeholder"))

        editor.selectAll(nil)
        editor.deleteBackward(nil)
        try InspectorPanelTestSupport.waitUntil("删空专注笔记后占位应恢复") {
            placeholders.contains("focus.note.placeholder")
        }
    }
}
