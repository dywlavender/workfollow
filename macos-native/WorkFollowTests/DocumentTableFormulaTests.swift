import AppKit
import XCTest
@testable import WorkFollow

/// 表格与公式：正文附件渲染、插入/更新、Delta 往返。
@MainActor
final class DocumentTableFormulaTests: XCTestCase {

    func testTableInsertRendersGridAttachmentAndRoundTripsThroughDelta() throws {
        let original = NativeDocument(plainText: "前文\n\n后文")
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        var latest = original
        let coordinator = DocumentEditorCoordinator(documentID: editor.documentIdentity, document: original,
            onDocumentChange: { latest = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        defer { withExtendedLifetime(coordinator) {} }

        let table = NativeTable(rows: [["项目", "状态"], ["设计", "完成"], ["开发", "进行中"]])
        XCTAssertTrue(editor.saveTable(table, replacing: NSRange(location: 3, length: 0), existingID: nil))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.table), [table],
                       "表格应作为独立块插入正文")

        let range = (editor.string as NSString).range(of: "\u{FFFC}")
        XCTAssertNotEqual(range.location, NSNotFound)
        let index = range.location
        XCTAssertTrue(editor.textStorage?.attribute(.attachment, at: index, effectiveRange: nil)
            is NSTextAttachment)
        XCTAssertTrue((editor.textStorage?.attribute(.attachment, at: index, effectiveRange: nil)
            as? NSTextAttachment)?.attachmentCell is DocumentTableCell)

        let ops = QuillDeltaCodec.delta(from: latest)
        XCTAssertEqual(QuillDeltaCodec.document(from: ops).blocks.flatMap(\.runs).compactMap(\.table), [table],
                       "表格要写进 Delta embed 并读回")

        var edited = table
        edited.setText("已上线", row: 2, column: 1)
        XCTAssertTrue(editor.saveTable(edited, replacing: NSRange(location: 0, length: 0), existingID: table.id))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.table), [edited],
                       "再次保存应更新同一个表格而不是追加")
    }

    func testFormulaInsertRendersImageAttachmentAndRoundTripsThroughDelta() throws {
        let original = NativeDocument(plainText: "面积 S = ")
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300), textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        var latest = original
        let coordinator = DocumentEditorCoordinator(documentID: editor.documentIdentity, document: original,
            onDocumentChange: { latest = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        defer { withExtendedLifetime(coordinator) {} }

        let formula = NativeFormula(latex: #"\frac{a}{b} + \sqrt{x^2}"#)
        let insertion = NSRange(location: (editor.string as NSString).length, length: 0)
        XCTAssertTrue(editor.saveFormula(formula, replacing: insertion, existingID: nil))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.formula), [formula])

        let index = (editor.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(index, NSNotFound)
        let cell = (editor.textStorage?.attribute(.attachment, at: index, effectiveRange: nil)
            as? NSTextAttachment)?.attachmentCell
        XCTAssertTrue(cell is DocumentFormulaCell)
        XCTAssertGreaterThan(cell?.cellSize().height ?? 0, 18)

        let ops = QuillDeltaCodec.delta(from: latest)
        XCTAssertEqual(QuillDeltaCodec.document(from: ops).blocks.flatMap(\.runs).compactMap(\.formula),
                       [formula], "公式 latex 要写进 Delta embed 并读回")

        var edited = formula
        edited.latex = "E = mc^2"
        XCTAssertTrue(editor.saveFormula(edited, replacing: NSRange(location: 0, length: 0), existingID: formula.id))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.formula), [edited],
                       "再次保存应更新同一个公式而不是追加")
    }

    func testFormulaTypesetterMeasuresFractionsScriptsAndRadicals() throws {
        let plain = FormulaTypesetter.measuredSize("x")
        let complex = FormulaTypesetter.measuredSize(#"\frac{a+b}{c} + \sqrt{x^2 + y_1}"#)
        XCTAssertGreaterThan(complex.width, plain.width * 2)
        XCTAssertGreaterThan(complex.height, plain.height)
        XCTAssertNotNil(FormulaTypesetter.image(for: #"\sum_{i=1}^{n} \alpha_i"#))
        XCTAssertNotNil(FormulaTypesetter.image(for: "E = mc^2"))
    }

    func testTableNormalizationKeepsRowsRectangular() {
        let table = NativeTable(rows: [["a", "b", "c"], ["d"]])
        XCTAssertEqual(table.rowCount, 2)
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows[1], ["d", "", ""])
        var mutable = table
        mutable.addColumn()
        XCTAssertEqual(mutable.columnCount, 4)
        mutable.removeLastRow()
        XCTAssertEqual(mutable.rowCount, 1)
        mutable.removeLastColumn()
        XCTAssertEqual(mutable.columnCount, 3)
    }

    func testTableAttachmentFitsNarrowInspector() {
        let cell = DocumentTableCell(table: .empty())
        let container = NSTextContainer(containerSize: NSSize(width: 288, height: 1000))
        let frame = cell.cellFrame(for: container,
                                   proposedLineFragment: NSRect(x: 20, y: 0, width: 268, height: 20),
                                   glyphPosition: .zero, characterIndex: 0)
        XCTAssertLessThanOrEqual(frame.width, 268)
        XCTAssertGreaterThanOrEqual(frame.height, 90)
    }
}
