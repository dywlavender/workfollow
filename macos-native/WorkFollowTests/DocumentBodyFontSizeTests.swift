import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 设置页的「正文字号」：只影响没有单独选字号档位的段落，打开中的编辑器即时重排。
@MainActor
final class DocumentBodyFontSizeTests: XCTestCase {
    private var savedBodyFontSize: Any?

    override func setUp() {
        super.setUp()
        savedBodyFontSize = EditorDefaultsSupport.takeBodyFontSize()
        UserDefaults.standard.set(16.0, forKey: EditorPreferences.bodyFontSizeKey)
    }

    override func tearDown() {
        EditorDefaultsSupport.restoreBodyFontSize(savedBodyFontSize)
        savedBodyFontSize = nil
        super.tearDown()
    }

    private func attributes(_ kind: DocumentBlockKind,
                            bodySize: DocumentBodySize? = nil) -> [NSAttributedString.Key: Any] {
        DocumentTextCodec.attributes(kind: kind, marks: [], bodySize: bodySize)
    }

    private func pointSize(_ kind: DocumentBlockKind,
                           bodySize: DocumentBodySize? = nil) throws -> CGFloat {
        let font = try XCTUnwrap(attributes(kind, bodySize: bodySize)[.font] as? NSFont)
        return font.pointSize
    }

    func testPlainBodyFollowsTheGlobalSize() throws {
        XCTAssertEqual(try pointSize(.paragraph), 16)
        let attrs = attributes(.paragraph)
        let font = try XCTUnwrap(attrs[.font] as? NSFont)
        let style = try XCTUnwrap(attrs[.paragraphStyle] as? NSParagraphStyle)
        let lineBox = font.ascender - font.descender + font.leading + style.lineSpacing
        XCTAssertEqual(lineBox, 24, accuracy: 0.01, "行盒跟随 1.5 倍字号")
    }

    func testExplicitBodySizesAndHeadingsAreNotOverridden() throws {
        XCTAssertEqual(try pointSize(.paragraph, bodySize: .small), 12)
        XCTAssertEqual(try pointSize(.paragraph, bodySize: .medium), 16)
        XCTAssertEqual(try pointSize(.paragraph, bodySize: .large), 18)
        XCTAssertEqual(try pointSize(.heading(1)), 18)
        XCTAssertEqual(try pointSize(.heading(2)), 16)
        XCTAssertEqual(try pointSize(.heading(3)), 14)
    }

    func testListsQuotesAndChecklistsKeepTheMeasuredScale() throws {
        for kind in [DocumentBlockKind.bullet, .ordered, .quote, .checklist(false)] {
            XCTAssertEqual(try pointSize(kind), DocumentEditorPresentationMetrics.bodyFontSize)
        }
    }

    func testStoredValueIsClampedToTheSettingRange() {
        UserDefaults.standard.set(40.0, forKey: EditorPreferences.bodyFontSizeKey)
        XCTAssertEqual(EditorPreferences.bodyFontSize, EditorPreferences.bodyFontSizeRange.upperBound)
        UserDefaults.standard.set(8.0, forKey: EditorPreferences.bodyFontSizeKey)
        XCTAssertEqual(EditorPreferences.bodyFontSize, EditorPreferences.bodyFontSizeRange.lowerBound)
    }

    func testOpenEditorReformatsOnlyDefaultParagraphs() throws {
        let id = UUID()
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "默认正文")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文档位")], bodySize: .medium)
        ])
        let host = NSHostingView(rootView: DocumentEditor(
            documentID: id, document: document,
            onDocumentChange: { _ in }, onEscape: { .endEditing }, onEditingChanged: { _ in }))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 520, height: 320)
        defer { window.close() }
        let editor = try XCTUnwrap(Self.editor(in: host))
        XCTAssertEqual(editor.font?.pointSize, 16)
        XCTAssertEqual(try storageSize(editor, at: 0), 16)
        XCTAssertEqual(try storageSize(editor, at: 5), 16, "正文 2 档位是 16")

        UserDefaults.standard.set(18.0, forKey: EditorPreferences.bodyFontSizeKey)
        try InspectorPanelTestSupport.waitUntil("打开中的编辑器没有跟随正文字号设置") {
            (try? self.storageSize(editor, at: 0)) == 18
        }
        XCTAssertEqual(editor.font?.pointSize, 18)
        XCTAssertEqual(try storageSize(editor, at: 5), 16, "显式档位保持 16")
    }

    private func storageSize(_ editor: NativeTextView, at index: Int) throws -> CGFloat {
        let font = try XCTUnwrap(editor.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
        return font.pointSize
    }

    private static func editor(in view: NSView) -> NativeTextView? {
        if let editor = view as? NativeTextView { return editor }
        return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
}
