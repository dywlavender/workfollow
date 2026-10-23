import AppKit
import WebKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentDiagramTests: XCTestCase {
    static let drawingXML = """
    <mxfile host="WorkFollow"><diagram name="流程"><mxGraphModel grid="1" page="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/><mxCell id="step" value="需求评审" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1"><mxGeometry x="40" y="40" width="160" height="70" as="geometry"/></mxCell></root></mxGraphModel></diagram></mxfile>
    """

    private func diagram(title: String = "交付流程") throws -> NativeDiagram {
        let image = NSImage(size: NSSize(width: 320, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 320, height: 160).fill()
        NSColor.systemBlue.setFill(); NSRect(x: 20, y: 20, width: 140, height: 80).fill()
        image.unlockFocus()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return NativeDiagram(title: title, xml: Self.drawingXML,
                             previewPNG: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
    }

    func testDiagramSourcePreviewAndIDRoundTripInNativeDocument() throws {
        let diagram = try diagram()
        let original = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "\u{FFFC}", diagram: diagram)
        ])])
        let decoded = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        let rendered = DocumentTextCodec.render(decoded)
        XCTAssertTrue((rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell is DocumentDiagramCell)
        let fromTextKit = DocumentTextCodec.decode(rendered, preserving: decoded)
        XCTAssertEqual(fromTextKit, original)
        XCTAssertEqual(fromTextKit.blocks[0].runs[0].diagram?.xml, Self.drawingXML)
    }

    func testOlderDocumentWithoutDiagramFieldStillDecodes() throws {
        let old = """
        {"blocks":[{"id":"00000000-0000-0000-0000-000000000001","kind":{"paragraph":{}},"runs":[{"text":"原有正文","marks":[]}]}]}
        """
        let document = try JSONDecoder().decode(NativeDocument.self, from: Data(old.utf8))
        XCTAssertEqual(document.plainText, "原有正文")
        XCTAssertNil(document.blocks[0].runs[0].diagram)
    }

    func testSourceAndPreviewSurviveSQLiteAndDeferredDocumentLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drawio-persistence-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "图表持久化", in: .inbox).taskID)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "\u{FFFC}", diagram: try diagram())
        ])])
        _ = workspace.setDocument(id, document)
        let repository = NativePreviewRepository(directory: directory)
        try repository.save(NativeWorkspaceSnapshot(tasks: workspace.allTasks, notes: []))
        let reloaded = try XCTUnwrap(repository.loadDeferred()?.tasks.first { $0.id == id })
        XCTAssertFalse(reloaded.document.isLoaded)
        XCTAssertEqual(try reloaded.document.materialized(), document)
    }

    func testInsertAndEditHaveCompleteUndoRedoIncludingPreview() throws {
        let original = NativeDocument(plainText: "说明")
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 500), textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        var latest = original
        let coordinator = DocumentEditorCoordinator(documentID: editor.documentIdentity, document: original,
            onDocumentChange: { latest = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        defer { withExtendedLifetime(coordinator) {} }
        let first = try diagram()
        XCTAssertTrue(editor.saveDiagram(first, replacing: NSRange(location: 2, length: 0), existingID: nil))
        XCTAssertEqual(latest.blocks.count, 3)
        XCTAssertEqual(latest.blocks[1].runs[0].diagram, first)
        XCTAssertEqual(latest.blocks[0].plainText, "说明")
        editor.undo(nil)
        XCTAssertEqual(latest.plainText, "说明")
        editor.redo(nil)
        XCTAssertEqual(latest.blocks[1].runs[0].diagram, first)
        var edited = first
        edited.title = "更新流程"; edited.xml = Self.drawingXML.replacingOccurrences(of: "需求评审", with: "验收")
        XCTAssertTrue(editor.saveDiagram(edited, replacing: NSRange(location: 0, length: 0), existingID: first.id))
        XCTAssertEqual(latest.blocks[1].runs[0].diagram, edited)
        editor.undo(nil)
        XCTAssertEqual(latest.blocks[1].runs[0].diagram, first)
        editor.redo(nil)
        XCTAssertEqual(latest.blocks[1].runs[0].diagram, edited)
    }

    func testPreviewFitsNarrowInspector() throws {
        let cell = DocumentDiagramCell(diagram: try diagram())
        let container = NSTextContainer(containerSize: NSSize(width: 288, height: 1000))
        let frame = cell.cellFrame(for: container, proposedLineFragment: NSRect(x: 20, y: 0, width: 268, height: 20),
                                   glyphPosition: .zero, characterIndex: 0)
        XCTAssertLessThanOrEqual(frame.width, 268)
        XCTAssertGreaterThan(frame.height, 90)
    }

    func testRepeatedSaveOfNewDrawingUpdatesSameAttachmentAndKeepsSurroundingText() async throws {
        let original = NativeDocument(plainText: "前文\n\n后文")
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        var latest = original
        let coordinator = DocumentEditorCoordinator(documentID: editor.documentIdentity, document: original,
            onDocumentChange: { latest = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        defer { withExtendedLifetime(coordinator) {} }
        var drawing = try diagram()
        let insertion = NSRange(location: 3, length: 0)
        XCTAssertTrue(editor.saveDiagram(drawing, replacing: insertion, existingID: nil))
        try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        let insertedText = editor.string
        for label in ["第二次保存", "第三次保存"] {
            drawing.xml = Self.drawingXML.replacingOccurrences(of: "需求评审", with: label)
            XCTAssertTrue(editor.saveDiagram(drawing, replacing: insertion, existingID: nil))
            XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram), [drawing])
            XCTAssertEqual(editor.string, insertedText, "连续保存不能再插入图表或额外换行")
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(editor.saveDiagram(drawing, replacing: insertion, existingID: nil))
        editor.undo(nil)
        let previous = try XCTUnwrap(latest.blocks.flatMap(\.runs).compactMap(\.diagram).first)
        XCTAssertTrue(previous.xml.contains("第二次保存"))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram).count, 1)
        editor.redo(nil)
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram), [drawing])
    }

    func testActualDrawioRepeatedSaveAndFinalSaveKeepOneDiagramInTaskInspector() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drawio-repeat-save-" + UUID().uuidString)
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let taskID = try XCTUnwrap(seed.createTask(title: "连续保存验收", in: .inbox).taskID)
        try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        let workspace = environment.taskWorkspace
        workspace.select(taskID)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, environment: environment)
        let parent = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { parent.close(); try? FileManager.default.removeItem(at: directory) }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTextView }.first)
        editor.insertDocumentDiagram(at: 0)
        let controller = try XCTUnwrap(editor.diagramEditor)
        defer { controller.close() }
        try await waitUntil(seconds: 25) { controller.isReady || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        var savedID: UUID?
        for label in ["第一次保存", "第二次保存", "第三次保存"] {
            let xml = Self.drawingXML.replacingOccurrences(of: "需求评审", with: label)
            controller.send(["action": "load", "xml": xml, "autosave": 1])
            try await _Concurrency.Task.sleep(nanoseconds: 400_000_000)
            // The actual vendor Save action emits the same event as its save shortcut.
            controller.send(["action": "invokeAction", "actionName": "save"])
            try await waitUntil(seconds: 25) {
                workspace.task(for: taskID)?.document.blocks.flatMap(\.runs).compactMap(\.diagram)
                    .contains { $0.xml.contains(label) } == true || controller.lastError != nil
            }
            XCTAssertNil(controller.lastError)
            let drawings = try XCTUnwrap(workspace.task(for: taskID)?.document).blocks.flatMap(\.runs).compactMap(\.diagram)
            XCTAssertEqual(drawings.count, 1, "同一绘图窗口每次保存只能更新当前图表")
            XCTAssertTrue(drawings.first?.xml.contains(label) == true)
            if let savedID { XCTAssertEqual(drawings.first?.id, savedID) }
            else { savedID = drawings.first?.id }
            XCTAssertNotNil(editor.diagramEditor, "绘图中的保存应保留当前编辑窗口")
        }
        let save = try XCTUnwrap(button(named: "保存并关闭", in: try XCTUnwrap(controller.window?.contentView)))
        save.performClick(nil)
        try await waitUntil(seconds: 25) { editor.diagramEditor == nil || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        let drawings = try XCTUnwrap(workspace.task(for: taskID)?.document).blocks.flatMap(\.runs).compactMap(\.diagram)
        XCTAssertEqual(drawings.count, 1)
        XCTAssertEqual(drawings.first?.id, savedID)
        XCTAssertTrue(drawings.first?.xml.contains("第三次保存") == true)
    }

    func testNextSaveConsolidatesEarlierDuplicateIDsAndUndoRestoresTheirVersions() throws {
        let first = try diagram()
        var second = first
        second.xml = Self.drawingXML.replacingOccurrences(of: "需求评审", with: "第二版")
        var third = second
        third.xml = Self.drawingXML.replacingOccurrences(of: "需求评审", with: "第三版")
        let independent = try diagram(title: "独立复制的图")
        func block(_ drawing: NativeDiagram) -> DocumentBlock {
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", diagram: drawing)])
        }
        let original = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "前文")]), block(first),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "保留中间文字")]),
            block(second), block(third), block(independent),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "后文")])
        ])
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
        var latest = original
        let coordinator = DocumentEditorCoordinator(documentID: editor.documentIdentity, document: original,
            onDocumentChange: { latest = $0 }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        defer { withExtendedLifetime(coordinator) {} }
        XCTAssertTrue(editor.saveDiagram(third, replacing: .init(location: 0, length: 0), existingID: third.id))
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram), [third, independent])
        XCTAssertEqual(latest.plainText, "前文\n\u{FFFC}\n保留中间文字\n\u{FFFC}\n后文")
        editor.undo(nil)
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram), [first, second, third, independent])
        XCTAssertEqual(latest.plainText, original.plainText)
        editor.redo(nil)
        XCTAssertEqual(latest.blocks.flatMap(\.runs).compactMap(\.diagram), [third, independent])
    }

    func testCopyPasteKeepsEditableSourceAndCreatesIndependentDrawing() throws {
        let original = try diagram()
        let source = NativeTextView(frame: .zero, textContainer: nil)
        source.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", diagram: original)])
        ])))
        source.setSelectedRange(NSRange(location: 0, length: 1))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(source.copyDiagramContent(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "[流程图：交付流程]")
        let destination = NativeTextView(frame: .zero, textContainer: nil)
        XCTAssertTrue(destination.pasteDiagramContent(from: pasteboard))
        let copied = try XCTUnwrap(destination.diagram(at: 0))
        XCTAssertNotEqual(copied.id, original.id)
        XCTAssertEqual(copied.xml, original.xml)
        XCTAssertEqual(copied.previewPNG, original.previewPNG)
    }

    func testDrawioCommandsAvailableInTaskNoteAndGenericEditor() {
        for profile in [DocumentProfile(), DocumentProfile(taskSlash: true), DocumentProfile(noteSlash: true)] {
            XCTAssertEqual(profile.slashCommands.filter { $0.id == "shared.drawio" }.count, 1)
            XCTAssertTrue(profile.slashCommands.first { $0.id == "shared.drawio" }?.keywords.contains("drawio") == true)
        }
    }

    func testOfflineResourcesLoadAndNativeSaveProducesEditableSourceAndPNG() async throws {
        let parent = InspectorPanelTestSupport.ownerWindow(for: NSView(), width: 1100, height: 780)
        var saved: NativeDiagram?
        var closed = false
        let controller = DrawioEditorWindowController(diagram: nil, onSave: { saved = $0; return true }, onClose: { closed = true })
        defer { controller.close(); parent.close() }
        controller.present(asSheetOf: parent)
        try await waitUntil(seconds: 35) { controller.isReady || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        guard controller.isReady else { XCTFail("Real bundled draw.io did not initialize"); return }
        XCTAssertEqual(controller.webView.url?.scheme, DrawioSchemeHandler.scheme)
        controller.send(["action": "load", "xml": Self.drawingXML, "autosave": 1])
        try await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
        let canvas: NSImage = try await withCheckedThrowingContinuation { continuation in
            controller.webView.takeSnapshot(with: nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? NSError(domain: "DrawioSnapshot", code: 1)) }
            }
        }
        try writePNG(canvas, to: "/private/tmp/workfollow-drawio-20261023-canvas.png")
        let saveButton = try XCTUnwrap(button(named: "保存并关闭", in: try XCTUnwrap(controller.window?.contentView)))
        saveButton.performClick(nil)
        try await waitUntil(seconds: 25) { saved != nil || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        let drawing = try XCTUnwrap(saved)
        XCTAssertNotNil(NSImage(data: drawing.previewPNG))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(NSBitmapImageRep(data: drawing.previewPNG)).pixelsWide, 880)
        try drawing.previewPNG.write(to: URL(fileURLWithPath: "/private/tmp/workfollow-drawio-20261023-export.png"))
        XCTAssertTrue(drawing.xml.contains("需求评审"))
        XCTAssertTrue(closed)
        // Reopen the actual persisted result with the same diagram identity.
        var reopened: NativeDiagram?
        let again = DrawioEditorWindowController(diagram: drawing, onSave: { reopened = $0; return true }, onClose: {})
        defer { again.close() }
        again.present(asSheetOf: parent)
        try await waitUntil(seconds: 25) { again.isReady || again.lastError != nil }
        XCTAssertNil(again.lastError)
        let saveAgain = try XCTUnwrap(button(named: "保存并关闭", in: try XCTUnwrap(again.window?.contentView)))
        saveAgain.performClick(nil)
        try await waitUntil(seconds: 25) { reopened != nil || again.lastError != nil }
        XCTAssertEqual(reopened?.id, drawing.id)
        XCTAssertTrue(reopened?.xml.contains("需求评审") == true)
    }

    func testCancellingBlankDrawingDoesNotInsertContent() async throws {
        let parent = InspectorPanelTestSupport.ownerWindow(for: NSView(), width: 1100, height: 780)
        var saved = false
        var closed = false
        let controller = DrawioEditorWindowController(diagram: nil, onSave: { _ in saved = true; return true }, onClose: { closed = true })
        defer { controller.close(); parent.close() }
        controller.present(asSheetOf: parent)
        try await waitUntil(seconds: 25) { controller.isReady || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        let cancel = try XCTUnwrap(button(named: "取消", in: try XCTUnwrap(controller.window?.contentView)))
        cancel.performClick(nil)
        XCTAssertTrue(closed)
        XCTAssertFalse(saved)
    }

    func testTaskInspectorSlashSaveAndDoubleClickReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("drawio-inspector-" + UUID().uuidString)
        let seed = TaskWorkspaceModel(seedDemoData: false)
        let taskID = try XCTUnwrap(seed.createTask(title: "流程图入口验收", in: .inbox).taskID)
        try NativePreviewRepository(directory: directory).save(NativeWorkspaceSnapshot(tasks: seed.allTasks, notes: []))
        let environment = AppEnvironment(directory: directory)
        environment.focusStore.notifier = nil
        let workspace = environment.taskWorkspace
        workspace.select(taskID)
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace, width: 390, height: 700, environment: environment)
        let parent = InspectorPanelTestSupport.ownerWindow(for: host, width: 390, height: 700)
        defer { parent.close(); try? FileManager.default.removeItem(at: directory) }
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? NativeTextView }.first)
        parent.makeFirstResponder(editor)
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertNotNil(editor.slashSession)
        let index = try XCTUnwrap(editor.profile.slashCommands.firstIndex { $0.id == "shared.drawio" })
        editor.executeSlash(at: index)
        let controller = try XCTUnwrap(editor.diagramEditor)
        defer { controller.close(); editor.diagramEditor?.close() }
        try await waitUntil(seconds: 25) { controller.isReady || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        controller.send(["action": "load", "xml": Self.drawingXML, "autosave": 1])
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        let save = try XCTUnwrap(button(named: "保存并关闭", in: try XCTUnwrap(controller.window?.contentView)))
        save.performClick(nil)
        try await waitUntil(seconds: 25) { editor.diagramEditor == nil || controller.lastError != nil }
        XCTAssertNil(controller.lastError)
        let document = try XCTUnwrap(workspace.task(for: taskID)?.document)
        let saved = try XCTUnwrap(document.blocks.flatMap(\.runs).compactMap(\.diagram).first)
        XCTAssertEqual(workspace.selectedTaskID, taskID)
        XCTAssertFalse(editor.string.contains("/"))
        XCTAssertEqual(saved.xml.contains("需求评审"), true)
        InspectorPanelTestSupport.settle(parent)
        let frame = try XCTUnwrap(editor.viewRect(forCharacterAt: 0))
        XCTAssertLessThanOrEqual(frame.maxX, editor.bounds.width, "实际 TextKit 排版里的预览不得溢出窄任务栏")
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/workfollow-drawio-20261023-preview.png"))
        }
        let point = editor.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
        func click(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: parent.windowNumber,
                context: nil, eventNumber: 100, clickCount: 2, pressure: type == .leftMouseDown ? 1 : 0))
        }
        NSApp.postEvent(try click(.leftMouseUp), atStart: true)
        NSApp.sendEvent(try click(.leftMouseDown))
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(up) }
        try await waitUntil(seconds: 5) { editor.diagramEditor != nil }
        let reopened = try XCTUnwrap(editor.diagramEditor)
        reopened.close()
        editor.undo(nil)
        XCTAssertFalse(workspace.task(for: taskID)?.document.blocks.flatMap(\.runs).contains { $0.diagram != nil } == true)
        editor.redo(nil)
        XCTAssertEqual(workspace.task(for: taskID)?.document.blocks.flatMap(\.runs).compactMap(\.diagram).first, saved)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func writePNG(_ image: NSImage, to path: String) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }

    private func waitUntil(seconds: TimeInterval, condition: () -> Bool) async throws {
        let until = Date().addingTimeInterval(seconds)
        while !condition(), Date() < until { try await _Concurrency.Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for the real drawing editor")
    }

    private func button(named title: String, in root: NSView) -> NSButton? {
        if let button = root as? NSButton, button.title == title { return button }
        for child in root.subviews { if let result = button(named: title, in: child) { return result } }
        return nil
    }
}
