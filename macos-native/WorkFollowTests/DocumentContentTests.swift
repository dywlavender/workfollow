import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentContentTests: XCTestCase {
    /// 标题行末尾回车：新行延续标题级别（模型里的文末空段靠 pendingTrailingBlock）。
    func testEnterAfterHeadingContinuesHeadingAtDocumentEnd() throws {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题")])])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.typingAttributes = DocumentTextCodec.attributes(kind: .heading(2), marks: [])

        editor.insertNewline(nil)

        XCTAssertEqual(editor.pendingTrailingBlock, .heading(2), "回车后文末空段应待定为 H2")
        editor.insertText("正文")
        let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document,
                                               trailing: editor.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.count, 2)
        XCTAssertEqual(decoded.blocks.last?.kind, .heading(2), "换行后输入的内容应延续 H2")
    }

    /// 空标题行上回车：退回正文（连按两次回车退出标题，滴答/Quill 同款）。
    func testEnterOnEmptyHeadingExitsToParagraph() throws {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题")])])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.typingAttributes = DocumentTextCodec.attributes(kind: .heading(2), marks: [])
        editor.insertNewline(nil)

        XCTAssertTrue(editor.exitEmptyBlockOnNewline(), "空标题行回车应被退出逻辑处理")
        XCTAssertEqual(editor.pendingTrailingBlock, .paragraph)
        XCTAssertEqual(editor.typingAttributes[DocumentTextCodec.blockKey] as? String, "paragraph")
        let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document,
                                               trailing: editor.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.last?.kind, .paragraph, "空标题行回车后应退回普通段落")
    }

    /// 空列表项（有序/无序/检查项）上回车：同样退回正文。
    func testEnterOnEmptyListItemExitsToParagraph() {
        for kind in [DocumentBlockKind.bullet, .ordered, .checklist(false)] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            let document = NativeDocument(blocks: [DocumentBlock(kind: kind, runs: [DocumentRun(text: "事项")])])
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            editor.typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [])
            editor.insertNewline(nil)

            XCTAssertTrue(editor.exitEmptyBlockOnNewline(), "\(kind) 空项回车应被退出逻辑处理")
            let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document,
                                                   trailing: editor.pendingTrailingBlock)
            XCTAssertEqual(decoded.blocks.last?.kind, .paragraph, "\(kind) 空项回车后应退回普通段落")
        }
    }

    /// 文末空段上应用列表：格式必须落在文末空段（待定级别），不能跑到上一行。
    func testApplyingListOnTrailingEmptyLineDoesNotTouchLineAbove() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "上一行")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
        ])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 4, length: 0))

        editor.applyFormat(.init(title: "无序列表", block: .bullet, mark: nil), lineStart: 4)

        XCTAssertEqual(editor.pendingTrailingBlock, .bullet, "文末空段应待定为无序列表")
        let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document,
                                               trailing: editor.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.first?.kind, .paragraph, "上一行不应被改成列表")
        editor.insertText("条目")
        let after = DocumentTextCodec.decode(editor.attributedString(), preserving: decoded,
                                             trailing: editor.pendingTrailingBlock)
        XCTAssertEqual(after.blocks.last?.kind, .bullet, "随后输入的内容应成为列表项")
    }

    /// 文末空段的检查项点击翻转：无字符段落的状态走输入属性 + 待定级别，
    /// 光标要落到文末，级别才能随下一次 commit 进模型。
    func testTrailingChecklistTogglesFromEmptyLine() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "上文")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
        ])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.pendingTrailingBlock = .checklist(false)
        editor.displayedTrailingBlock = .checklist(false)

        editor.setTrailingChecklist(checked: true)

        XCTAssertEqual(editor.pendingTrailingBlock, .checklist(true))
        XCTAssertEqual(editor.typingAttributes[DocumentTextCodec.blockKey] as? String, "checked")
        XCTAssertEqual(editor.selectedRange().location, 3, "光标应落在文末空段")
        let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document,
                                               trailing: editor.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.last?.kind, .checklist(true), "文末空段应记录为已勾选检查项")
    }

    func testBlockPresentationDoesNotBecomeInlineFormatting() {
        for kind in [DocumentBlockKind.heading(1), .heading(3), .code] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            let original = NativeDocument(blocks: [DocumentBlock(kind: kind, runs: [DocumentRun(text: "正文")])])
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
            editor.setSelectedRange(NSRange(location: 0, length: 2))
            editor.applyFormat(.init(title: "正文", block: .paragraph, mark: nil))
            let converted = DocumentTextCodec.decode(editor.attributedString(), preserving: original)
            XCTAssertEqual(converted.blocks[0].kind, .paragraph)
            XCTAssertEqual(converted.blocks[0].runs[0].marks, [])
        }
        let explicit = NativeDocument(blocks: [DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "手动粗体", marks: [.bold])])])
        let decoded = DocumentTextCodec.decode(DocumentTextCodec.render(explicit), preserving: explicit)
        XCTAssertEqual(decoded.blocks[0].runs[0].marks, [.bold])
    }

    func testCaretFormatsComposeAndToggleWithoutChangingExistingText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        editor.applyFormat(.init(title: "粗体", block: nil, mark: .bold))
        editor.applyFormat(.init(title: "下划线", block: nil, mark: .underline))
        editor.insertText("甲", replacementRange: editor.selectedRange())
        editor.applyFormat(.init(title: "粗体", block: nil, mark: .bold))
        editor.insertText("乙", replacementRange: editor.selectedRange())
        let runs = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty).blocks[0].runs
        XCTAssertEqual(runs.map(\.text), ["甲", "乙"])
        XCTAssertEqual(runs[0].marks, [.bold, .underline])
        XCTAssertEqual(runs[1].marks, [.underline])
    }

    func testEditorFormattingAdditionsPersistAndUndo() throws {
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: nil)
        editor.insertText("验收", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.applyFormat(.init(title: "三级标题", block: .heading(3), mark: nil))
        editor.applyFormat(.init(title: "行内代码", block: nil, mark: .code))
        var document = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty)
        XCTAssertEqual(document.blocks[0].kind, .heading(3))
        XCTAssertTrue(document.blocks[0].runs[0].marks.contains(.code))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.breakUndoCoalescing()
        editor.undoManager?.removeAllActions()
        editor.undoManager?.beginUndoGrouping()
        editor.insertDocumentDivider()
        editor.undoManager?.endUndoGrouping()
        document = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertEqual(document.blocks[1].kind, .divider)
        XCTAssertEqual(document.blocks.last?.kind, .paragraph)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(DocumentTextCodec.decode(DocumentTextCodec.render(restored), preserving: restored).blocks[1].kind, .divider)
        editor.undo(nil)
        XCTAssertEqual(editor.string, "验收")
        editor.redo(nil)
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
        editor.insertDocumentTime(Date(timeIntervalSince1970: 0))
        XCTAssertTrue(editor.string.contains("1970年1月1日"))
        XCTAssertEqual(DocumentTextCodec.decode(editor.attributedString(), preserving: document).blocks.last?.kind, .paragraph)
    }

    func testLegacyRunWithoutAttachmentDecodes() throws {
        let data = Data("{\"text\":\"old text\",\"marks\":[]}".utf8)
        let run = try JSONDecoder().decode(DocumentRun.self, from: data)
        XCTAssertEqual(run.text, "old text")
        XCTAssertNil(run.attachment)
    }

    func testAttachmentSurvivesTextKitAndJSONRoundTrip() throws {
        let attachment = NativeAttachment(id: UUID(), name: "资料.pdf", storedName: "example.pdf")
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "正文 "), DocumentRun(text: "\u{FFFC}", attachment: attachment)
        ])])
        let rendered = DocumentTextCodec.render(document)
        XCTAssertNotNil(rendered.attribute(.attachment, at: 3, effectiveRange: nil))
        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks.first?.runs.last?.attachment, attachment)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored, decoded)
    }

    func testChecklistStatusRoundTrip() {
        for checked in [false, true] {
            let document = NativeDocument(blocks: [DocumentBlock(kind: .checklist(checked), runs: [DocumentRun(text: "item")])])
            let rendered = DocumentTextCodec.render(document)
            XCTAssertEqual(DocumentTextCodec.decode(rendered, preserving: document).blocks.first?.kind, .checklist(checked))
            let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            // 标记由视图层自绘：段落不挂 NSTextList，否则 TextKit 2（macOS 14+）
            // 会再画一份灰色标记并挤占行首空间。
            XCTAssertEqual(style?.textLists.isEmpty, true)
            XCTAssertEqual(style?.firstLineHeadIndent, 42)
        }
    }

    func testConsecutiveOrderedBlocksNumberContinuously() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第二项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第三项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "分组结束")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "新列表")])
        ])
        let rendered = DocumentTextCodec.render(document)
        let style = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textLists.isEmpty, true)
        // 序号口径：向前数连续 ordered 段，普通段落打断后重新从 1 计。
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 0, in: rendered), 1)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 4, in: rendered), 2)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 8, in: rendered), 3)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 17, in: rendered), 1)
    }

    func testLinkEditingPreservesTextAndOtherMarks() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "网站", marks: [.bold])])])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        editor.setDocumentLink("https://example.com", range: NSRange(location: 0, length: 2))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2))
        var updated = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertEqual(updated.plainText, "网站")
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.link("https://example.com")))
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.bold))
        editor.undo(nil)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2))
        XCTAssertNil(editor.attributedString().attribute(.link, at: 0, effectiveRange: nil))
        editor.redo(nil)
        XCTAssertEqual(editor.attributedString().attribute(.link, at: 0, effectiveRange: nil) as? String,
                       "https://example.com")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.removeDocumentLink(nil)
        updated = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertFalse(updated.blocks[0].runs[0].marks.contains(.link("https://example.com")))
        XCTAssertTrue(updated.blocks[0].runs[0].marks.contains(.bold))
    }

    func testAttachmentInsertionCanUndoAndDoesNotLeakToTyping() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.undoManager?.beginUndoGrouping()
        editor.insertAttachments([NativeAttachment(id: UUID(), name: "test.txt", storedName: "test.txt")])
        editor.undoManager?.endUndoGrouping()
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
        XCTAssertNil(editor.typingAttributes[.attachment])
        editor.undo(nil)
        XCTAssertEqual(editor.string, "")
        editor.redo(nil)
        XCTAssertTrue(editor.string.contains("\u{FFFC}"))
    }

    func testFormattingPreservesEmbeddedFileReference() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let file = NativeAttachment(id: UUID(), name: "test.txt", storedName: "test.txt")
        editor.insertAttachments([file])
        editor.setSelectedRange(NSRange(location: 0, length: 1))
        editor.applyFormat(DocumentFormatCommand(title: "高亮", block: nil, mark: .highlight))
        let result = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty)
        XCTAssertEqual(result.blocks[0].runs[0].attachment, file)
        XCTAssertTrue(result.blocks[0].runs[0].marks.contains(.highlight))
    }
}
