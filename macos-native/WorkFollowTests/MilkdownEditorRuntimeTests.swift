import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class MilkdownEditorRuntimeTests: XCTestCase {
    @MainActor final class Model: ObservableObject {
        @Published var id = UUID()
        @Published var document = NativeDocument(plainText: "原始中文🙂内容")
        let handle = DocumentEditorHandle()
        var profile = DocumentProfile()
    }
    struct Host: View {
        @ObservedObject var model: Model
        var growing = false
        var readOnly = false
        var body: some View {
            DocumentEditor(documentID: model.id, document: model.document,
                onDocumentChange: { model.document = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in },
                profile: model.profile, contentSized: growing, handle: model.handle, readOnly: readOnly)
                .frame(width: 700, height: growing ? nil : 460)
        }
    }
    private func wait(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "MilkdownRuntimeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func fixture(readOnly: Bool = false, document: NativeDocument? = nil, profile: DocumentProfile = .init()) async throws -> (Model, MilkdownWebView, NSWindow) {
        let model = Model()
        if let document { model.document = document }
        model.profile = profile
        let host = NSHostingView(rootView: Host(model: model, readOnly: readOnly))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 480)
        addTeardownBlock { @MainActor in window.contentView = nil; window.close() }
        try await wait("编辑器未加载：\(model.handle.webView?.loadError ?? "等待 WebKit")") { model.handle.webView?.isDocumentReady == true }
        return (model, try XCTUnwrap(model.handle.webView), window)
    }

    /// 标题回车接力：光标落在正文第一行末尾；第一行空着时就是行首。
    func testFocusFirstLineLandsAtFirstLineEnd() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "第一行正文\n第二行正文"))
        model.handle.focusFirstLine()
        try await wait("光标没有落到第一行末尾") {
            guard let range = try? MilkdownTestSupport.range(view) else { return false }
            return range == NSRange(location: 5, length: 0)
        }
        XCTAssertTrue(MilkdownTestSupport.isFocused(view))
    }

    /// 标题右方向键接力：光标落在正文第一行行首。
    func testFocusFirstLineStartLandsAtDocumentStart() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "第一行正文\n第二行正文"))
        model.handle.focusFirstLineStart()
        try await wait("光标没有落到第一行行首") {
            guard let range = try? MilkdownTestSupport.range(view) else { return false }
            return range == NSRange(location: 0, length: 0)
        }
        XCTAssertTrue(MilkdownTestSupport.isFocused(view))
    }

    /// 正文第一行行首按左方向键：上报 leftEdgePressed，宿主把焦点交还标题栏；
    /// 光标不在行首时（第二行行首）不能误报。
    func testLeftEdgeAtDocumentStartRequestsTitleFocus() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "第一行正文\n第二行正文"))
        var leftEdgeRequests = 0
        model.handle.onLeftEdge = { leftEdgeRequests += 1 }
        try MilkdownTestSupport.command(view, "focusFirstLineStart")
        try await wait("光标没有落到第一行行首") { (try? MilkdownTestSupport.range(view))?.location == 0 }
        try MilkdownTestSupport.script(view, """
            document.querySelector('.ProseMirror').dispatchEvent(
              new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }))
            """)
        try await wait("leftEdgePressed 没有上报") { leftEdgeRequests == 1 }
        // 光标不在第一行行首时（第二行中间）按左方向键：不上报。合成事件不会驱动
        // 浏览器原生光标移动，所以这里只断言「没有重复上报」，移动语义由真机覆盖。
        try MilkdownTestSupport.select(view, NSRange(location: 8, length: 0))
        try MilkdownTestSupport.script(view, """
            document.querySelector('.ProseMirror').dispatchEvent(
              new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }))
            """)
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(leftEdgeRequests, 1, "不在行首时不应上报")
        XCTAssertEqual((try? MilkdownTestSupport.range(view))?.location, 8, "光标不应移动")
    }

    /// 第一行选字时上方放不下浮条，应翻到选区下方，不压住第一行文字。
    func testSelectionToolbarClearsFirstLine() async throws {
        var profile = DocumentProfile()
        profile.selectionToolbarEnabled = true
        let (_, view, _) = try await fixture(document: NativeDocument(plainText: "第一行正文\n第二行正文"), profile: profile)
        try MilkdownTestSupport.command(view, "focus")
        try MilkdownTestSupport.select(view, NSRange(location: 0, length: 3))
        try await wait("选区浮条没有出现") {
            guard let value = try? MilkdownTestSupport.script(view, "document.getElementById('wf-selection').hidden"),
                  let hidden = value as? Bool else { return false }
            return !hidden
        }
        let geometry = try XCTUnwrap(MilkdownTestSupport.script(view, """
            (() => { const bar = document.getElementById('wf-selection').getBoundingClientRect();
              const text = window.getSelection().getRangeAt(0).getBoundingClientRect();
              return {barTop: bar.top, barBottom: bar.bottom, textTop: text.top, textBottom: text.bottom}; })()
            """) as? [String: CGFloat])
        let barTop = try XCTUnwrap(geometry["barTop"]), barBottom = try XCTUnwrap(geometry["barBottom"])
        let textTop = try XCTUnwrap(geometry["textTop"]), textBottom = try XCTUnwrap(geometry["textBottom"])
        XCTAssertTrue(barTop >= textBottom || barBottom <= textTop,
            "选区浮条不应覆盖第一行文字（浮条 \(barTop)-\(barBottom)，文字 \(textTop)-\(textBottom)）")
    }

    func testProductionBodyLoadsEditsAndUsesItsOwnUndoHistory() async throws {
        let (model, view, _) = try await fixture()
        let original = model.document
        _ = try await view.call("command", ["name": "select", "payload": ["from": 1, "to": 3]])
        _ = try await view.call("command", ["name": "format", "payload": ["id": "bold"]])
        await view.flush()
        XCTAssertTrue(model.document.blocks[0].runs.contains { $0.marks.contains(.bold) })
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(model.document, original)
        _ = try await view.call("command", ["name": "redo"]); await view.flush()
        XCTAssertTrue(model.document.blocks[0].runs.contains { $0.marks.contains(.bold) })
        XCTAssertEqual(model.document.blocks[0].id, original.blocks[0].id)
    }
    func testReadOnlyBodyRejectsEditing() async throws {
        let (model, view, _) = try await fixture(readOnly: true)
        let original = model.document
        let result = try await view.call("command", ["name": "insertText", "payload": ["text": "不应写入"]])
        XCTAssertEqual(result as? Bool, false); await view.flush(); XCTAssertEqual(model.document, original)
    }
    func testAISelectionReplacementIsAcknowledgedAndStaleSelectionIsRejected() async throws {
        let (model, view, _) = try await fixture()
        _ = try await view.call("command", ["name": "select", "payload": ["from": 1, "to": 3]])
        let object = try await view.call("getSelection")
        let packet = try XCTUnwrap(object as? [String: Any], "Selection returned \(String(describing: object))")
        let selection = try JSONDecoder().decode(MilkdownSelection.self, from: JSONSerialization.data(withJSONObject: packet))
        let target = try XCTUnwrap(AISelectionTarget(editor: view, selection: selection))
        let applied = await target.applyAsync("修改", inserting: false)
        XCTAssertTrue(applied); await view.flush(); XCTAssertTrue(model.document.plainText.hasPrefix("修改"))
        let repeated = await target.applyAsync("不能重复", inserting: false)
        XCTAssertFalse(repeated)
    }

    func testMultilineAIAdoptionCreatesNativeBlocksAndUndoRestoresOriginal() async throws {
        let (model, view, _) = try await fixture()
        let original = model.document
        _ = try await view.call("command", ["name": "selectPlain", "payload": ["from": 0, "to": original.plainText.utf16.count]])
        let selection = try MilkdownTestSupport.selection(view)
        let target = try XCTUnwrap(AISelectionTarget(editor: view, selection: selection))
        let applied = await target.applyAsync("第一段\n第二段\n", inserting: false)
        XCTAssertTrue(applied)
        await view.flush()
        XCTAssertEqual(model.document.plainText, "第一段\n第二段\n")
        XCTAssertEqual(model.document.blocks.count, 3)
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(model.document, original)
    }

    func testEveryToolbarBlockCommandProducesSupportedNativeKinds() async throws {
        let (model, view, _) = try await fixture()
        for command in DocumentFormatCommand.commands where command.block != nil {
            _ = try await view.call("command", ["name": "format", "payload": ["id": "paragraph"]])
            _ = try await view.call("command", ["name": "format", "payload": ["id": String(command.id.dropFirst(7))]])
            await view.flush()
            XCTAssertEqual(model.document.blocks[0].kind, command.block, command.id)
            XCTAssertEqual(model.document.blocks[0].bodySize, command.bodySize, command.id)
        }
    }

    func testInlineTableAndFormulaEditsReachNativeDocumentAndUndo() async throws {
        let table = NativeTable(rows: [["甲", "乙"], ["1", "2"]]), formula = NativeFormula(latex: "x^2")
        let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [
            .init(text: "\u{fffc}", table: table), .init(text: "\u{fffc}", formula: formula)
        ])])
        let (model, view, _) = try await fixture(document: document)
        try MilkdownTestSupport.script(view, "(() => { const field=document.querySelector('textarea'); field.value='修改单元格'; field.dispatchEvent(new Event('input',{bubbles:true})); })()")
        await view.flush()
        XCTAssertEqual(model.document.blocks[0].runs[0].table?.rows[0][0], "修改单元格")
        try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed-controls button').click()")
        await view.flush()
        XCTAssertEqual(model.document.blocks[0].runs[0].table?.rows.count, 3)
        XCTAssertEqual(model.document.blocks[0].runs[0].table?.rows[0][0], "修改单元格")
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        try MilkdownTestSupport.script(view, "(() => { const field=document.querySelector('input'); field.value='\\\\frac{a}{b}'; field.dispatchEvent(new Event('input',{bubbles:true})); })()")
        await view.flush()
        XCTAssertEqual(model.document.blocks[0].runs[1].formula?.latex, "\\frac{a}{b}")
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelectorAll('.katex').length") as? Int, 1)
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(model.document.blocks[0].runs[1].formula?.latex, "x^2")
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(model.document, document)
    }

    func testChecklistToggleRetainsReminderAndUsesNativeMetadata() async throws {
        let reminder = Date(timeIntervalSinceReferenceDate: 9000)
        let document = NativeDocument(blocks: [.init(kind: .checklist(false), runs: [.init(text: "检查项")],
            checklist: .init(reminderAt: reminder))])
        let (model, view, _) = try await fixture(document: document)
        try MilkdownTestSupport.script(view, "document.querySelector('.wf-marker').click()")
        await view.flush()
        XCTAssertEqual(model.document.blocks[0].kind, .checklist(true))
        XCTAssertEqual(model.document.blocks[0].checklist?.reminderAt, reminder)
        XCTAssertNotNil(model.document.blocks[0].checklist?.completedAt)
        XCTAssertEqual(model.document.blocks[0].id, document.blocks[0].id)
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('[role=checkbox]').getAttribute('aria-checked')") as? String, "true")
    }

    func testHostOwnedDocumentTransactionUndoAndRedoUseTheirBusinessCallbacks() async throws {
        let (model, view, _) = try await fixture()
        let original = model.document, replacement = NativeDocument(plainText: "关联任务插入后的正文")
        var commits = 0, inverses = 0
        XCTAssertTrue(model.handle.replaceDocument(replacement, commit: { model.document = $0; commits += 1 },
            inverseCommit: { model.document = $0; inverses += 1 }))
        try await wait("宿主事务未提交") { commits == 1 }
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(inverses, 1); XCTAssertEqual(model.document, original)
        _ = try await view.call("command", ["name": "redo"]); await view.flush()
        XCTAssertEqual(commits, 2); XCTAssertEqual(model.document, replacement)
    }

    func testNativePrivateAndRichClipboardPastePreserveBlocksAndStyles() async throws {
        let (model, view, _) = try await fixture()
        let fragment = NativeDocument(blocks: [.init(kind: .heading(2), runs: [.init(text: "粘贴标题", marks: [.bold])]),
            .init(kind: .checklist(false), runs: [.init(text: "检查项")])])
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = DocumentClipboardCodec.write(.init(document: fragment, startsAtParagraphBoundary: true, endsAtParagraphBoundary: true), to: board)
        try MilkdownTestSupport.select(view, NSRange(location: 0, length: model.document.plainText.utf16.count))
        view.paste(from: board)
        try await wait("内部剪贴板未写入") { model.document.plainText.contains("粘贴标题") }
        XCTAssertTrue(model.document.blocks.contains { $0.kind == .heading(2) && $0.runs.contains { $0.marks.contains(.bold) } })
        board.clearContents(); board.setString("<p><b>外部粗体</b></p><p>另一段</p>", forType: .html)
        try MilkdownTestSupport.command(view, "focusEnd"); view.paste(from: board)
        try await wait("HTML 剪贴板未写入") { model.document.plainText.contains("外部粗体") }
        XCTAssertTrue(model.document.blocks.flatMap(\.runs).contains { $0.text.contains("外部粗体") && $0.marks.contains(.bold) })
    }

    func testImageLoadsFromNativeAssetAndResizesWithoutSendingItsPayloadBack() async throws {
        let image = NSImage(size: NSSize(width: 32, height: 16))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 32, height: 16).fill(); image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation), bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let file = NativeAttachment(id: UUID(), name: "虚构图片.png", storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", attachment: file)])])
        let (model, view, _) = try await fixture(document: document)
        try MilkdownTestSupport.wait("图片资源没有加载") { (try? MilkdownTestSupport.script(view, "document.querySelector('.wf-embed img').naturalWidth")) as? Int == bitmap.pixelsWide }
        let wire = try await view.call("getDoc")
        let data = try JSONSerialization.data(withJSONObject: wire)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("base64"))
        _ = try await view.call("command", ["name": "updateEmbed", "payload": ["id": file.id.uuidString, "value": ["width": 160, "height": 80]]])
        await view.flush()
        let resized = try XCTUnwrap(model.document.blocks[0].runs[0].attachment)
        XCTAssertEqual(resized.storedName, file.storedName)
        XCTAssertEqual(resized.displayWidth, 160); XCTAssertEqual(resized.displayHeight, 80)
        _ = try await view.call("command", ["name": "undo"]); await view.flush()
        XCTAssertEqual(model.document, document)
    }

    func testNativeKeyboardInputTriggersMarkdownBlocksAndInlineMarks() async throws {
        for (source, kind, text, mark) in [
            ("# 标题", DocumentBlockKind.heading(1), "标题", Optional<DocumentMark>.none),
            ("- [x] 检查", .checklist(true), "检查", nil),
            ("```代码", .code, "代码", nil),
            ("**粗**", .paragraph, "粗", .bold),
            ("~下划~", .paragraph, "下划", .underline),
            ("::高亮::", .paragraph, "高亮", .highlight)
        ] {
            let (model, view, window) = try await fixture(document: .empty)
            let client = try MilkdownTestSupport.inputClient(view)
            for character in source {
                client.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                InspectorPanelTestSupport.settle(window, duration: 0.025)
            }
            await view.flush()
            XCTAssertEqual(model.document.plainText, text, source)
            XCTAssertEqual(model.document.blocks[0].kind, kind, source)
            if let mark { XCTAssertTrue(model.document.blocks[0].runs.contains { $0.marks.contains(mark) }, source) }
            window.contentView = nil; window.close()
        }
    }

    func testNestedListEnterOutdentsBeforeExitingAndDividerKeepsNeighbours() async throws {
        let document = NativeDocument(blocks: [.init(kind: .ordered, runs: [.init(text: "第七项")], indentLevel: 1, listStart: 7)])
        let (model, view, _) = try await fixture(document: document)
        try MilkdownTestSupport.command(view, "focusEnd")
        let enter = "document.querySelector('.ProseMirror').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}))"
        try MilkdownTestSupport.script(view, enter); await view.flush()
        XCTAssertEqual(model.document.blocks.map(\.indentLevel), [1, 1])
        XCTAssertEqual(try MilkdownTestSupport.script(view, "Array.from(document.querySelectorAll('.wf-ordered .wf-marker')).map(n=>n.textContent)") as? [String], ["7.", "8."])
        try MilkdownTestSupport.script(view, enter); await view.flush()
        XCTAssertEqual(model.document.blocks.last?.indentLevel, 0)
        XCTAssertEqual(model.document.blocks.last?.kind, .ordered)
        try MilkdownTestSupport.script(view, enter); await view.flush()
        XCTAssertEqual(model.document.blocks.last?.kind, .paragraph)
        try MilkdownTestSupport.command(view, "insertDivider"); await view.flush()
        XCTAssertTrue(model.document.blocks.contains { $0.kind == .divider })
        XCTAssertEqual(model.document.blocks[0], document.blocks[0])
    }

    func testExternalReminderUpdatePreservesBodyUndoAndRedo() async throws {
        let original = NativeDocument(blocks: [.init(kind: .checklist(false), runs: [.init(text: "原文")])])
        let (model, view, _) = try await fixture(document: original)
        try MilkdownTestSupport.command(view, "focusEnd")
        let client = try MilkdownTestSupport.inputClient(view)
        client.insertText("补充", replacementRange: NSRange(location: NSNotFound, length: 0))
        await view.flush()
        try await wait("输入尚未提交") { model.document.plainText == "原文补充" }
        var updated = model.document
        let reminder = Date(timeIntervalSinceReferenceDate: 9000)
        updated.blocks[0].checklist = .init(reminderAt: reminder)
        model.document = updated
        try await wait("外部更新未载入") { view.isDocumentReady && view.document == updated }
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertEqual(model.document.plainText, "原文")
        XCTAssertEqual(model.document.blocks[0].checklist?.reminderAt, reminder)
        try MilkdownTestSupport.command(view, "redo"); await view.flush()
        XCTAssertEqual(model.document.plainText, "原文补充")
        XCTAssertEqual(model.document.blocks[0].checklist?.reminderAt, reminder)
        model.id = UUID(); model.document = NativeDocument(plainText: "另一篇")
        try await wait("新文档未载入") { view.isDocumentReady && view.documentIdentity == model.id }
        XCTAssertEqual(try MilkdownTestSupport.command(view, "undo") as? Bool, false)
    }

    func testHostTransactionUndoAfterRapidTypingAndExternalMetadataUsesInverse() async throws {
        let (model, view, _) = try await fixture()
        let original = model.document
        var linked = false
        try MilkdownTestSupport.command(view, "focusEnd")
        XCTAssertTrue(model.handle.insertReference(.init(title: "关联笔记", target: "workfollow://note/test"),
            commit: { model.document = $0; linked = true }, undoCommit: { model.document = $0; linked = false }))
        try await wait("关联未提交") { linked }
        let client = try MilkdownTestSupport.inputClient(view)
        client.insertText("续写", replacementRange: NSRange(location: NSNotFound, length: 0))
        await view.flush()
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertTrue(linked); XCTAssertTrue(model.document.plainText.hasSuffix("关联笔记"))
        var updated = model.document; updated.blocks[0].align = .right
        model.document = updated
        try await wait("段落属性未载入") { view.isDocumentReady && view.document == updated }
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertFalse(linked); XCTAssertEqual(model.document.plainText, original.plainText)
        XCTAssertEqual(model.document.blocks[0].align, .right)
        try MilkdownTestSupport.command(view, "redo"); await view.flush()
        XCTAssertTrue(linked)
        client.insertText("再次续写", replacementRange: NSRange(location: NSNotFound, length: 0))
        await view.flush()
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertTrue(linked); XCTAssertTrue(model.document.plainText.hasSuffix("关联笔记"))
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertFalse(linked)
    }

    func testFocusedFormulaUndoAndRedoSynchronizeInputAndPreview() async throws {
        let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", formula: .init(latex: "x"))])])
        let (model, view, _) = try await fixture(document: document)
        try MilkdownTestSupport.script(view, "(() => { const f=document.querySelector('.wf-embed input'); f.focus(); f.value='x^2'; f.setSelectionRange(3,3); f.dispatchEvent(new Event('input',{bubbles:true})); })()")
        await view.flush()
        try MilkdownTestSupport.command(view, "undo"); await view.flush()
        XCTAssertEqual(model.document.blocks[0].runs[0].formula?.latex, "x")
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').value") as? String, "x")
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.activeElement===document.querySelector('.wf-embed input')") as? Bool, true)
        try MilkdownTestSupport.command(view, "redo"); await view.flush()
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').value") as? String, "x^2")
        try MilkdownTestSupport.script(view, "(() => { const f=document.querySelector('.wf-embed input'); f.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true})); f.value='组合中'; window.workfollowEditor.command('undo'); })()")
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').value") as? String, "组合中")
        try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true}))")
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').value") as? String, "x")
    }

    func testSpellingPreferenceUpdatesExistingAndNewEditors() async throws {
        let previous = UserDefaults.standard.object(forKey: EditorPreferences.spellCheckingKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: EditorPreferences.spellCheckingKey) }
            else { UserDefaults.standard.removeObject(forKey: EditorPreferences.spellCheckingKey) }
            NotificationCenter.default.post(name: EditorPreferences.spellCheckingDidChange, object: nil)
        }
        EditorPreferences.setSpellCheckingEnabled(false)
        let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", table: .empty()), .init(text: "\u{fffc}", formula: .init(latex: "x"))])])
        let (_, view, _) = try await fixture(document: document)
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').spellcheck") as? Bool, false)
        EditorPreferences.setSpellCheckingEnabled(true)
        try await wait("拼写设置未刷新") { (try? MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').spellcheck")) as? Bool == true }
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('textarea').spellcheck") as? Bool, true)
        XCTAssertEqual(try MilkdownTestSupport.script(view, "document.querySelector('.wf-embed input').spellcheck") as? Bool, false)
        let (_, next, _) = try await fixture()
        XCTAssertEqual(try MilkdownTestSupport.script(next, "document.querySelector('.ProseMirror').spellcheck") as? Bool, true)
        EditorPreferences.setSpellCheckingEnabled(false)
        try await wait("关闭拼写设置未刷新") { (try? MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').spellcheck")) as? Bool == false }
    }

    func testSlashMenuEscapesShortBodyBoundsAndKeepsItsCommandsAndKeyboardSelection() async throws {
        let model = Model(); model.document = .empty
        let host = NSHostingView(rootView: ScrollView { Host(model: model, growing: true) }.frame(width: 720, height: 400))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 400)
        defer { window.contentView = nil; window.close() }
        let view = try await MilkdownTestSupport.editorAsync(in: host)
        try MilkdownTestSupport.command(view, "insertText", ["text": "/"])
        try await wait("斜杠菜单没有出现") { view.menuPanel?.isVisible == true }
        let panel = try XCTUnwrap(view.menuPanel)
        XCTAssertTrue(panel.parent === window)
        XCTAssertGreaterThan(panel.frame.height, view.frame.height + 100, "菜单高度应独立于短正文，不被 WebKit 底边裁掉")
        XCTAssertTrue(EditorPopupGeometry.bounds(in: window).contains(panel.frame))
        let packet = try XCTUnwrap(MilkdownTestSupport.call(view, "getMenu") as? [String: Any])
        let items = try XCTUnwrap(packet["items"] as? [[String: Any]])
        XCTAssertTrue(items.contains { $0["id"] as? String == "shared.drawio" })
        let before = try XCTUnwrap(packet["selected"] as? Int)
        try MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowDown',bubbles:true,cancelable:true}))")
        let moved = try XCTUnwrap(MilkdownTestSupport.call(view, "getMenu") as? [String: Any])
        XCTAssertEqual(moved["selected"] as? Int, (before + 1) % items.count)
        try MilkdownTestSupport.chooseMenu(view, title: "二级标题")
        await view.flush()
        XCTAssertEqual(model.document.blocks[0].kind, .heading(2))
        XCTAssertEqual(model.document.plainText, "")
        XCTAssertNil(view.menuPanel)
    }

    func testAtMentionCompletesAndInsertsLinkedRun() async throws {
        let taskID = UUID(), noteID = UUID()
        var profile = DocumentProfile()
        profile.mentionCandidates = { [
            DocumentMention(id: taskID, kind: .task, title: "核对成本"),
            DocumentMention(id: noteID, kind: .note, title: "评审纪要"),
        ] }
        let (model, view, _) = try await fixture(document: .empty, profile: profile)
        try MilkdownTestSupport.command(view, "insertText", ["text": "@核"])
        try await wait("提及浮层没有出现") { view.menuPanel?.isVisible == true }
        try MilkdownTestSupport.chooseMenu(view, title: "核对成本")
        await view.flush()
        XCTAssertEqual(model.document.plainText, "@核对成本 ")
        let linked = try XCTUnwrap(model.document.blocks[0].runs.first { !$0.marks.isEmpty })
        XCTAssertEqual(linked.text, "@核对成本", "链接只覆盖触发符与标题，尾随空格不着链")
        XCTAssertEqual(linked.marks.first, .link("workfollow://task/\(taskID.uuidString)"))
        // 候选过滤后无命中则不出浮层
        try MilkdownTestSupport.command(view, "insertText", ["text": "@不存在"])
        try await wait("查询无命中时浮层应保持关闭") { view.menuPanel?.isVisible != true }
    }

    func testIncrementalCommitMergesChangedBlockAndPreservesSiblings() async throws {
        let first = UUID(), second = UUID(), third = UUID()
        let document = NativeDocument(blocks: [
            DocumentBlock(id: first, kind: .paragraph, runs: [DocumentRun(text: "首块")]),
            DocumentBlock(id: second, kind: .paragraph, runs: [DocumentRun(text: "中间")]),
            DocumentBlock(id: third, kind: .quote, runs: [DocumentRun(text: "尾块")]),
        ])
        let (model, view, _) = try await fixture(document: document)
        // 光标放进中间块末尾（块1 占 0..4，块2 文字在 5..7）后输入一个字
        try MilkdownTestSupport.command(view, "select", ["from": 7])
        try MilkdownTestSupport.command(view, "insertText", ["text": "改"])
        await view.flush()
        XCTAssertEqual(model.document.plainText, "首块\n中间改\n尾块")
        XCTAssertEqual(model.document.blocks.map(\.id), [first, second, third], "兄弟块身份从缓存原样恢复")
        XCTAssertEqual(model.document.blocks[1].runs.first?.text, "中间改")
    }

    /// 增量序列化契约：未改动块靠节点身份命中缓存，编辑一个块只重新序列化这一个块。
    func testIncrementalSerializationOnlyTouchesEditedBlock() async throws {
        let document = NativeDocument(plainText: "首块\n中间\n尾块")
        let (model, view, _) = try await fixture(document: document)
        _ = try await view.call("getDoc") // 预热：首次全量序列化进缓存
        try MilkdownTestSupport.command(view, "select", ["from": 7]) // 光标进中间块，选区快照也走按块缓存
        let baseline = try XCTUnwrap(MilkdownTestSupport.script(view, "window.workfollowEditor.serializeCount()") as? Int)
        try MilkdownTestSupport.command(view, "insertText", ["text": "改"])
        await view.flush()
        XCTAssertEqual(model.document.plainText, "首块\n中间改\n尾块")
        let delta = (try XCTUnwrap(MilkdownTestSupport.script(view, "window.workfollowEditor.serializeCount()") as? Int)) - baseline
        XCTAssertEqual(delta, 1, "编辑一个块只应重新序列化这一个块，实际 \(delta)")
    }

    /// 搜索走按块缓存的 plainText：块被编辑后缓存必须失效，命中位置按新文本算。
    func testSearchLocatesEditedPlainTextAcrossBlocks() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "第一段甲\n第二段乙丙\n第三段丁"))
        _ = try await view.call("getDoc")
        XCTAssertEqual(try MilkdownTestSupport.command(view, "search", ["query": "乙丙"]) as? Bool, true)
        XCTAssertEqual(try MilkdownTestSupport.range(view), NSRange(location: 8, length: 2))
        try MilkdownTestSupport.select(view, NSRange(location: 10, length: 0))
        try MilkdownTestSupport.command(view, "insertText", ["text": "插"])
        await view.flush()
        XCTAssertEqual(model.document.plainText, "第一段甲\n第二段乙丙插\n第三段丁")
        XCTAssertEqual(try MilkdownTestSupport.command(view, "search", ["query": "乙丙插"]) as? Bool, true)
        XCTAssertEqual(try MilkdownTestSupport.range(view), NSRange(location: 8, length: 3))
    }

    /// 行内日期用视图层装饰标记，不写进文档模型。
    func testInlineDatePhrasesAreDecoratedWithoutChangingDocument() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "周五前提交方案\n明天上午同步"))
        try await wait("行内日期没有被标记") {
            (try? MilkdownTestSupport.script(view, "document.querySelectorAll('.wf-inline-date').length")) as? Int == 2
        }
        let texts = try XCTUnwrap(MilkdownTestSupport.script(view,
            "Array.from(document.querySelectorAll('.wf-inline-date')).map(n=>n.textContent)") as? [String])
        XCTAssertEqual(texts, ["周五前", "明天"])
        XCTAssertEqual(model.document.plainText, "周五前提交方案\n明天上午同步")
    }

    /// ghost text 只在光标锚点显示，Tab 采纳后写进文档且不再残留。
    func testGhostTextDisplaysAtCaretAndTabAdoptsIt() async throws {
        let (model, view, _) = try await fixture(document: NativeDocument(plainText: "这是一段足够长的正文内容"))
        try MilkdownTestSupport.command(view, "focusEnd")
        let state = try XCTUnwrap(MilkdownTestSupport.script(view, "window.workfollowEditor.ghostState()") as? [String: Any])
        let request = try XCTUnwrap(state["request"] as? Int), anchor = try XCTUnwrap(state["anchor"] as? Int)
        let documentID = try XCTUnwrap(state["documentID"] as? String), epoch = try XCTUnwrap(state["epoch"] as? String)
        let payload: [String: Any] = ["text": "，再补一句", "documentID": documentID, "epoch": epoch,
                                      "anchor": anchor, "request": request]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        XCTAssertEqual(try MilkdownTestSupport.script(view, "window.workfollowEditor.applyGhost(\(json))") as? Bool, true)
        try await wait("ghost text 没有出现") {
            (try? MilkdownTestSupport.script(view, "document.querySelector('.wf-ghost')?.textContent")) as? String == "，再补一句"
        }
        try MilkdownTestSupport.script(view, "document.querySelector('.ProseMirror').dispatchEvent(new KeyboardEvent('keydown',{key:'Tab',bubbles:true,cancelable:true}))")
        await view.flush()
        XCTAssertEqual(model.document.plainText, "这是一段足够长的正文内容，再补一句")
        // querySelector 未命中返回 JS null（过桥是 NSNull 而非 nil），改用显式回退值断言。
        XCTAssertNil(try MilkdownTestSupport.script(view, "document.querySelector('.wf-ghost')?.textContent ?? null") as? String,
                     "Tab 采纳后 ghost 不应残留")
    }
}
