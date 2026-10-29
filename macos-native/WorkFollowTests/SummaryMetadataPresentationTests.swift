import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class SummaryMetadataPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 28800)!
        return value
    }
    private func day(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func datedTask(_ title: String, due: Int, end: Int? = nil,
                           timed: Bool = false, closed: Bool = false) -> Task {
        Task(id: UUID(), title: title, tags: ["项目", "待评审"], list: TaskList(name: "工作"), priority: .high,
            schedule: .init(dueAt: day(due, hour: timed ? 8 : 0), hasTime: timed, dueEndAt: end.map { self.day($0) }),
            status: closed ? .completed : .active, childOrder: 0, createdAt: day(20), updatedAt: day(27),
            completedAt: closed ? day(27) : nil)
    }
    private func dateDocument(_ tasks: [Task], content: Set<SummaryContentField> = [.taskName, .taskTime]) -> NativeDocument {
        let builder = WeeklyReportBuilder(calendar: calendar)
        let range = SummaryDateRange.custom(start: day(20), through: day(31), calendar: calendar)!
        var options = SummaryDocumentOptions.standard; options.content = content
        let report = builder.report(tasks: tasks, weekOf: day(27), range: range)
        return builder.document(for: report, options: options, now: day(27))
    }
    private func sample() -> (NativeDocument, Task) {
        var source = Task(id: UUID(), title: "完成本周方案与评审", tags: ["项目", "待评审"],
            list: .inbox, priority: .high,
            schedule: .init(dueAt: now.addingTimeInterval(-86400)), status: .completed,
            childOrder: 0, createdAt: now, updatedAt: now, completedAt: now)
        source.document = NativeDocument(plainText: "整理需求、确认交付范围，并记录本周遇到的问题。")
        let builder = WeeklyReportBuilder(calendar: .current)
        var options = SummaryDocumentOptions.standard
        options.content = [.taskName, .status, .completedTime, .taskTime, .tags, .list, .detail]
        let report = builder.report(tasks: [source], weekOf: now)
        return (builder.document(for: report, options: options), source)
    }

    func testGeneratedRowsKeepTitleAndSemanticMetadataOnOneBulletLine() throws {
        let (document, source) = sample()
        let row = try XCTUnwrap(document.blocks.first { $0.kind == .bullet })
        XCTAssertTrue(row.plainText.contains(source.title))
        XCTAssertEqual(row.runs.first { $0.text == source.title }?.marks, [])
        XCTAssertTrue(row.plainText.hasPrefix("["))
        let symbols = Set(row.runs.flatMap(\.marks).compactMap { mark -> DocumentInlineSymbol? in
            if case .symbol(let value) = mark { return value }; return nil
        })
        XCTAssertEqual(symbols, [.calendar, .tag, .inbox])
        XCTAssertTrue(row.plainText.contains("#项目、待评审"))
        XCTAssertTrue(row.runs.filter { $0.marks.contains(.caption) }.allSatisfy { $0.marks.contains(.muted) })
        XCTAssertFalse(row.plainText.contains("已完成"), "分组标题已表达状态，不重复添加")
        for raw in ["[x]", "[ ]", "<收集箱>"] { XCTAssertFalse(document.plainText.contains(raw)) }
        let decoded = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
    }

    func testTaskDatesShareDelayRulesAndKeepClosedDatesNeutral() throws {
        let cases: [(Task, DocumentInk?, String?)] = [
            (datedTask("未来任务", due: 29), .accent, nil),
            (datedTask("跨天逾期", due: 24), .danger, "延迟3天"),
            (datedTask("今天已过时刻", due: 27, timed: true), .danger, "延迟不足1天"),
            (datedTask("区间尚未结束", due: 24, end: 29), .accent, nil),
            (datedTask("区间结束", due: 20, end: 25), .danger, "延迟2天"),
            (datedTask("已完成", due: 24, closed: true), nil, nil),
        ]
        for (task, ink, delay) in cases {
            let document = dateDocument([task])
            let runs = try XCTUnwrap(document.blocks.first { $0.runs.contains { $0.marks.contains(.symbol(.calendar)) } }).runs
            let iconIndex = try XCTUnwrap(runs.firstIndex { $0.marks.contains(.symbol(.calendar)) })
            XCTAssertEqual(runs[iconIndex].marks.documentInk, ink, task.title)
            XCTAssertEqual(runs[iconIndex + 1].marks.documentInk, ink, "日期与日历图标同色")
            if let delay { XCTAssertTrue(runs[iconIndex + 1].text.contains(delay), task.title) }
            else { XCTAssertFalse(runs[iconIndex + 1].text.contains("延迟"), task.title) }
            XCTAssertEqual(delay, TaskInspectorSchedulePresentation.overdueDescription(
                schedule: task.schedule, isClosed: task.isClosed, now: day(27), calendar: calendar))
        }
        var abandoned = datedTask("已放弃", due: 24); abandoned.abandonedAt = day(27)
        XCTAssertFalse(dateDocument([abandoned]).blocks.flatMap(\.runs).contains { $0.marks.contains(.ink(.danger)) })
        let completed = dateDocument([datedTask("完成时间", due: 24, closed: true)], content: [.taskName, .completedTime])
        XCTAssertTrue(completed.blocks.flatMap(\.runs).allSatisfy { $0.marks.documentInk == nil })
    }

    func testListAndIndividualTagColorsUseTheExistingDirectory() throws {
        let task = datedTask("项目任务", due: 29)
        let tags = [TaskTag(name: "项目", colorARGB: WFListPalette.argb[0]),
                    TaskTag(name: "待评审", colorARGB: WFListPalette.argb[7])]
        let meta = TaskListMeta(name: "工作", colorIndex: 7, icon: "💼")
        let builder = WeeklyReportBuilder(calendar: calendar)
        let report = builder.report(tasks: [task], weekOf: day(27), tagDirectory: tags, listMetas: [meta])
        var options = SummaryDocumentOptions.standard; options.content = [.taskName, .tags, .list]
        let document = builder.document(for: report, options: options, now: day(27))
        let runs = document.blocks.flatMap(\.runs)
        XCTAssertEqual(runs.first { $0.text.trimmingCharacters(in: .whitespaces) == "项目" }?.marks.documentInk, .argb(WFListPalette.argb[0]))
        XCTAssertEqual(runs.first { $0.text == "待评审" }?.marks.documentInk, .argb(WFListPalette.argb[7]))
        XCTAssertEqual(runs.first { $0.text == "💼" }?.marks.documentInk, .argb(WFListPalette.argb(for: "工作", meta: meta)))
        XCTAssertEqual(try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(document)), document)
        let rendered = DocumentTextCodec.render(document)
        XCTAssertEqual(DocumentTextCodec.decode(rendered, preserving: document).plainText, document.plainText)
        XCTAssertTrue(DocumentTextCodec.decode(rendered, preserving: document).blocks.flatMap(\.runs).flatMap(\.marks).contains(.ink(.argb(WFListPalette.argb[0]))))
    }

    func testDateIconTextAndExportUseTheSameSemanticInk() throws {
        let document = dateDocument([datedTask("需要跟进", due: 24)])
        let rendered = DocumentTextCodec.render(document)
        let range = try XCTUnwrap(rendered.string.range(of: "\u{FFFC}")).nsRange(in: rendered.string)
        let cell = try XCTUnwrap((rendered.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell as? DocumentInlineSymbolCell)
        let textColor = try XCTUnwrap(rendered.attribute(.foregroundColor, at: range.location + 1, effectiveRange: nil) as? NSColor)
        XCTAssertTrue(cell.tint.isEqual(textColor))
        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertTrue(decoded.blocks.flatMap(\.runs).flatMap(\.marks).contains(.ink(.danger)))
        let fragment = try XCTUnwrap(DocumentClipboardCodec.fragment(from: rendered, range: .init(location: 0, length: rendered.length)))
        let pasted = try XCTUnwrap(DocumentClipboardCodec.decode(DocumentClipboardCodec.encodedData(for: fragment)))
        XCTAssertTrue(pasted.document.blocks.flatMap(\.runs).flatMap(\.marks).contains(.ink(.danger)))
        let export = SummaryExportService.attributedText(document, inlineSymbols: true)
        let label = (export.string as NSString).range(of: "延迟3天")
        let exportedColor = try XCTUnwrap(export.attribute(.foregroundColor, at: label.location, effectiveRange: nil) as? NSColor)
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        XCTAssertEqual(exportedColor, DocumentInk.danger.resolved(in: light))
        XCTAssertTrue(SummaryExportService.plainText(document).contains("延迟3天"))
    }

    func testNativeSymbolsRoundTripWithoutLosingAdjacentTypedText() throws {
        let (document, _) = sample()
        let rendered = DocumentTextCodec.render(document)
        let iconRange = try XCTUnwrap(rendered.string.range(of: "\u{FFFC}")).nsRange(in: rendered.string)
        let cell = try XCTUnwrap((rendered.attribute(.attachment, at: iconRange.location, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell as? DocumentInlineSymbolCell)
        XCTAssertEqual(cell.cellSize(), NSSize(width: 14, height: 14))
        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.plainText, document.plainText)
        XCTAssertEqual(decoded.blocks.flatMap(\.runs).flatMap(\.marks).filter { if case .symbol = $0 { return true }; return false }.count, 3)
        let edited = NSMutableAttributedString(attributedString: rendered)
        edited.insert(NSAttributedString(string: "补充", attributes: rendered.attributes(at: iconRange.location, effectiveRange: nil)), at: iconRange.location + 1)
        let result = DocumentTextCodec.decode(edited, preserving: document)
        XCTAssertTrue(result.plainText.contains("◷补充"))
        XCTAssertTrue(DocumentTextCodec.render(result).string.contains("补充"))
    }

    func testExportsKeepReadableFallbacksAndVisualSymbols() throws {
        let (document, source) = sample()
        let plain = SummaryExportService.plainText(document)
        XCTAssertTrue(plain.contains("◷")); XCTAssertTrue(plain.contains(source.title))
        XCTAssertFalse(plain.contains("\u{FFFC}"))
        let markdown = SummaryExportService.markdown(document)
        XCTAssertFalse(markdown.contains(NativeResourceLink.task(source.id).url.absoluteString))
        XCTAssertTrue(markdown.contains("项目、待评审"))
        let rich = try SummaryCopyService.payload(for: .richText, document: document)
        XCTAssertTrue(rich.string?.contains("◷") == true)
        XCTAssertFalse(rich.string?.contains("\u{FFFC}") == true)
        let caption = SummaryExportService.attributedText(document)
        let label = (caption.string as NSString).range(of: "项目、待评审")
        XCTAssertEqual((caption.attribute(.font, at: label.location, effectiveRange: nil) as? NSFont)?.pointSize, 12)
        XCTAssertTrue(SummaryExportService.attributedText(document, inlineSymbols: true).string.contains("\u{FFFC}"))
        let rendered = DocumentTextCodec.render(document)
        let fragment = try XCTUnwrap(DocumentClipboardCodec.fragment(from: rendered, range: NSRange(location: 0, length: rendered.length)))
        let pasteboard = NSPasteboard(name: .init("SummaryMetadata-" + UUID().uuidString))
        defer { pasteboard.clearContents() }
        XCTAssertTrue(DocumentClipboardCodec.write(fragment, to: pasteboard))
        let pasted = try XCTUnwrap(DocumentClipboardCodec.read(from: pasteboard))
        XCTAssertEqual(pasted.document.plainText, document.plainText)
        XCTAssertTrue(pasted.document.blocks.flatMap(\.runs).flatMap(\.marks).contains(.symbol(.calendar)))
        XCTAssertFalse(pasteboard.string(forType: .string)?.contains("\u{FFFC}") == true)
        XCTAssertFalse(try SummaryExportService.imageData(document).isEmpty)
        XCTAssertFalse(try SummaryExportService.pdfData(document).isEmpty)
    }

    func testNativeEditorMetadataLayoutInLightDarkAndNarrowWindows() throws {
        let builder = WeeklyReportBuilder(calendar: calendar)
        let tasks = [datedTask("整理项目方案", due: 26), datedTask("准备评审材料", due: 29),
                     datedTask("确认交付范围", due: 26, closed: true)]
        let tags = [TaskTag(name: "项目", colorARGB: WFListPalette.argb[7]),
                    TaskTag(name: "待评审", colorARGB: WFListPalette.argb[0])]
        let report = builder.report(tasks: tasks, weekOf: day(27), tagDirectory: tags,
            listMetas: [TaskListMeta(name: "工作", colorIndex: 7, icon: "💼")])
        var options = SummaryDocumentOptions.standard; options.content = [.taskName, .completedTime, .taskTime, .tags, .list]
        let document = builder.document(for: report, options: options, now: day(27))
        for (name, width, dark) in [("light", 700.0, false), ("dark", 700.0, true), ("narrow", 340.0, false)] {
            let handle = DocumentEditorHandle()
            let root = DocumentEditor(documentID: UUID(), document: document,
                onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in }, handle: handle)
                .padding(24).frame(width: width, height: 620)
                .background(WFColors.content).preferredColorScheme(dark ? .dark : .light)
            let host = NSHostingView(rootView: root)
            let window = InspectorPanelTestSupport.ownerWindow(for: host, width: width, height: 620)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            defer { window.close() }
            InspectorPanelTestSupport.settle(window)
            let text = try XCTUnwrap(handle.textView)
            XCTAssertTrue(text.isEditable)
            let storage = try XCTUnwrap(text.textStorage)
            let range = (storage.string as NSString).range(of: "项目、待评审")
            XCTAssertNotEqual(range.location, NSNotFound)
            XCTAssertEqual((storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)?.pointSize, 12)
            if let directory = ProcessInfo.processInfo.environment["WORKFOLLOW_SUMMARY_CAPTURE_DIRECTORY"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let visibleContent = CGRect(x: 0, y: 0, width: host.bounds.width, height: width < 500 ? 500 : 340)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: visibleContent))
                host.cacheDisplay(in: visibleContent, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name + ".png"))
            }
        }
    }
}

private extension Range where Bound == String.Index {
    func nsRange(in text: String) -> NSRange { NSRange(self, in: text) }
}
