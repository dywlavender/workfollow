import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class SummaryExportTests: XCTestCase {
    private var document: NativeDocument {
        let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        return NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "10月19日-10月25日")]),
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "已完成")]),
            DocumentBlock(kind: .bullet, runs: [
                DocumentRun(text: "[10月21日] "),
                DocumentRun(text: "写周报", marks: [.bold, .link(NativeResourceLink.task(taskID).url.absoluteString)]),
            ]),
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "未完成")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "整理文档")]),
        ])
    }

    func testPlainTextKeepsSectionsAndBullets() {
        XCTAssertEqual(SummaryExportService.plainText(document), """
        10月19日-10月25日

        已完成
        • [10月21日] 写周报

        未完成
        • 整理文档
        """)
    }

    func testMarkdownKeepsDateBracketsAndTaskLinks() {
        let taskID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let link = NativeResourceLink.task(taskID).url.absoluteString
        XCTAssertEqual(SummaryExportService.markdown(document), """
        # 10月19日-10月25日

        ## 已完成
        - [10月21日] [**写周报**](<\(link)>)

        ## 未完成
        - 整理文档
        """)
        XCTAssertFalse(SummaryExportService.markdown(document).contains("\\[10月21日\\]"))
    }

    func testImageSourceKeepsListMarkersAndBoldTitles() throws {
        let attributed = SummaryExportService.attributedText(document)
        XCTAssertTrue(attributed.string.contains("•\t[10月21日] 写周报"))
        let title = "写周报" as NSString
        let range = (attributed.string as NSString).range(of: title as String)
        XCTAssertNotEqual(range.location, NSNotFound)
        let attributes = attributed.attributes(at: range.location, effectiveRange: nil)
        XCTAssertNil(attributes[.link])
        XCTAssertNil(attributes[.underlineStyle])
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testPNGAndPDFHaveReadableContentAndExpectedWidth() throws {
        let png = try SummaryExportService.imageData(document)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(bitmap.pixelsWide, 1400)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 200)

        let pdf = try SummaryExportService.pdfData(document)
        XCTAssertEqual(String(decoding: pdf.prefix(4), as: UTF8.self), "%PDF")
    }

    func testEmptyDocumentAndFileNames() {
        XCTAssertThrowsError(try SummaryExportService.data(for: .empty, format: .plainText)) { error in
            XCTAssertEqual(error as? SummaryExportError, .emptyDocument)
        }
        XCTAssertEqual(SummaryExportFormat.image.suggestedFileName(for: "摘要 10月19日-10月25日"),
                       "摘要 10月19日-10月25日.png")
        XCTAssertEqual(SummaryExportFormat.plainText.suggestedFileName(for: "工作/周报:本周"),
                       "工作-周报-本周.txt")
        XCTAssertEqual(SummaryExportFormat.markdown.suggestedFileName(for: "  "), "摘要.md")
        XCTAssertEqual(SummaryExportFormat.plainText.contentType.preferredFilenameExtension, "txt")
        XCTAssertEqual(SummaryExportFormat.markdown.contentType.preferredFilenameExtension, "md")
        XCTAssertEqual(SummaryExportFormat.image.contentType.preferredFilenameExtension, "png")
        XCTAssertEqual(SummaryExportFormat.pdf.contentType.preferredFilenameExtension, "pdf")
    }

    func testCopyFormatsWriteExpectedPasteboardPayloads() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SummaryExportTests-" + UUID().uuidString))
        defer { pasteboard.clearContents() }

        try SummaryCopyService.copy(document, format: .plainText, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), SummaryExportService.plainText(document))

        try SummaryCopyService.copy(document, format: .markdown, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), SummaryExportService.markdown(document))

        try SummaryCopyService.copy(document, format: .richText, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string),
                       SummaryExportService.attributedText(document).string)
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let html = try XCTUnwrap(pasteboard.data(forType: .html))
        XCTAssertFalse(rtf.isEmpty)
        XCTAssertFalse(html.isEmpty)
        let rich = try NSAttributedString(data: rtf, documentAttributes: nil)
        let titleRange = (rich.string as NSString).range(of: "写周报")
        XCTAssertNotEqual(titleRange.location, NSNotFound)
        let font = try XCTUnwrap(rich.attributes(at: titleRange.location, effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertNil(rich.attributes(at: titleRange.location, effectiveRange: nil)[.underlineStyle])
    }

    func testCopyRejectsEmptyDocumentWithoutClearingPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SummaryExportTests-" + UUID().uuidString))
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        pasteboard.setString("keep", forType: .string)
        XCTAssertThrowsError(try SummaryCopyService.copy(.empty, format: .richText, to: pasteboard)) { error in
            XCTAssertEqual(error as? SummaryExportError, .emptyDocument)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "keep")
    }

    func testExportBaseNameUsesBracketedRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21)))
        let range = SummaryDateRange.week(containing: anchor, calendar: calendar)
        XCTAssertEqual(SummaryExportService.baseName(for: range, calendar: calendar),
                       "摘要 (10月19日-10月25日)")
    }

    func testMailDraftUsesRichBodyAndNormalizesSubject() throws {
        let draft = try XCTUnwrap(SummaryMailDraft.make(
            subject: " 摘要 (10月19日-10月25日) ",
            document: document))
        XCTAssertEqual(draft.subject, "摘要 (10月19日-10月25日)")
        XCTAssertTrue(draft.plainText.contains("写周报"))
        XCTAssertTrue(draft.body.string.contains("写周报"))
        let range = (draft.body.string as NSString).range(of: "写周报")
        XCTAssertNotEqual(range.location, NSNotFound)
        let font = try XCTUnwrap(draft.body.attributes(at: range.location, effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))

        XCTAssertNil(SummaryMailDraft.make(subject: "摘要", document: .empty))
    }

    func testExportAndCopyReflectContentOrderListGroupAndPlainDetail() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
        let due = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))!
        var done = Task(id: UUID(), title: "写周报", tags: [], list: TaskList(name: "工作"),
                        priority: .medium, schedule: .init(dueAt: due, hasTime: true),
                        status: .completed, childOrder: 0, createdAt: now, updatedAt: now,
                        completedAt: now)
        done.document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文", marks: [.bold])]),
        ])
        let builder = WeeklyReportBuilder(calendar: calendar)
        let report = builder.report(tasks: [done], weekOf: now, listFolders: ["工作": "项目A"])
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .list, .detail]
        options.contentOrder = [.list, .taskName, .status, .progress,
                                .taskTime, .parentTask, .tags, .focus]
        options.contentStyles.list = .listGroup
        options.contentStyles.detail = .plain
        let output = builder.document(for: report, options: options)

        let plain = SummaryExportService.plainText(output)
        XCTAssertTrue(plain.contains("• 写周报"))
        XCTAssertTrue(plain.contains("▤ 项目A / 工作"))
        XCTAssertTrue(plain.contains("│ 正文"))
        let markdown = SummaryExportService.markdown(output)
        XCTAssertTrue(markdown.contains("写周报"))
        XCTAssertFalse(markdown.contains("**写周报**"))
        XCTAssertFalse(markdown.contains(NativeResourceLink.task(done.id).url.absoluteString))
        XCTAssertTrue(markdown.contains("项目A / 工作"))
        XCTAssertTrue(markdown.contains("> 正文"))
        XCTAssertFalse(markdown.contains("**正文**"))
        let attributed = SummaryExportService.attributedText(output)
        XCTAssertTrue(attributed.string.contains("写周报"))
        XCTAssertTrue(attributed.string.contains("项目A / 工作"))
        XCTAssertTrue(attributed.string.contains("│ 正文"))
        XCTAssertNoThrow(try SummaryExportService.imageData(output))
        XCTAssertNoThrow(try SummaryExportService.pdfData(output))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SummaryExportTests-" + UUID().uuidString))
        defer { pasteboard.clearContents() }
        try SummaryCopyService.copy(output, format: .plainText, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), plain)
        try SummaryCopyService.copy(output, format: .markdown, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), markdown)
        try SummaryCopyService.copy(output, format: .richText, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), attributed.string)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
        XCTAssertNotNil(pasteboard.data(forType: .html))
    }

    func testImageHeightLimitUsesBoundaryAndRejectsTaller() throws {
        XCTAssertEqual(SummaryExportService.maximumImagePixelHeight, 16_000)
        XCTAssertEqual(SummaryExportError.imageTooLong.localizedDescription,
                       "摘要内容过多，无法导出图片，请改用 PDF")
        let size = try SummaryExportService.imagePixelSize(for: document)
        XCTAssertGreaterThan(size.height, 1)
        XCTAssertThrowsError(try SummaryExportService.imageData(
            document, maximumPixelHeight: size.height - 1
        )) { error in
            XCTAssertEqual(error as? SummaryExportError, .imageTooLong)
        }
        XCTAssertNoThrow(try SummaryExportService.imageData(
            document, maximumPixelHeight: size.height
        ))
    }
}
