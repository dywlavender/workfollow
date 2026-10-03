import XCTest
import SwiftUI
@testable import WorkFollow

/// 活动行标记（标题角标 / 空行"+"）的离屏渲染验收。
///
/// 把 `NativeTextView` 挂到真实窗口、设好选区后抓取真实渲染结果
/// （`drawViewHierarchy`；TextKit 2 的文本不走 `draw(_:)`，
/// `cacheDisplay` 抓不到）：
/// - 沟槽（视图左侧 20pt）里的非白像素只可能来自行首装饰——
///   正文与光标都画在 x≥25，所以"沟槽有墨"⇔"标记画出来了"。
/// - 同时把 PNG 落到 /tmp 供人工目检几何位置。
final class DocumentDecorationRenderTests: XCTestCase {
    @MainActor
    func testCompletionPresentationIsRemovedFromNonChecklistDisplayWithoutRemovingExplicitStrike() {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        var inherited = DocumentTextCodec.attributes(kind: .checklist(true), marks: [])
        inherited[DocumentTextCodec.blockKey] = "h1"
        let value = NSMutableAttributedString(string: "标题", attributes: inherited)
        value.append(NSAttributedString(string: "显式删除线", attributes:
            DocumentTextCodec.attributes(kind: .paragraph, marks: [.strikethrough])))
        view.textStorage?.setAttributedString(value)
        view.didChangeText()
        XCTAssertNil(view.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertNil(view.textStorage?.attribute(DocumentTextCodec.completedChecklistPresentationKey, at: 0, effectiveRange: nil))
        XCTAssertNotNil(view.textStorage?.attribute(.strikethroughStyle, at: 2, effectiveRange: nil))
    }

    @MainActor
    func testTogglingEarlierChecklistDoesNotLeakStrikeIntoTrailingHeading() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "事项")]),
            DocumentBlock(kind: .paragraph, runs: [])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [])
        window.makeFirstResponder(view)
        view.toggleNoteChecklist(at: 0)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.setSelectedRange(NSRange(location: 3, length: 0))
        // Native caret relocation may retain checked presentation attributes
        // even after the empty paragraph's block type has been restored.
        var inherited = DocumentTextCodec.attributes(kind: .checklist(true), marks: [])
        inherited[DocumentTextCodec.blockKey] = "paragraph"
        view.typingAttributes = inherited
        view.applyFormat(try XCTUnwrap(EditorCommandCatalog.format("format.heading1")))
        view.insertText("新标题", replacementRange: view.selectedRange())
        let decoded = DocumentTextCodec.decode(view.attributedString(), preserving: document,
                                               trailing: view.pendingTrailingBlock)
        XCTAssertEqual(decoded.blocks.first?.kind, .checklist(true))
        XCTAssertEqual(decoded.blocks.last?.kind, .heading(1))
        XCTAssertFalse(try XCTUnwrap(decoded.blocks.last?.runs.first).marks.contains(.strikethrough))
    }

    @MainActor
    func testExistingHeadingAndQuoteGeometryIgnoresTrailingTypingStyle() throws {
        for kind in [DocumentBlockKind.heading(1), .heading(2), .heading(3), .quote] {
            let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180), textContainer: nil)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFront(nil)
            defer { window.close() }
            let document = NativeDocument(blocks: [DocumentBlock(kind: kind, runs: [DocumentRun(text: "标题或引用")])])
            view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 5, length: 0))
            view.typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [])
            view.insertNewline(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let original = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
            for typingKind in [DocumentBlockKind.paragraph, .bullet, .heading(1)] {
                let command = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.block == typingKind })
                view.applyFormat(command)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let changed = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
                XCTAssertEqual(changed.minX, original.minX, accuracy: 0.5, "\(kind)")
                XCTAssertEqual(changed.height, original.height, accuracy: 0.5, "\(kind)")
                XCTAssertEqual(DocumentTextCodec.decode(view.attributedString(), preserving: document,
                    trailing: view.pendingTrailingBlock).blocks.first?.kind, kind)
            }
        }
    }

    @MainActor
    func testChecklistVisibleRightEdgeRemainsClickableAfterExitingList() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "plp")])
        ])))
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.typingAttributes = DocumentTextCodec.attributes(kind: .checklist(false), marks: [])
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        view.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let line = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
        // Inside the visible box's right edge, outside the stale hit rectangle.
        let point = view.convert(NSPoint(x: line.minX - 9, y: line.midY), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let release = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        NSApp.postEvent(release, atStart: true)
        view.mouseDown(with: event)
        XCTAssertEqual(view.textStorage?.attribute(DocumentTextCodec.blockKey, at: 0, effectiveRange: nil) as? String,
                       "checked", "The displayed checkbox must toggle across its visible bounds")
        XCTAssertEqual(view.string, "plp\n")
    }

    @MainActor
    func testListMarkerStaysAnchoredWhenDoubleReturnExitsList() throws {
        for kind in [DocumentBlockKind.bullet, .ordered, .checklist(false)] {
            let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 180), textContainer: nil)
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.contentView = view
            window.orderFront(nil)
            defer { window.close() }
            view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
                DocumentBlock(kind: kind, runs: [DocumentRun(text: "plp")])
            ])))
            window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: 3, length: 0))
            view.typingAttributes = DocumentTextCodec.attributes(kind: kind, marks: [])
            func settle() {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            settle()
            let original = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
            view.insertNewline(nil)
            settle()
            XCTAssertEqual(try XCTUnwrap(view.viewRect(forCharacterAt: 0)).minX, original.minX, accuracy: 0.5)
            XCTAssertTrue(view.exitEmptyBlockOnNewline())
            settle()
            let exited = try XCTUnwrap(view.viewRect(forCharacterAt: 0))
            XCTAssertEqual(exited.minX, original.minX, accuracy: 0.5, "\(kind): exiting the trailing list must not move the preceding marker")
            let emptyLine = try XCTUnwrap(view.viewRect(forCharacterAt: view.string.utf16.count))
            XCTAssertTrue(view.openEmptyBlockMenu(at: NSPoint(x: max(5, view.decorationVisibleMinX + 4) + 3,
                                                             y: emptyLine.midY)))
            XCTAssertEqual(view.string, "plp\n", "The plus opens a menu without inserting content")
            view.dismissSlash()
            if kind == .bullet {
                view.displayIfNeeded()
                let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
                    CGWindowID(window.windowNumber), [.bestResolution]))
                try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: "/tmp/render_list_double_return.png"))
            }
            view.insertNewline(nil)
            settle()
            XCTAssertEqual(try XCTUnwrap(view.viewRect(forCharacterAt: 0)).minX, original.minX, accuracy: 0.5)
        }
    }

    @MainActor
    func testMixedListsAndContinuousQuoteRender() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 240), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "0")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "1")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "按时")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "按时 d")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func rect(_ offset: Int) -> NSRect {
            view.convert(window.convertFromScreen(view.firstRect(forCharacterRange:
                NSRange(location: offset, length: 0), actualRange: nil)), from: nil)
        }
        XCTAssertEqual(rect(0).minX, rect(2).minX, accuracy: 0.5)
        XCTAssertEqual(rect(4).minX, rect(0).minX, accuracy: 0.5)
        XCTAssertEqual(rect(0).minX - rect(12).minX, 16, accuracy: 0.5)
        view.displayIfNeeded()
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(bitmap.pixelsWide) / window.frame.width
        let bridgeX = rect(4).minX - DocumentEditorGeometry.quoteTextIndent
            + DocumentEditorGeometry.quoteRuleInset + DocumentEditorGeometry.quoteRuleWidth / 2
        let bridgeY = (rect(4).maxY + rect(7).minY) / 2
        // NSTextView may size itself to the document, so account for its frame
        // within the window before sampling the top-down window capture.
        let point = view.convert(NSPoint(x: bridgeX, y: bridgeY), to: nil)
        let captureY = window.frame.height - point.y
        let bridgeColor = try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int(captureY * scale)))
        XCTAssertLessThan(bridgeColor.redComponent, 0.95, "相邻引用之间的竖线不能断开")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_mixed_list_quote.png"))
    }

    @MainActor
    func testHeadingAndPlusLaneStayBeforeHostContentOrigin() throws {
        let host = NSHostingView(rootView:
            DocumentEditor(documentID: UUID(), document: .empty,
                           onDocumentChange: { _ in }, onEscape: { .keepInspector },
                           onEditingChanged: { _ in })
                .padding(.horizontal, 40))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        func editor(in view: NSView) -> NativeTextView? {
            if let text = view as? NativeTextView { return text }
            return view.subviews.lazy.compactMap { editor(in: $0) }.first
        }
        let text = try XCTUnwrap(editor(in: host))
        window.makeFirstResponder(text)
        func caretX() -> CGFloat {
            let rect = text.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
            return host.convert(window.convertFromScreen(rect), from: nil).minX
        }
        let emptyX = caretX()
        XCTAssertEqual(emptyX, 45, accuracy: 1, "正文起点应是宿主40pt加TextKit的5pt，不额外占20pt沟槽")
        text.applyFormat(try XCTUnwrap(EditorCommandCatalog.format("format.heading1")))
        text.insertText("一级标题", replacementRange: NSRange(location: 0, length: 0))
        text.setSelectedRange(NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(caretX(), emptyX, accuracy: 1, "切换标题不能改变正文起点")
        let viewOrigin = host.convert(.zero, from: text).x
        XCTAssertEqual(viewOrigin, 20, accuracy: 1, "装饰沟槽前置于宿主40pt正文区域")
        text.displayIfNeeded()
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        let bitmap = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_heading_host_alignment.png"))
    }

    private let sample = NativeDocument(blocks: [
        DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题行")]),
        DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
        DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")]),
    ])

    @MainActor
    private func renderedGutter(caret: Int, dump name: String,
                                typingKind: DocumentBlockKind? = nil) throws -> (rep: NSBitmapImageRep, scale: CGFloat) {
        let width: CGFloat = 600
        let height: CGFloat = 300
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: width, height: height), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.hasShadow = false
        // 装饰用的是动态系统色（tertiaryLabelColor 等）：系统切到深色模式后，
        // 它们变成近白色，"白底 + 非白像素"的断言会整片失效（实测踩过）。
        // 测试把外观钉在浅色，颜色可预期，与断言口径一致。
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        view.textStorage?.setAttributedString(DocumentTextCodec.render(sample))
        if let typingKind {
            view.typingAttributes = DocumentTextCodec.attributes(kind: typingKind, marks: [])
            // 装饰层读取模型同步的文末级别（测试里没有协调器，手动给值）。
            view.displayedTrailingBlock = typingKind
        }
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        // 直接抓窗口合成结果：TextKit 2 的文本不走 draw(_)，位图重绘抓不到；
        // 窗口镜像才是用户看到的真实画面。
        let cgImage = try XCTUnwrap(CGWindowListCreateImage(
            .null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/render_\(name).png"))
        let scale = CGFloat(rep.pixelsWide) / width
        return (rep, scale)
    }

    /// 沟槽区域内是否存在非白的不透明像素。
    /// 窗口底为白，正文/光标都在 x≥25pt；捕获图两侧有透明黑边（alpha=0），
    /// 必须按 alpha 过滤，否则透明黑会被误判成墨迹。
    private func gutterHasInk(_ rep: NSBitmapImageRep, scale: CGFloat) -> Bool {
        let columnLimit = min(Int(20.0 * scale), rep.pixelsWide)
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < columnLimit {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 {
                    let isBackground = color.redComponent > 0.95
                        && color.greenComponent > 0.95 && color.blueComponent > 0.95
                    if !isBackground { return true }
                }
                x += 1
            }
            y += 1
        }
        return false
    }

    /// 光标在标题行：行首沟槽应出现 H2 角标。
    @MainActor
    func testHeadingBadgeDrawsInGutterForActiveHeadingLine() throws {
        let (rep, scale) = try renderedGutter(caret: 0, dump: "badge")
        XCTAssertTrue(gutterHasInk(rep, scale: scale),
                      "H2 角标应画在标题行左侧的沟槽里")
    }

    /// 光标在文末空行：行首沟槽应出现 "+"。
    @MainActor
    func testEmptyLinePlusDrawsInGutterForActiveEmptyLine() throws {
        let (rep, scale) = try renderedGutter(caret: sample.plainText.count, dump: "plus")
        XCTAssertTrue(gutterHasInk(rep, scale: scale),
                      "空行活动时沟槽里应画出 +")
    }

    /// 光标在非空正文行：沟槽应保持干净（普通段落没有行首标记）。
    @MainActor
    func testPlainBodyLineLeavesGutterEmpty() throws {
        let (rep, scale) = try renderedGutter(caret: 5, dump: "plain")
        XCTAssertFalse(gutterHasInk(rep, scale: scale), "普通非空段落不应在沟槽里画任何标记")
    }

    /// 两个渲染在指定横向区间（pt）内，B 相对 A 新出现的非白像素数。
    /// 捕获图存在垂直翻转/底部锚定的不确定性与透明边缘，逐列差分比
    /// 固定坐标区域更稳。
    private func newInkCount(base: NSBitmapImageRep, other: NSBitmapImageRep,
                             scale: CGFloat, ptColumn: NSRange) -> Int {
        let x0 = Int(Double(ptColumn.location) * scale)
        let x1 = min(Int(Double(ptColumn.location + ptColumn.length) * scale), other.pixelsWide)
        func isInk(_ color: NSColor?) -> Bool {
            guard let color, color.alphaComponent > 0.5 else { return false }
            return !(color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95)
        }
        var count = 0
        var y = 0
        while y < min(base.pixelsHigh, other.pixelsHigh) {
            var x = x0
            while x < x1 {
                if !isInk(base.colorAt(x: x, y: y)), isInk(other.colorAt(x: x, y: y)) { count += 1 }
                x += 1
            }
            y += 1
        }
        return count
    }

    /// 光标在文末空段且待定级别是列表：列表缩进区应画出项目符号
    /// （无字符的段落主循环看不到，由活动行绘制补上）。
    /// 基线是同一位置的"+"（画在沟槽 0..15pt），列表符号画在缩进区 25..45pt，
    /// 对比两者在符号区的新增墨迹。
    @MainActor
    func testTrailingEmptyLineWithPendingListKindDrawsMarker() throws {
        let baseline = try renderedGutter(caret: sample.plainText.count, dump: "pending_plus",
                                          typingKind: nil)
        let pending = try renderedGutter(caret: sample.plainText.count, dump: "pending_list",
                                         typingKind: .bullet)
        let delta = newInkCount(base: baseline.rep, other: pending.rep,
                                scale: pending.scale, ptColumn: NSRange(location: 16, length: 44))
        XCTAssertGreaterThan(delta, 10, "文末空段的待定列表应画出项目符号")
    }
}
