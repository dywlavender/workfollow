import XCTest
import AppKit
import SwiftUI
@testable import WorkFollow

@MainActor
final class DocumentProfileTests: XCTestCase {
    func testTaskHostProfileRoutesOnlyAvailableBusinessActions() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let childID = try XCTUnwrap(workspace.createChild(parentID, title: "子任务").taskID)
        var invoked: [String] = []
        let host = TaskEditorHostActions(createChild: { invoked.append("child") },
                                        openTags: { invoked.append("tags") },
                                        openRelation: { invoked.append("relation") },
                                        openLink: { invoked.append($0); return true })
        let parent = TaskDocumentProfile.make(task: try XCTUnwrap(workspace.task(for: parentID)), host: host)
        let child = TaskDocumentProfile.make(task: try XCTUnwrap(workspace.task(for: childID)), host: host)
        XCTAssertEqual(parent.commands.map(\.id), ["task.child", "task.tags", "task.relation"])
        XCTAssertEqual(child.commands.map(\.id), ["task.tags", "task.relation"])
        XCTAssertEqual(parent.slashCommands.count, 12)
        XCTAssertEqual(child.slashCommands.count, 11)
        XCTAssertFalse(parent.supportsSelectionToolbar)
        XCTAssertTrue(parent.selectionActions.isEmpty)
        let view = NativeTextView(frame: .zero, textContainer: nil)
        parent.commands.forEach { $0.perform(view) }
        XCTAssertEqual(invoked, ["child", "tags", "relation"])
        XCTAssertTrue(parent.onOpenLink?("workfollow://note/example") == true)
        XCTAssertEqual(invoked.last, "workfollow://note/example")
        XCTAssertEqual(workspace.allTasks.count, 2, "The editor delegates; it does not mutate business models itself")
    }

    func testNoteHostSelectionCreatesTrimmedInboxTaskAndPreservesLinks() throws {
        let tasks = TaskWorkspaceModel(seedDemoData: false)
        let notes = NotesWorkspaceModel()
        notes.create()
        let noteID = try XCTUnwrap(notes.selectedID)
        let existingLink = UUID()
        notes.edit(noteID) { $0.linkedTaskIDs = [existingLink] }
        let profile = NoteDocumentProfile.make(host: .make(noteID: noteID, tasks: tasks, notes: notes))
        let action = try XCTUnwrap(profile.selectionActions.first)
        XCTAssertEqual(action.title, "用所选文字创建任务")
        XCTAssertEqual(action.displayTitle, "创建任务")
        XCTAssertTrue(profile.supportsSelectionToolbar)
        XCTAssertEqual(profile.slashCommands.map(\.id), DocumentProfile(noteSlash: true).slashCommands.map(\.id))
        action.perform(" \n 行动项 \n ")
        let task = try XCTUnwrap(tasks.allTasks.first)
        XCTAssertEqual(task.title, "行动项")
        XCTAssertEqual(task.list, .inbox)
        XCTAssertEqual(notes.notes.first { $0.id == noteID }?.linkedTaskIDs, [existingLink, task.id])
        action.perform(" \n ")
        XCTAssertEqual(tasks.allTasks.count, 1)
        XCTAssertEqual(notes.notes.first { $0.id == noteID }?.linkedTaskIDs, [existingLink, task.id])
    }

    func testSelectionShortTitleIsMetadataNotBusinessIdentity() {
        let custom = DocumentSelectionAction(id: "host.custom", title: "完整说明", toolbarTitle: "短标题", perform: { _ in })
        XCTAssertEqual(custom.displayTitle, "短标题")
        XCTAssertEqual(custom.title, "完整说明")
        let fallback = DocumentSelectionAction(id: "note.createTask", title: "任意宿主标题", perform: { _ in })
        XCTAssertEqual(fallback.displayTitle, "任意宿主标题", "Core must not special-case a business action ID")
    }

    func testHostReferencePayloadPreservesDocumentLink() throws {
        let notes = NotesWorkspaceModel()
        notes.create()
        var note = try XCTUnwrap(notes.notes.first)
        for title in ["关联笔记", ""] {
            note.title = title
            let reference = TaskDocumentProfile.reference(to: note)
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            let handle = DocumentEditorHandle()
            handle.textView = editor
            handle.insertReference(reference)
            let document = DocumentTextCodec.decode(editor.attributedString(), preserving: .empty)
            XCTAssertEqual(document.plainText, title.isEmpty ? "📄 未命名笔记" : "📄 关联笔记")
            XCTAssertTrue(document.blocks.flatMap(\.runs).contains {
                $0.marks.contains(.link("workfollow://note/" + note.id.uuidString))
            })
            XCTAssertFalse(DocumentTextCodec.style(of: NSAttributedString(string: " ", attributes: editor.typingAttributes))
                .marks.contains(.link(reference.target)))
        }
    }

    func testToolbarDescriptorsPreserveTitlesSymbolsAndActiveState() throws {
        let ids = EditorCommandCatalog.selectionFormatIDs
        let descriptors = try ids.map { try XCTUnwrap(EditorCommandCatalog.format($0)).descriptor }
        XCTAssertEqual(descriptors.map(\.title), ["粗体", "斜体", "下划线", "删除线", "高亮", "行内代码"])
        XCTAssertEqual(descriptors.map(\.toolbarSymbol),
                       ["bold", "italic", "underline", "strikethrough", "highlighter", "chevron.left.forwardslash.chevron.right"])
        XCTAssertEqual(descriptors.last?.formatToolbarTitle, "代码")
        XCTAssertEqual(DocumentToolbarPicker.heading.titles, ["正文", "一级标题", "二级标题", "三级标题"])
        for format in DocumentFormatCommand.commands {
            for style in [DocumentSelectionStyle(),
                          DocumentSelectionStyle(blockToken: DocumentTextCodec.blockToken(format.block ?? .paragraph),
                                                 marks: format.mark.map { [$0] } ?? [])] {
                XCTAssertEqual(format.descriptor.isActive(in: style),
                               style.has(format.mark) || style.isBlock(format.block), format.id)
            }
        }
    }

    func testRealToolbarControlsKeepOrderAndGeometry() throws {
        let handle = DocumentEditorHandle()
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文")))
        editor.setSelectedRange(NSRange(location: 0, length: 2))
        handle.textView = editor
        let formatIDs = ["format.bold", "format.highlight", "format.checklist", "format.bullet",
                         "format.ordered", "format.italic", "format.underline", "format.strikethrough",
                         "format.inlineCode", "format.quote"]
        var formatFrames: [String: CGRect] = [:]
        let formatRoot = DocumentFormatToolbarView(handle: handle)
            .frame(width: 444, height: 38)
            .onPreferenceChange(EditorToolbarCommandFramesKey.self) { formatFrames = $0 }
        let formatWindow = renderToolbar(formatRoot, size: NSSize(width: 444, height: 38))
        defer { formatWindow.orderOut(nil); formatWindow.contentView = nil; formatWindow.close() }
        settleToolbar(formatWindow) { formatFrames.count == formatIDs.count }
        XCTAssertEqual(Set(formatFrames.keys), Set(formatIDs))
        for id in formatIDs {
            let frame = try XCTUnwrap(formatFrames[id])
            XCTAssertEqual(frame.width, 26, accuracy: 0.5, id)
            XCTAssertEqual(frame.height, 28, accuracy: 0.5, id)
        }
        for (left, right) in zip(formatIDs, formatIDs.dropFirst()) {
            XCTAssertLessThan(try XCTUnwrap(formatFrames[left]).midX,
                              try XCTUnwrap(formatFrames[right]).midX)
        }
        try clickToolbarControl(try XCTUnwrap(formatFrames["format.bold"]), in: formatWindow)
        XCTAssertTrue(handle.style.has(.bold), "The rendered format button must invoke the shared engine")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2))

        var selectionFrames: [String: CGRect] = [:]
        var selectionCommands: [String] = []
        let selectionRoot = DocumentSelectionToolbarView(actions: [], onInvoke: { _ in },
                                                         onFormat: { command in
                                                             selectionCommands.append(command.id)
                                                             handle.format(command)
                                                         }, onLink: {})
            .onPreferenceChange(EditorToolbarCommandFramesKey.self) { selectionFrames = $0 }
        let selectionWindow = renderToolbar(selectionRoot, size: NSSize(width: 200, height: 34))
        defer { selectionWindow.orderOut(nil); selectionWindow.contentView = nil; selectionWindow.close() }
        settleToolbar(selectionWindow) { selectionFrames.count == 6 }
        XCTAssertEqual(Set(selectionFrames.keys), Set(EditorCommandCatalog.selectionFormatIDs))
        for id in EditorCommandCatalog.selectionFormatIDs {
            let frame = try XCTUnwrap(selectionFrames[id])
            XCTAssertEqual(frame.width, 24, accuracy: 0.5, id)
            XCTAssertEqual(frame.height, 26, accuracy: 0.5, id)
        }
        for (left, right) in zip(EditorCommandCatalog.selectionFormatIDs, EditorCommandCatalog.selectionFormatIDs.dropFirst()) {
            XCTAssertLessThan(try XCTUnwrap(selectionFrames[left]).midX,
                              try XCTUnwrap(selectionFrames[right]).midX)
        }
        try clickToolbarControl(try XCTUnwrap(selectionFrames["format.bold"]), in: selectionWindow)
        XCTAssertEqual(selectionCommands, ["format.bold"])
        XCTAssertFalse(handle.style.has(.bold), "Both entry points toggle the same format on the same selection")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2))
    }

    private func clickToolbarControl(_ frame: CGRect, in window: NSWindow) throws {
        let host = try XCTUnwrap(window.contentView)
        let local = NSPoint(x: frame.midX, y: host.isFlipped ? frame.midY : host.bounds.height - frame.midY)
        let point = host.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    private func renderToolbar<Root: View>(_ root: Root, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root.environment(\.colorScheme, .light))
        window.orderFront(nil)
        return window
    }

    private func settleToolbar(_ window: NSWindow, until ready: () -> Bool) {
        for _ in 0..<20 {
            window.contentView?.layoutSubtreeIfNeeded()
            if ready() { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testCatalogUsesUniqueSemanticIDsIndependentOfPresentationOrder() throws {
        let descriptors = EditorCommandCatalog.formats
        XCTAssertEqual(Set(descriptors.map(\.id)).count, 16)
        XCTAssertEqual(descriptors.count, 16)
        let reversed = Dictionary(uniqueKeysWithValues: descriptors.reversed().map { ($0.id, $0.glyph) })
        for id in EditorCommandCatalog.compactSlashFormatIDs {
            let format = try XCTUnwrap(EditorCommandCatalog.format(id))
            XCTAssertEqual(reversed[id], format.descriptor.glyph)
            XCTAssertEqual(SlashGlyphKind.forCommand(id), format.descriptor.glyph)
        }
        XCTAssertEqual(EditorCommandCatalog.format("format.bold")?.mark, .bold)
        XCTAssertEqual(EditorCommandCatalog.format("format.heading3")?.block, .heading(3))
        XCTAssertEqual(EditorCommandCatalog.format("format.checkedChecklist")?.block, .checklist(true))
    }

    func testTaskNoteAndGenericProfilesShareFormatIdentityWithoutChangingGlyphPolicy() {
        let task = DocumentProfile(taskSlash: true).slashCommands
        let note = DocumentProfile(noteSlash: true).slashCommands
        let generic = DocumentProfile().slashCommands
        XCTAssertEqual(task.map(\.id), note.map(\.id))
        XCTAssertEqual(Array(task.prefix(7)).map(\.id), EditorCommandCatalog.compactSlashFormatIDs)
        XCTAssertEqual(Array(generic.prefix(16)).map(\.id), DocumentFormatCommand.commands.map(\.id))
        XCTAssertEqual(Array(task.prefix(7)).map(\.resolvedGlyph),
                       [.heading(1), .heading(2), .heading(3), .bullet, .ordered, .checklist, .quote])
        XCTAssertTrue(generic.prefix(16).allSatisfy { $0.resolvedGlyph == .symbol("text.alignleft") },
                      "Generic Slash keeps its existing visual policy during this refactor")
        for command in task.prefix(7) {
            let format = EditorCommandCatalog.format(command.id)
            XCTAssertEqual(command.title, format?.title)
            XCTAssertEqual(command.keywords, "", "Compact Slash search behavior must not change")
        }
    }

    func testSlashAdapterKeepsExistingFormatExecutionResults() {
        for format in DocumentFormatCommand.commands {
            let direct = NativeTextView(frame: .zero, textContainer: nil)
            let adapted = NativeTextView(frame: .zero, textContainer: nil)
            for view in [direct, adapted] {
                view.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文内容")))
                view.setSelectedRange(NSRange(location: 1, length: 2))
            }
            direct.applyFormat(format)
            format.slashCommand(group: "格式").perform(adapted)
            let expected = DocumentTextCodec.decode(direct.attributedString(), preserving: .empty)
            let actual = DocumentTextCodec.decode(adapted.attributedString(), preserving: .empty)
            XCTAssertEqual(actual.plainText, expected.plainText, format.id)
            XCTAssertEqual(actual.blocks.map(\.kind), expected.blocks.map(\.kind), format.id)
            XCTAssertEqual(actual.blocks.flatMap(\.runs).map(\.marks),
                           expected.blocks.flatMap(\.runs).map(\.marks), format.id)
            XCTAssertEqual(adapted.selectedRange(), direct.selectedRange(), format.id)
            XCTAssertEqual(DocumentTextCodec.style(of: adapted.attributedString()),
                           DocumentTextCodec.style(of: direct.attributedString()), format.id)
        }
    }

    func testTaskSlashCommandsMatchFlutterOrderAndLabels() {
        let parentCommands = taskActions(includeChild: true)
        let childCommands = taskActions(includeChild: false)

        let parentTitles = DocumentProfile(commands: parentCommands, taskSlash: true)
            .slashCommands.map(\.title)
        let childTitles = DocumentProfile(commands: childCommands, taskSlash: true)
            .slashCommands.map(\.title)

        XCTAssertEqual(parentTitles, [
            "一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用",
            "水平分割线", "附件", "子任务", "标签", "关联任务/笔记"
        ])
        XCTAssertEqual(childTitles, [
            "一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用",
            "水平分割线", "附件", "标签", "关联任务/笔记"
        ])
    }

    func testTaskSlashClosesWhenTypingAfterSlashInsteadOfSearching() {
        var session = SlashSession(start: 3)

        XCTAssertTrue(session.update(
            text: "abc/",
            selection: NSRange(location: 4, length: 0),
            allowsQuery: false
        ))
        XCTAssertFalse(session.update(
            text: "abc/q",
            selection: NSRange(location: 5, length: 0),
            allowsQuery: false
        ))
    }

    private func taskActions(includeChild: Bool) -> [DocumentCommand] {
        var commands: [DocumentCommand] = []
        if includeChild {
            commands.append(DocumentCommand(id: "task.child", title: "子任务", group: "插入") { _ in })
        }
        commands.append(DocumentCommand(id: "task.tags", title: "标签", group: "插入") { _ in })
        commands.append(DocumentCommand(id: "task.relation", title: "关联任务/笔记", group: "插入") { _ in })
        return commands
    }
}
