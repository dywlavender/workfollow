import AppKit
import XCTest
@testable import WorkFollow

/// 基础格式批（撤销/重做、清除格式、文字与高亮颜色、对齐、缩进、格式刷）。
///
/// 守三件事：颜色/对齐/缩进在 **Delta 与富文本两个投影**里都能往返；段级命令
/// 只动选中的段落并留下可撤销的一步；格式刷取的是"当时那一份样式"，落一次
/// 就自动退出，不会持续劫持后面的选区。
final class DocumentRichFormatTests: XCTestCase {
    @MainActor
    private func makeView(_ document: NativeDocument) -> NativeTextView {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.isEditable = true
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.undoManager?.removeAllActions()
        return view
    }

    // MARK: - 模型 ↔ Delta ↔ 渲染

    func testQuillRoundTripKeepsColorsAlignmentAndIndent() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "红字", marks: [.bold, .textColor("#ff3b30")])
            ]),
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "彩底", marks: [.highlightColor("#ffe58a")])
            ]),
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "旧高亮", marks: [.highlight])
            ]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "缩进居中")],
                          indentLevel: 2, align: .center)
        ])
        let ops = QuillDeltaCodec.delta(from: document)
        XCTAssertEqual(QuillDeltaCodec.document(from: ops), document)

        XCTAssertEqual(ops[0].attributes?["color"]?.stringValue, "#ff3b30")
        XCTAssertEqual(ops[2].attributes?["background"]?.stringValue, "#ffe58a")
        let bulletLine = try XCTUnwrap(ops.last)
        XCTAssertEqual(bulletLine.attributes?["indent"]?.intValue, 2)
        XCTAssertEqual(bulletLine.attributes?["align"]?.stringValue, "center")
        // 默认高亮仍落固定黄色，旧档与新色板互认。
        XCTAssertEqual(ops[4].attributes?["background"]?.stringValue, QuillDeltaCodec.highlightBackground)
    }

    func testQuillNormalizesHexAndToleratesUnknownColors() {
        XCTAssertEqual(QuillDeltaCodec.normalizedColor("#FF3B30"), "#ff3b30")
        XCTAssertEqual(QuillDeltaCodec.normalizedColor("00a95c"), "#00a95c")
        XCTAssertNil(QuillDeltaCodec.normalizedColor("rgb(255,0,0)"))
        XCTAssertNil(QuillDeltaCodec.normalizedColor("#ff3b3"))

        let ops = [
            QuillDeltaOp(insert: .string("未知"),
                         attributes: ["background": .string("rgb(255,0,0)"),
                                      "color": .string("chartreuse")]),
            QuillDeltaOp(insert: .string("\n"), attributes: nil)
        ]
        let decoded = QuillDeltaCodec.document(from: ops)
        // 认不出的背景按默认高亮处理，认不出的文字色不落标记。
        XCTAssertEqual(decoded.blocks.first?.runs.first?.marks, [.highlight])
    }

    func testColorPaletteKeepsAllSixtySwatchesWithDistinctIdentity() {
        XCTAssertEqual(DocumentColorPalette.rows.count, 6)
        XCTAssertTrue(DocumentColorPalette.rows.allSatisfy { $0.count == 10 })
        XCTAssertEqual(DocumentColorPalette.swatches.count, 60)
        XCTAssertEqual(Set(DocumentColorPalette.swatches.map(\.id)).count, 60,
                       "同色不同格的 id 必须唯一，否则网格会吞掉重复颜色")
        // 第五行是独立的中间色阶：与首行高亮色、末行深色都不重复。
        let middle = DocumentColorPalette.rows[4]
        XCTAssertEqual(Set(middle).count, 10)
        for column in 0..<10 {
            XCTAssertNotEqual(middle[column], DocumentColorPalette.rows[0][column])
            XCTAssertNotEqual(middle[column], DocumentColorPalette.rows[5][column])
        }
        XCTAssertEqual(DocumentColorPalette.swatches.last?.hex, DocumentColorPalette.rows[5].last)
    }

    @MainActor
    func testRenderingProjectsColorAlignmentAndIndent() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .bullet, runs: [
                DocumentRun(text: "彩色", marks: [.textColor("#0b7bff"), .highlightColor("#ffe58a")])
            ], indentLevel: 2, align: .center)
        ])
        let rendered = DocumentTextCodec.render(document)
        let attributes = rendered.attributes(at: 0, effectiveRange: nil)

        let foreground = try XCTUnwrap(attributes[.foregroundColor] as? NSColor)
        XCTAssertEqual(foreground.usingColorSpace(.sRGB),
                       try XCTUnwrap(NSColor(documentHex: "#0b7bff")).usingColorSpace(.sRGB))
        let background = try XCTUnwrap(attributes[.backgroundColor] as? NSColor)
        XCTAssertEqual(background.usingColorSpace(.sRGB),
                       try XCTUnwrap(NSColor(documentHex: "#ffe58a")).usingColorSpace(.sRGB))
        XCTAssertEqual(attributes[DocumentTextCodec.textColorKey] as? String, "#0b7bff")
        XCTAssertEqual(attributes[DocumentTextCodec.highlightColorKey] as? String, "#ffe58a")

        let style = try XCTUnwrap(attributes[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(style.alignment, .center)
        XCTAssertEqual(style.headIndent - DocumentEditorGeometry.decorationLane,
                       DocumentEditorGeometry.listTextIndent
                           + 2 * DocumentEditorGeometry.listIndentStep)

        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.blocks.first?.align, .center)
        XCTAssertEqual(decoded.blocks.first?.indentLevel, 2)
        let marks = try XCTUnwrap(decoded.blocks.first?.runs.first?.marks)
        XCTAssertTrue(marks.contains(.textColor("#0b7bff")))
        XCTAssertTrue(marks.contains(.highlightColor("#ffe58a")))
        XCTAssertFalse(marks.contains(.highlight))
    }

    // MARK: - 对齐 / 缩进

    @MainActor
    func testAlignmentAndIndentCommandsOnlyTouchSelectedParagraphs() throws {
        let document = NativeDocument(plainText: "甲\n乙\n丙")
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 2, length: 1))
        view.breakUndoCoalescing()
        view.applyAlignment(.right)

        func decode() -> NativeDocument {
            DocumentTextCodec.decode(view.attributedString(), preserving: document)
        }
        XCTAssertEqual(decode().blocks.map(\.align), [nil, .right, nil])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 1))
        XCTAssertTrue(view.canUndoDocumentEdit)

        view.undo(nil)
        XCTAssertEqual(decode().blocks.map(\.align), [nil, nil, nil])
        XCTAssertTrue(view.canRedoDocumentEdit)
        view.redo(nil)
        XCTAssertEqual(decode().blocks.map(\.align), [nil, .right, nil])

        view.setSelectedRange(NSRange(location: 2, length: 1))
        view.breakUndoCoalescing()
        view.adjustIndent(by: 3)
        XCTAssertEqual(decode().blocks.map(\.indentLevel), [0, 3, 0])
        XCTAssertEqual(decode().blocks[1].align, .right, "缩进不应碰对齐")
        view.adjustIndent(by: -9)
        XCTAssertEqual(decode().blocks.map(\.indentLevel), [0, 0, 0], "缩进夹在 0…8")
        XCTAssertEqual(view.string, "甲\n乙\n丙")
    }

    @MainActor
    func testTrailingEmptyParagraphKeepsAlignmentAndIndent() throws {
        let document = NativeDocument(plainText: "正文\n")
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        view.breakUndoCoalescing()
        view.applyAlignment(.center)

        XCTAssertEqual(view.pendingTrailingBlock, .paragraph)
        XCTAssertEqual(view.trailingAlign, .center)
        // 真实点按之间隔着一轮事件循环，撤销组按事件收口；测试里显式放行，
        // 否则对齐与缩进会落进同一个撤销步。
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        view.adjustIndent(by: 1)
        XCTAssertEqual(view.trailingIndentLevel, 1)

        let saved = DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                             trailing: view.pendingTrailingBlock,
                                             trailingIndentLevel: view.trailingIndentLevel,
                                             trailingListStart: view.trailingListStart,
                                             trailingAlign: view.trailingAlign)
        XCTAssertEqual(saved.blocks.last?.align, .center)
        XCTAssertEqual(saved.blocks.last?.indentLevel, 1)

        view.undo(nil)
        XCTAssertEqual(view.trailingIndentLevel, 0)
        XCTAssertEqual(view.trailingAlign, .center)
        view.undo(nil)
        XCTAssertNil(view.trailingAlign)
        XCTAssertEqual(view.string, "正文\n")
    }

    // MARK: - 清除格式

    @MainActor
    func testClearFormattingResetsParagraphAndInlineStyles() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [
                DocumentRun(text: "标题", marks: [.bold, .italic, .textColor("#ff3b30")])
            ], indentLevel: 1, align: .right),
            DocumentBlock(kind: .quote, runs: [
                DocumentRun(text: "引用", marks: [.link("https://example.com"), .highlightColor("#ffe58a")])
            ])
        ])
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length))
        view.breakUndoCoalescing()
        view.clearFormatting()

        func decode() -> NativeDocument {
            DocumentTextCodec.decode(view.attributedString(), preserving: document)
        }
        let cleared = decode()
        XCTAssertEqual(cleared.blocks.prefix(2).map(\.kind), [.paragraph, .paragraph])
        XCTAssertEqual(cleared.blocks.prefix(2).map(\.indentLevel), [0, 0])
        XCTAssertEqual(cleared.blocks.prefix(2).map(\.align), [nil, nil])
        XCTAssertTrue(cleared.blocks.prefix(2).flatMap(\.runs).allSatisfy(\.marks.isEmpty))
        XCTAssertEqual(view.string, "标题\n引用")

        XCTAssertTrue(view.canUndoDocumentEdit)
        view.undo(nil)
        let restored = decode()
        XCTAssertEqual(restored.blocks.first?.kind, .heading(2))
        XCTAssertEqual(restored.blocks.first?.align, .right)
        XCTAssertTrue(restored.blocks.first?.runs.first?.marks.contains(.textColor("#ff3b30")) == true)
    }

    // MARK: - 文字颜色 / 高亮

    @MainActor
    func testColorCommandsApplyToSelectionAndCaretTyping() throws {
        let document = NativeDocument(plainText: "颜色")
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 0, length: 2))
        view.breakUndoCoalescing()
        view.applyTextColor("#ff3b30")
        view.applyHighlightColor("#ffe58a")

        func decode() -> NativeDocument {
            DocumentTextCodec.decode(view.attributedString(), preserving: document)
        }
        var marks = try XCTUnwrap(decode().blocks.first?.runs.first?.marks)
        XCTAssertTrue(marks.contains(.textColor("#ff3b30")))
        XCTAssertTrue(marks.contains(.highlightColor("#ffe58a")))
        XCTAssertEqual(marks.textColorHex, "#ff3b30")
        XCTAssertEqual(marks.highlightHex, "#ffe58a")

        view.applyTextColor(nil)
        view.applyHighlightColor(nil)
        marks = try XCTUnwrap(decode().blocks.first?.runs.first?.marks)
        XCTAssertNil(marks.textColorHex)
        XCTAssertFalse(marks.hasAnyHighlight)

        // 无选区：只改输入属性，接着敲的字带颜色。
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        view.applyTextColor("#00a95c")
        XCTAssertEqual(view.typingAttributes[DocumentTextCodec.textColorKey] as? String, "#00a95c")
        view.insertText("新", replacementRange: view.selectedRange())
        let typed = try XCTUnwrap(decode().blocks.first?.runs.last?.marks)
        XCTAssertTrue(typed.contains(.textColor("#00a95c")))
    }

    @MainActor
    func testImageFileBecomesInlineImageAttachment() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 12, height: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-image-\(UUID().uuidString).png")
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let attachment = try XCTUnwrap(NativeTextView.imageAttachment(from: url))
        XCTAssertTrue(attachment.storedName.hasPrefix("data:image/png;base64,"))
        XCTAssertNotNil(DocumentTextCodec.pastedImage(from: attachment))

        let document = NativeDocument(plainText: "前")
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertAttachments([attachment])

        let decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        XCTAssertTrue(decoded.blocks.flatMap(\.runs).contains { $0.attachment?.id == attachment.id })

        let rendered = view.attributedString()
        let marker = (rendered.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(marker, NSNotFound)
        let renderedAttachment = try XCTUnwrap(
            rendered.attribute(.attachment, at: marker, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertNotNil(renderedAttachment.image, "图片附件应内联渲染，而不是 📎 文本")
    }

    @MainActor
    func testHighlightToggleFallsBackToDefaultPaletteColor() throws {
        let document = NativeDocument(plainText: "高亮")
        let view = makeView(document)
        let handle = DocumentEditorHandle()
        handle.textView = view
        view.setSelectedRange(NSRange(location: 0, length: 2))
        handle.toggleHighlight()

        var decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        XCTAssertEqual(decoded.blocks.first?.runs.first?.marks.highlightHex,
                       DocumentColorPalette.defaultHighlight)
        handle.refreshStyle()
        XCTAssertTrue(handle.style.marks.hasAnyHighlight)

        handle.toggleHighlight()
        decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        XCTAssertFalse(decoded.blocks.first?.runs.first?.marks.hasAnyHighlight ?? true)
    }

    // MARK: - 格式刷

    @MainActor
    func testFormatPainterAppliesCapturedStyleToNextSelection() throws {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "源", marks: [.bold, .textColor("#ff3b30")])
            ]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "目标")])
        ])
        let view = makeView(document)
        let handle = DocumentEditorHandle()
        handle.textView = view

        view.setSelectedRange(NSRange(location: 0, length: 1))
        handle.refreshStyle()
        XCTAssertEqual(handle.style.marks.textColorHex, "#ff3b30")
        handle.toggleFormatPainter()
        XCTAssertTrue(handle.formatPainterActive)

        view.setSelectedRange(NSRange(location: 2, length: 2))
        handle.selectionDidChange()

        let settled = expectation(description: "格式刷在选区停稳后应用")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        let decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        let marks = try XCTUnwrap(decoded.blocks.last?.runs.first?.marks)
        XCTAssertTrue(marks.contains(.bold))
        XCTAssertEqual(marks.textColorHex, "#ff3b30")
        XCTAssertFalse(handle.formatPainterActive)
        XCTAssertEqual(view.string, "源\n目标")
    }

    @MainActor
    func testFormatPainterCopiesBlockStyleAndCanBeCancelled() throws {
        let document = NativeDocument(plainText: "正文\n另一段")
        let view = makeView(document)
        view.setSelectedRange(NSRange(location: 3, length: 2))
        view.breakUndoCoalescing()
        view.applyCapturedStyle(DocumentSelectionStyle(
            blockToken: DocumentTextCodec.blockToken(.heading(2)),
            marks: [.bold], indentLevel: 1, align: .center))

        let decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        XCTAssertEqual(decoded.blocks[0].kind, .paragraph)
        XCTAssertEqual(decoded.blocks[1].kind, .heading(2))
        XCTAssertEqual(decoded.blocks[1].indentLevel, 1)
        XCTAssertEqual(decoded.blocks[1].align, .center)
        XCTAssertEqual(decoded.blocks[1].runs.first?.marks, [.bold])

        let handle = DocumentEditorHandle()
        handle.textView = view
        handle.toggleFormatPainter()
        XCTAssertTrue(handle.formatPainterActive)
        handle.toggleFormatPainter()
        XCTAssertFalse(handle.formatPainterActive)
    }

    // MARK: - 撤销状态

    @MainActor
    func testHandlePublishesUndoRedoAvailability() throws {
        let document = NativeDocument(plainText: "撤销")
        let view = makeView(document)
        let handle = DocumentEditorHandle()
        handle.textView = view
        handle.refreshStyle()
        XCTAssertFalse(handle.canUndo)

        view.setSelectedRange(NSRange(location: 0, length: 2))
        view.applyTextColor("#ff3b30")
        handle.refreshStyle()
        XCTAssertTrue(handle.canUndo)

        handle.undo()
        XCTAssertTrue(handle.canRedo)
        XCTAssertEqual(view.string, "撤销")
        handle.redo()
        XCTAssertTrue(handle.canUndo)
    }
}
