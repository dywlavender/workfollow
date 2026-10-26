import AppKit
import XCTest
@testable import WorkFollow

/// P2：提醒等“仅元数据”变化不能重建正文，光标与选区必须原地保留。
@MainActor
final class ChecklistMetadataRerenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let reminder = Date(timeIntervalSince1970: 1_800_003_600)
    private let documentID = UUID()

    func testSameContentIgnoresChecklistMetadata() {
        let original = baseDocument()
        var withReminder = original
        withReminder.blocks[0].checklist = ChecklistItemMeta(reminderAt: reminder)

        XCTAssertTrue(DocumentEditorCoordinator.sameContent(original, withReminder))

        var edited = withReminder
        edited.blocks[0].runs[0].text = "改过"
        XCTAssertFalse(DocumentEditorCoordinator.sameContent(original, edited))
    }

    func testMetadataOnlyUpdateKeepsTextStorageAndSelection() throws {
        let original = baseDocument()
        let view = try makeView(document: original)
        let revision = view.storageRevision
        let selection = NSRange(location: 2, length: 1)
        view.setSelectedRange(selection)

        let coordinator = DocumentEditorCoordinator(documentID: documentID, document: original,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        var withReminder = original
        withReminder.blocks[0].checklist = ChecklistItemMeta(reminderAt: reminder)
        coordinator.update(view, documentID: documentID, document: withReminder,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })

        XCTAssertEqual(view.storageRevision, revision, "仅元数据变化不应改写 text storage")
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(view.string, original.plainText)
    }

    func testContentUpdateStillRebuildsTheProjection() throws {
        let original = baseDocument()
        let view = try makeView(document: original)
        let revision = view.storageRevision
        let coordinator = DocumentEditorCoordinator(documentID: documentID, document: original,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        var appended = original
        appended.blocks.append(DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "丙")]))
        coordinator.update(view, documentID: documentID, document: appended,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })

        XCTAssertEqual(view.string, appended.plainText)
        XCTAssertEqual(view.string.filter { $0 == "\n" }.count, 2)
        XCTAssertGreaterThan(view.storageRevision, revision)
    }

    // MARK: - Helpers

    private func baseDocument() -> NativeDocument {
        NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "乙")])
        ])
    }

    private func makeView(document: NativeDocument) throws -> NativeTextView {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFront(nil)
        addTeardownBlock { window.close() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        window.makeFirstResponder(view)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return view
    }
}
