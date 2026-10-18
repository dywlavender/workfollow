import AppKit
import XCTest
@testable import WorkFollow

/// TI2-03 剩余项：粘贴文件 → 附件。
///
/// 滴答证据：`handleTextViewDidPasteFiles:files:range:`。剪贴板里是文件时不再按文本
/// 粘贴，而是交给宿主落盘成附件（与拖放共用同一套落盘规则）。
@MainActor
final class DocumentPasteFilesTests: XCTestCase {

    func testPastingFileURLsCallsHostInsteadOfInsertingText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("paste-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("报告.pdf")
        try Data("pdf".utf8).write(to: file)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([file as NSURL]))
        defer { pasteboard.clearContents() }

        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.isEditable = true
        var received: [URL] = []
        var profile = DocumentProfile()
        profile.onPasteFiles = { received = $0 }
        view.profile = profile
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        view.textStorage?.setAttributedString(NSAttributedString(string: "前文"))
        view.setSelectedRange(NSRange(location: ("前文" as NSString).length, length: 0))

        view.paste(nil)

        XCTAssertEqual(received.map(\.lastPathComponent), ["报告.pdf"])
        XCTAssertEqual(view.string, "前文", "粘贴文件不应把路径写进正文")
    }

    func testPastingPlainTextStillInsertsText() throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("纯文本", forType: .string)
        defer { pasteboard.clearContents() }

        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.isEditable = true
        var profile = DocumentProfile()
        var received: [URL] = []
        profile.onPasteFiles = { received = $0 }
        view.profile = profile
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 0))

        view.paste(nil)

        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(view.string, "纯文本")
    }
}
