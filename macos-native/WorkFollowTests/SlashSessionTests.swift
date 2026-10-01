import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class SlashSessionTests: XCTestCase {
    private func taskProfile(_ task: Task, workspace: TaskWorkspaceModel,
                             tags: @escaping () -> Void = {}, relation: @escaping () -> Void = {}) -> DocumentProfile {
        TaskDocumentProfile.make(task: task, host: TaskEditorHostActions(
            createChild: { workspace.requestChildTitleEditor(for: task.id) },
            openTags: tags, openRelation: relation, openLink: { _ in false }))
    }

    func testTaskSlashChecklistAndChildUseDifferentMutationChannels() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = taskProfile(try XCTUnwrap(workspace.task(for: parentID)), workspace: workspace)
        editor.insertText("/", replacementRange: editor.selectedRange())
        editor.executeSlash(at: try XCTUnwrap(editor.profile.slashCommands.firstIndex { $0.id == "format.checklist" }))
        XCTAssertEqual(editor.string, "")
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.pendingTrailingBlock, .checklist(false))
        XCTAssertEqual(workspace.allTasks.count, 1)
        XCTAssertNil(workspace.pendingChildTitleEditorID)

        editor.insertText("/", replacementRange: editor.selectedRange())
        editor.executeSlash(at: try XCTUnwrap(editor.profile.slashCommands.firstIndex { $0.id == "task.child" }))
        XCTAssertEqual(editor.string, "")
        XCTAssertNil(editor.slashSession)
        let childID = try XCTUnwrap(workspace.pendingChildTitleEditorID)
        XCTAssertEqual(workspace.task(for: childID)?.parentID, parentID)
        XCTAssertEqual(workspace.allTasks.count, 2)
        XCTAssertEqual(workspace.selectedTaskID, parentID)
        let childProfile = taskProfile(try XCTUnwrap(workspace.task(for: childID)), workspace: workspace)
        XCTAssertFalse(childProfile.slashCommands.contains { $0.id == "task.child" })
    }

    func testTaskSlashBusinessPickersConsumeTriggerBeforeCallingHost() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: parentID))
        for id in ["task.tags", "task.relation"] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            var routed: [String] = []
            func opened(_ action: String) {
                XCTAssertEqual(editor.string, "正文 ")
                XCTAssertNil(editor.slashSession)
                XCTAssertNil(editor.slashPanel)
                routed.append(action)
            }
            editor.profile = taskProfile(task, workspace: workspace,
                tags: { opened("task.tags") }, relation: { opened("task.relation") })
            editor.insertText("正文 ", replacementRange: editor.selectedRange())
            editor.insertText("、", replacementRange: editor.selectedRange())
            editor.executeSlash(at: try XCTUnwrap(editor.profile.slashCommands.firstIndex { $0.id == id }))
            XCTAssertEqual(routed, [id])
            XCTAssertEqual(workspace.allTasks.count, 1)
        }
    }

    func testTaskSlashFormatAndDividerAreSingleUndoOperations() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: parentID))
        for id in ["format.heading1", "format.checklist", "shared.divider"] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            editor.profile = taskProfile(task, workspace: workspace)
            let original = NativeDocument(plainText: "前段\n\n后段")
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(original))
            editor.setSelectedRange(NSRange(location: 3, length: 0))
            let manager = try XCTUnwrap(editor.undoManager)
            // Direct test calls have no separate AppKit input/click events.
            // Use explicit groups to model those two event boundaries.
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
            editor.insertText("/", replacementRange: editor.selectedRange())
            manager.endUndoGrouping()
            let before = editor.attributedString().copy() as! NSAttributedString
            editor.executeSlash(at: try XCTUnwrap(editor.profile.slashCommands.firstIndex { $0.id == id }))
            XCTAssertFalse(editor.string.contains("/"), id)
            editor.undo(nil)
            XCTAssertEqual(editor.string, "前段\n/\n后段", id)
            let restored = DocumentTextCodec.decode(editor.attributedString(), preserving: original)
            let expected = DocumentTextCodec.decode(before, preserving: original)
            XCTAssertEqual(restored.blocks.map(\.kind), expected.blocks.map(\.kind), id)
        }
    }

    func testHoverKeyboardAndEscapeShareOneTaskSlashSelection() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        var hostEscapes = 0
        editor.onEscape = { hostEscapes += 1; return .keepInspector }
        editor.insertText("/", replacementRange: editor.selectedRange())
        editor.hoverSlash(4)
        XCTAssertEqual(editor.slashSession?.selectedIndex, 4)
        editor.doCommand(by: #selector(NSTextView.moveDown(_:)))
        XCTAssertEqual(editor.slashSession?.selectedIndex, 5)
        editor.doCommand(by: #selector(NSTextView.moveUp(_:)))
        XCTAssertEqual(editor.slashSession?.selectedIndex, 4)
        editor.cancelOperation(nil)
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.string, "/")
        XCTAssertEqual(hostEscapes, 0)
    }

    func testTaskSlashWindowsRenderParentChildHoverAndBottomFlip() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parentID = try XCTUnwrap(workspace.createTask(title: "父任务", in: .inbox).taskID)
        let childID = try XCTUnwrap(workspace.createChild(parentID, title: "子任务").taskID)
        for (name, taskID, nearBottom, hover) in [
            ("parent", parentID, false, false), ("child", childID, false, false),
            ("hover", parentID, false, true), ("bottom", parentID, true, false)
        ] {
            let window = NSWindow(contentRect: NSRect(x: 200, y: 100, width: 600, height: 700),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let editor = NativeTextView(frame: window.contentLayoutRect, textContainer: nil)
            // This fixture is a fixed viewport, not the content-sized host.
            // Prevent NSTextView's text insertion from resizing its root view.
            editor.isVerticallyResizable = false
            editor.profile = taskProfile(try XCTUnwrap(workspace.task(for: taskID)), workspace: workspace)
            window.contentView = editor
            window.orderFront(nil)
            window.makeFirstResponder(editor)
            defer { editor.dismissSlash(); window.close() }
            if nearBottom {
                editor.insertText(String(repeating: "正文\n", count: 20), replacementRange: editor.selectedRange())
            }
            let editorFrame = editor.frame
            editor.insertText("/", replacementRange: editor.selectedRange())
            if hover { editor.hoverSlash(4) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let panel = try XCTUnwrap(editor.slashPanel)
            XCTAssertTrue(panel.parent === window)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(editor.frame, editorFrame, "Slash cannot push editor layout")
            XCTAssertEqual(panel.frame.width, 160, accuracy: 0.5)
            XCTAssertEqual(panel.frame.height, taskID == childID ? 391 : 425, accuracy: 0.5)
            if hover { XCTAssertEqual(editor.slashSession?.selectedIndex, 4) }
            let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            if nearBottom {
                XCTAssertGreaterThanOrEqual(panel.frame.minY, caret.maxY, "Bottom caret must flip menu above")
            } else {
                XCTAssertLessThanOrEqual(panel.frame.maxY, caret.minY, "Prefer below caret")
            }
            XCTAssertTrue(window.frame.insetBy(dx: 11, dy: 11).contains(panel.frame))
            let image = try XCTUnwrap(CGWindowListCreateImage(.null, .optionIncludingWindow,
                CGWindowID(panel.windowNumber), [.bestResolution]))
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/render_task_slash_\(name).png"))
        }
    }

    func testSlashFollowsViewportAndWindowChanges() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.autoresizingMask = [.width, .height]
        let editor = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 1400), textContainer: nil)
        editor.isVerticallyResizable = false
        editor.profile = DocumentProfile(taskSlash: true)
        scroll.documentView = editor
        window.contentView = scroll
        window.orderFront(nil)
        defer { editor.dismissSlash(); window.close() }
        editor.insertText(String(repeating: "正文\n", count: 6), replacementRange: editor.selectedRange())
        editor.insertText("/", replacementRange: editor.selectedRange())
        let panel = try XCTUnwrap(editor.slashPanel)
        func followsCaret(file: StaticString = #filePath, line: UInt = #line) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let caret = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            XCTAssertEqual(panel.frame.maxY, caret.minY - WFPlanningOverlayMetrics.gap,
                           accuracy: 1, file: file, line: line)
        }
        followsCaret()
        let before = panel.frame
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
        scroll.reflectScrolledClipView(scroll.contentView)
        followsCaret()
        XCTAssertNotEqual(panel.frame.origin.y, before.origin.y)
        window.setFrameOrigin(NSPoint(x: 180, y: 150))
        followsCaret()
        window.setContentSize(NSSize(width: 660, height: 960))
        followsCaret()
        XCTAssertTrue(panel.parent === window)
    }

    func testTaskSlashTriggersAfterWhitespaceAndClosesWhenTypingContinues() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.insertText("正文 ", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())
        XCTAssertNotNil(editor.slashSession)
        XCTAssertEqual(editor.profile.slashCommands.map(\.title), ["一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用", "水平分割线", "附件"])
        editor.insertText("a", replacementRange: editor.selectedRange())
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.string, "正文 /a")
    }

    func testSlashAndIdeographicCommaOpenTheSameFormatPaletteForTasksAndNotes() {
        for profile in [DocumentProfile(taskSlash: true), DocumentProfile(noteSlash: true)] {
            for trigger in ["/", "、"] {
                let editor = NativeTextView(frame: .zero, textContainer: nil)
                editor.profile = profile
                editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
                editor.setSelectedRange(NSRange(location: 0, length: 0))
                editor.insertText(trigger, replacementRange: editor.selectedRange())

                XCTAssertEqual(editor.string, "\(trigger)正文")
                var session = try! XCTUnwrap(editor.slashSession)
                XCTAssertEqual(session.trigger, trigger)
                XCTAssertTrue(session.update(text: editor.string, selection: editor.selectedRange(),
                                             allowsQuery: false))
                XCTAssertEqual(session.range, NSRange(location: 0, length: 1))

                editor.executeSlash(at: 0)
                XCTAssertEqual(editor.string, "正文", "the selected command removes only its trigger")
                let formatted = DocumentTextCodec.decode(
                    editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
                XCTAssertEqual(formatted.blocks.first?.kind, .heading(1))
            }
        }
    }

    func testUTF16RangeSearchAndKeyboardWrap() {
        var session = SlashSession(start: 3)
        XCTAssertTrue(session.update(text: "😀 /标题", selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(session.range, NSRange(location: 3, length: 3))
        XCTAssertEqual(session.results(in: DocumentProfile().slashCommands).count, 3)
        session.move(-1, count: 2)
        XCTAssertEqual(session.selectedIndex, 1)
        session.move(1, count: 2)
        XCTAssertEqual(session.selectedIndex, 0)
    }

    func testDeletingSlashOrMovingOutsideCancelsSession() {
        var session = SlashSession(start: 0)
        XCTAssertFalse(session.update(text: "abc", selection: NSRange(location: 3, length: 0)))
        XCTAssertFalse(session.update(text: "/abc", selection: NSRange(location: 0, length: 0)))
        XCTAssertFalse(session.update(text: "/abc\n", selection: NSRange(location: 5, length: 0)))
    }

    func testInjectedCommandOnlyExistsInItsProfile() {
        let custom = DocumentCommand(id: "host.action", title: "业务操作", group: "宿主", keywords: "custom") { _ in }
        let profile = DocumentProfile(commands: [custom])
        var session = SlashSession(start: 0)
        XCTAssertTrue(session.update(text: "/custom", selection: NSRange(location: 7, length: 0)))
        XCTAssertEqual(session.results(in: profile.slashCommands).map(\.id), ["host.action"])
        XCTAssertTrue(session.results(in: DocumentProfile().slashCommands).isEmpty)
    }

    func testExecutionConsumesQueryAndCallsInjectedAction() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var invoked = false
        editor.profile = DocumentProfile(commands: [DocumentCommand(id: "custom", title: "custom", group: "测试") { view in
            invoked = true
            XCTAssertEqual(view.string, "")
        }])
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("custom", replacementRange: NSRange(location: 1, length: 0))
        editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertTrue(invoked)
        XCTAssertNil(editor.slashSession)
        XCTAssertEqual(editor.string, "")
    }

    func testSlashBlockFormatsMatchFlutterLineScopeAndKeepCaret() {
        let cases: [(Int, DocumentBlockKind)] = [
            (0, .heading(1)), (1, .heading(2)), (2, .heading(3)),
            (3, .bullet), (4, .ordered), (5, .checklist(false)), (6, .quote)
        ]

        for (commandIndex, expectedKind) in cases {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            editor.profile = DocumentProfile(taskSlash: true)
            let original = "前置\n目标 内容\n后置"
            editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: original)))
            editor.setSelectedRange(NSRange(location: 6, length: 0))
            editor.insertText("/", replacementRange: editor.selectedRange())

            editor.executeSlash(at: commandIndex)

            XCTAssertEqual(editor.string, original, "command \(commandIndex) must only remove its slash trigger")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 0), "command \(commandIndex) must preserve the caret")
            let document = DocumentTextCodec.decode(
                editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
            XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, expectedKind, .paragraph],
                           "command \(commandIndex) must format only the invoking line")

            editor.insertText("续", replacementRange: editor.selectedRange())
            let continued = DocumentTextCodec.decode(
                editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
            XCTAssertEqual(editor.string, "前置\n目标 续内容\n后置")
            XCTAssertEqual(continued.blocks.map(\.kind), [.paragraph, expectedKind, .paragraph],
                           "typing after command \(commandIndex) must retain the line format")

            if expectedKind == .bullet || expectedKind == .ordered || expectedKind == .checklist(false) {
                let style = editor.attributedString().attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle
                // 标记由视图层自绘，段落不挂 NSTextList（否则与自绘标记重复）。
                XCTAssertEqual(style?.textLists.isEmpty, true,
                               "list command \(commandIndex) must not carry a native text list")
            }
        }
    }

    func testSlashChecklistFormatsOneEmptyLineWithoutMarkingTheNextLine() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        let original = "前置\n\n后置"
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: original)))
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())

        editor.executeSlash(at: 5)

        XCTAssertEqual(editor.string, original)
        let document = DocumentTextCodec.decode(
            editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .checklist(false), .paragraph])
    }

    func testSlashOrderedFormatJoinsAdjacentOrderedItems() throws {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "前置")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "目标项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "第三项")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "后置")])
        ])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 10, length: 0))
        editor.insertText(" ", replacementRange: editor.selectedRange())
        editor.insertText("/", replacementRange: editor.selectedRange())

        editor.executeSlash(at: 4)

        let rendered = editor.attributedString()
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 3, in: rendered), 1)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 7, in: rendered), 2)
        XCTAssertEqual(DocumentTextCodec.ordinal(forOrderedParagraphAt: 12, in: rendered), 3)
    }

    func testSlashInlineFormatAppliesToNextTypedText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "正文")))
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: editor.selectedRange())
        let boldIndex = editor.profile.slashCommands.firstIndex { $0.id == "format.bold" }!
        editor.executeSlash(at: boldIndex)
        editor.insertText("加粗", replacementRange: editor.selectedRange())
        let boldDocument = DocumentTextCodec.decode(
            editor.attributedString(), preserving: NativeDocument(plainText: editor.string))
        XCTAssertTrue(boldDocument.blocks[0].runs.contains { $0.text == "加粗" && $0.marks.contains(.bold) })
    }

    func testSlashDividerKeepsSurroundingText() {
        let divider = NativeTextView(frame: .zero, textContainer: nil)
        divider.profile = DocumentProfile(taskSlash: true)
        divider.textStorage?.setAttributedString(DocumentTextCodec.render(NativeDocument(plainText: "前置内容")))
        divider.setSelectedRange(NSRange(location: 2, length: 0))
        divider.insertText(" ", replacementRange: divider.selectedRange())
        divider.insertText("/", replacementRange: divider.selectedRange())
        divider.executeSlash(at: 7)
        XCTAssertEqual(divider.string, "前置 \n\u{FFFC}\n内容")
        let dividerDocument = DocumentTextCodec.decode(
            divider.attributedString(), preserving: NativeDocument(plainText: divider.string))
        XCTAssertTrue(dividerDocument.blocks.contains { $0.kind == .divider })
    }

    func testEscapeKeepsQueryAndDoesNotEscapeHost() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        var escaped = false
        editor.onEscape = { escaped = true; return .keepInspector }
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        editor.cancelOperation(nil)
        XCTAssertEqual(editor.string, "/")
        XCTAssertNil(editor.slashSession)
        XCTAssertFalse(escaped)
    }

    /// 面板每一项的图形：三个标题是 H + 下标级别，其余段落字形按原版手绘，
    /// 只有附件走系统图标。这里把 id → 图形的映射与真实清单钉在一起，
    /// `DocumentProfile` 里那七项的顺序一变就会被抓住。
    func testSlashGlyphMappingFollowsThePaletteOrder() {
        XCTAssertEqual(DocumentProfile(taskSlash: true).slashCommands.map { SlashGlyphKind.forCommand($0.id) },
                       [.heading(1), .heading(2), .heading(3), .bullet, .ordered, .checklist,
                        .quote, .divider, .symbol("paperclip")])
        XCTAssertEqual(SlashGlyphKind.forCommand("task.child"), .nestedItems)
        XCTAssertEqual(SlashGlyphKind.forCommand("task.tags"), .labelTag)
        XCTAssertEqual(SlashGlyphKind.forCommand("task.relation"), .linkedCards)
    }

    /// 用 `/` 覆盖一段选中文本是普通编辑：原版按前后文本差异判断"这是插入了一个
    /// `/`"，选中内容被替换掉不算，因此不该开面板（`slash_command_session.dart:21-31`）。
    func testTypingSlashOverASelectionIsOrdinaryText() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.insertText("选中的文字", replacementRange: NSRange(location: 0, length: 0))
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        editor.insertText("/", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "/文字")
        XCTAssertNil(editor.slashSession, "替换选中文本不该开斜杠面板")
    }

    func testTypingEitherTriggerOverASelectionIsOrdinaryText() {
        for trigger in ["/", "、"] {
            let editor = NativeTextView(frame: .zero, textContainer: nil)
            editor.profile = DocumentProfile(taskSlash: true)
            editor.insertText("选中的文字", replacementRange: NSRange(location: 0, length: 0))
            editor.setSelectedRange(NSRange(location: 0, length: 3))
            editor.insertText(trigger, replacementRange: editor.selectedRange())

            XCTAssertEqual(editor.string, "\(trigger)文字")
            XCTAssertNil(editor.slashSession, "replacing selected text must not open the palette")
        }
    }

    func testIdeographicCommaCommittedFromMarkedTextOpensPalette() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.profile = DocumentProfile(taskSlash: true)
        editor.setMarkedText("、", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())

        editor.insertText("、", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "、")
        XCTAssertNotNil(editor.slashSession)
    }

    func testBothTriggersRequireDocumentStartOrPrecedingWhitespace() {
        for profile in [DocumentProfile(taskSlash: true), DocumentProfile(noteSlash: true)] {
            for trigger in ["/", "、"] {
                for prefix in ["", "正文 ", "正文\n"] {
                    let editor = NativeTextView(frame: .zero, textContainer: nil)
                    editor.profile = profile
                    editor.insertText(prefix, replacementRange: NSRange(location: 0, length: 0))
                    editor.insertText(trigger, replacementRange: editor.selectedRange())

                    XCTAssertNotNil(editor.slashSession,
                                    "trigger \(trigger) should open after prefix \(prefix.debugDescription)")
                }

                let editor = NativeTextView(frame: .zero, textContainer: nil)
                editor.profile = profile
                editor.insertText("正文", replacementRange: NSRange(location: 0, length: 0))
                editor.insertText(trigger, replacementRange: editor.selectedRange())

                XCTAssertEqual(editor.string, "正文\(trigger)")
                XCTAssertNil(editor.slashSession,
                             "trigger \(trigger) must stay literal when attached to text")
            }
        }
    }

    func testURLDoesNotOpenSession() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        editor.insertText("https:", replacementRange: NSRange(location: 0, length: 0))
        editor.insertText("/", replacementRange: NSRange(location: 6, length: 0))
        XCTAssertNil(editor.slashSession)
    }

    func testDocumentRebindClearsUndoAndSlash() {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let coordinator = DocumentEditorCoordinator(documentID: UUID(), document: .empty,
            onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        editor.delegate = coordinator
        editor.insertText("/", replacementRange: NSRange(location: 0, length: 0))
        coordinator.update(editor, documentID: UUID(), document: NativeDocument(plainText: "second"),
                           onDocumentChange: { _ in }, onEscape: { .keepInspector }, onEditingChanged: { _ in })
        XCTAssertEqual(editor.string, "second")
        XCTAssertFalse(editor.undoManager!.canUndo)
        XCTAssertNil(editor.slashSession)
    }
}
