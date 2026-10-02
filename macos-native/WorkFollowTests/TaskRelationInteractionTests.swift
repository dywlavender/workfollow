import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class TaskRelationInteractionTests: XCTestCase {
    func testWindowEditorUndoRedoRestoresDocumentAndSourceTogether() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        let original = NativeDocument(plainText: "原有正文 ")
        _ = workspace.setDocument(source, original)
        workspace.select(source)
        let note = Note(id: UUID(), title: "关联笔记", document: .empty, folder: "资料", updatedAt: Date())
        let handle = DocumentEditorHandle()
        let host = NSHostingView(rootView: DocumentEditor(documentID: source, document: original,
            onDocumentChange: { _ = workspace.setDocument(source, $0) },
            onEscape: { .keepInspector }, onEditingChanged: { _ in }, handle: handle)
            .frame(width: 360, height: 180).background(Color.white))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let editor = try XCTUnwrap(handle.textView)
        editor.setSelectedRange(NSRange(location: editor.attributedString().length, length: 0))
        XCTAssertTrue(TaskRelationSelection.apply(.note(note), sourceTaskID: source,
            workspace: workspace, notes: [note], handle: handle))
        XCTAssertTrue(window.firstResponder === editor)
        let linked = try XCTUnwrap(workspace.task(for: source)?.document)
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, note.id)
        XCTAssertTrue(NSApp.sendAction(#selector(NativeTextView.undo(_:)), to: window.firstResponder, from: nil))
        XCTAssertEqual(workspace.task(for: source)?.document, original)
        XCTAssertNil(workspace.task(for: source)?.sourceNoteID)
        XCTAssertTrue(NSApp.sendAction(#selector(NativeTextView.redo(_:)), to: window.firstResponder, from: nil))
        XCTAssertEqual(workspace.task(for: source)?.document, linked)
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, note.id)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_relation_undo_redo.png"))
    }

    func testMixedPickerClickInsertsTaskReferenceWithoutChangingParentOrSourceNote() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源任务", in: .inbox).taskID)
        let target = try XCTUnwrap(workspace.createTask(title: "目标任务", in: .inbox).taskID)
        let originalNote = UUID()
        workspace.setSourceNote(source, originalNote)
        workspace.select(source)
        let note = Note(id: UUID(), title: "目标笔记", document: .empty, folder: "资料", updatedAt: Date())
        let handle = DocumentEditorHandle()
        var frames: [TaskRelationPickerAnchor: CGRect] = [:]
        var dismissed = false
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            DocumentEditor(documentID: source, document: .empty,
                onDocumentChange: { _ = workspace.setDocument(source, $0) },
                onEscape: { .keepInspector }, onEditingChanged: { _ in }, handle: handle)
                .frame(width: 320, height: 100)
            TaskRelationPicker(sourceTaskID: source, tasks: workspace.allTasks, notes: [note], sourceNoteID: originalNote,
                onSelect: { target in
                    let applied = TaskRelationSelection.apply(target, sourceTaskID: source, workspace: workspace, notes: [note], handle: handle)
                    dismissed = applied
                    return applied
                }, onCancel: { dismissed = true })
        }.onPreferenceChange(TaskRelationPickerFrames.self) { frames = $0 })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let targetID = TaskRelationTarget.task(try XCTUnwrap(workspace.task(for: target))).id
        let row = try XCTUnwrap(frames[.target(targetID)])
        XCTAssertNotNil(frames[.target(TaskRelationTarget.note(note).id)])
        XCTAssertEqual(try XCTUnwrap(frames[.panel]).size, CGSize(width: 320, height: 300))
        let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
            CGWindowID(window.windowNumber), [.bestResolution]))
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/render_task_relation_picker.png"))
        // Picker coordinates are local; the document occupies the preceding 100pt.
        let point = host.convert(NSPoint(x: row.midX, y: host.isFlipped ? row.midY + 100 : host.bounds.height - row.midY - 100), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertTrue(dismissed)
        let document = try XCTUnwrap(workspace.task(for: source)?.document)
        let url = NativeResourceLink.task(target).url.absoluteString
        XCTAssertTrue(document.blocks.flatMap(\.runs).contains { $0.marks.contains(.link(url)) })
        XCTAssertNil(workspace.task(for: source)?.parentID)
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, originalNote)
        let notes = NotesWorkspaceModel(initialNotes: [note], folders: [])
        let navigation = AppNavigation()
        XCTAssertTrue(NativeResourceLinkRouter.open(try XCTUnwrap(NativeResourceLink(url: try XCTUnwrap(URL(string: url)))),
            tasks: workspace, notes: notes, navigation: navigation))
        XCTAssertEqual(workspace.selectedTaskID, target)
    }

    func testNoteReferenceKeepsLegacySourceAndUnavailableEditorCannotMutateTask() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let source = try XCTUnwrap(workspace.createTask(title: "来源", in: .inbox).taskID)
        workspace.select(source)
        let note = Note(id: UUID(), title: "笔记", document: .empty, folder: "", updatedAt: Date())
        let handle = DocumentEditorHandle()
        let before = workspace.task(for: source)
        XCTAssertFalse(TaskRelationSelection.apply(.note(note), sourceTaskID: source, workspace: workspace, notes: [note], handle: handle))
        XCTAssertEqual(workspace.task(for: source), before)
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.documentIdentity = source
        let coordinator = DocumentEditorCoordinator(documentID: source, document: .empty,
            onDocumentChange: { _ = workspace.setDocument(source, $0) }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        handle.textView = editor
        XCTAssertTrue(TaskRelationSelection.apply(.note(note), sourceTaskID: source, workspace: workspace, notes: [note], handle: handle))
        XCTAssertEqual(workspace.task(for: source)?.sourceNoteID, note.id)
        XCTAssertTrue(try XCTUnwrap(workspace.task(for: source)?.document).blocks.flatMap(\.runs)
            .contains { $0.marks.contains(.link(NativeResourceLink.note(note.id).url.absoluteString)) })
        // Cancellation is presentation-only; it must never call the selection action.
        let after = workspace.task(for: source)
        var state = TaskInspectorActionPresentationState()
        state.open(.relation)
        XCTAssertTrue(state.handleEscape())
        XCTAssertEqual(workspace.task(for: source), after)
    }
}
