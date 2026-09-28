import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class NoteFeatureTests: XCTestCase {
    func testNoteChecklistToggleChangesOnlyClickedParagraphAndSupportsUndo() {
        let view = NativeTextView(frame: .zero, textContainer: nil)
        view.profile = DocumentProfile(noteSlash: true)
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第一项")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "第二项")])
        ])
        view.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.toggleNoteChecklist(at: 0)
        let result = DocumentTextCodec.decode(view.attributedString(), preserving: document)
        XCTAssertEqual(result.blocks.map(\.kind), [.checklist(true), .checklist(false)])
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))
        view.undoManager?.undo()
        XCTAssertEqual(DocumentTextCodec.decode(view.attributedString(), preserving: document).blocks.map(\.kind),
                       [.checklist(false), .checklist(false)])
    }

    func testFolderChangesAlsoApplyToTrashWithoutChangingDeletionOrder() throws {
        let date = Date(timeIntervalSince1970: 10)
        let model = NotesWorkspaceModel(clock: { date })
        XCTAssertTrue(model.addFolder("会议"))
        model.create(folder: "会议")
        let id = try XCTUnwrap(model.selectedID)
        model.delete(id)
        XCTAssertTrue(model.renameFolder("会议", to: "记录"))
        XCTAssertEqual(model.notes.first?.folder, "记录")
        XCTAssertEqual(model.notes.first?.deletedAt, date)
        model.folderFilter = "记录"
        model.removeFolder("记录")
        XCTAssertEqual(model.folderFilter, "未归档")
        model.restore(id)
        XCTAssertEqual(model.notes.first?.folder, "未归档")
        XCTAssertTrue(model.folders.isEmpty)
    }

    func testNoteSlashMatchesFlutterSharedDocumentCommands() {
        let profile = DocumentProfile(noteSlash: true)
        XCTAssertEqual(profile.slashCommands.map(\.title), ["一级标题", "二级标题", "三级标题", "无序列表", "有序列表", "检查项", "引用", "水平分割线", "附件"])
        XCTAssertFalse(profile.taskSlash)
        XCTAssertTrue(profile.compactSlash)
    }
    func testNoteIndexSortAndCreationInCurrentFolder() {
        let a = Note(id: UUID(), title: "A", document: .empty, folder: "工作", favorite: true,
                     updatedAt: Date(timeIntervalSince1970: 1))
        let b = Note(id: UUID(), title: "B", document: .empty, folder: "未归档",
                     updatedAt: Date(timeIntervalSince1970: 2))
        let model = NotesWorkspaceModel(initialNotes: [a, b])
        XCTAssertEqual(model.rows(trash: false, query: "", folder: nil, favorites: false).map(\.title), ["A", "B"])
        model.sort(.recentlyEdited)
        XCTAssertEqual(model.rows(trash: false, query: "", folder: nil, favorites: false).map(\.title), ["B", "A"])
        model.sort(.title)
        XCTAssertEqual(model.rows(trash: false, query: "", folder: nil, favorites: false).map(\.title), ["A", "B"])
        XCTAssertEqual(model.rows(trash: false, query: "", folder: "工作", favorites: true).map(\.id), [a.id])
        model.create(folder: "工作")
        XCTAssertEqual(model.selected?.folder, "工作")
        XCTAssertEqual(model.folders, ["工作"])
    }

    func testFolderLifecycleAndSnapshotPersistence() throws {
        let model = NotesWorkspaceModel()
        XCTAssertTrue(model.addFolder("会议"))
        XCTAssertFalse(model.addFolder("会议"))
        let data = try JSONEncoder().encode(NativeWorkspaceSnapshot(tasks: [], notes: [], noteFolders: model.folders))
        let snapshot = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: data)
        let reopened = NotesWorkspaceModel(initialNotes: snapshot.notes, folders: snapshot.noteFolders ?? [])
        XCTAssertEqual(reopened.folders, ["会议"])
        reopened.create(folder: "会议")
        XCTAssertTrue(reopened.renameFolder("会议", to: "会议记录"))
        XCTAssertEqual(reopened.selected?.folder, "会议记录")
        reopened.removeFolder("会议记录")
        XCTAssertEqual(reopened.selected?.folder, "未归档")
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertTrue(reopened.folders.isEmpty)
    }

    func testEditingDoesNotReorderNotesAndExplicitOrderSurvivesReopening() throws {
        let model = NotesWorkspaceModel()
        model.create()
        let first = try XCTUnwrap(model.selectedID)
        model.edit(first) { $0.title = "A" }
        model.create()
        let second = try XCTUnwrap(model.selectedID)
        model.edit(second) { $0.title = "B" }
        model.edit(first) { $0.document = NativeDocument(plainText: "更新正文"); $0.favorite = true }
        XCTAssertEqual(model.rows(trash: false, query: "", folder: nil, favorites: false).map(\.id), [second, first])
        model.sort(.title)
        model.edit(second) { $0.title = "0" }
        XCTAssertEqual(model.rows(trash: false, query: "", folder: nil, favorites: false).map(\.id), [first, second])
        let data = try JSONEncoder().encode(NativeWorkspaceSnapshot(tasks: [], notes: model.notes))
        let saved = try JSONDecoder().decode(NativeWorkspaceSnapshot.self, from: data)
        let reopened = NotesWorkspaceModel(initialNotes: saved.notes)
        XCTAssertEqual(reopened.rows(trash: false, query: "", folder: nil, favorites: false).map(\.id), [first, second])
        reopened.create()
        XCTAssertEqual(reopened.rows(trash: false, query: "", folder: nil, favorites: false).first?.id, reopened.selectedID)
    }

    // MARK: - 页脚字数统计（去空白 rune 计数）

    func testWordCountSkipsWhitespaceAndCountsCodePoints() {
        XCTAssertEqual(noteWordCount(""), 0)
        XCTAssertEqual(noteWordCount("   \n\t"), 0)
        XCTAssertEqual(noteWordCount("你好 世界"), 4)
        XCTAssertEqual(noteWordCount(" a b\nc "), 3)
        XCTAssertEqual(noteWordCount("👍"), 1)
        // Dart runes 语义：家庭 emoji 按码点计 5，而不是按字素簇计 1
        XCTAssertEqual(noteWordCount("👨‍👩‍👧"), 5)
    }

    // MARK: - 纯文本副本（命名与内容）

    func testPlainTextCopyNamingAndContent() {
        let attachment = NativeAttachment(id: UUID(), name: "图.png", storedName: "data:image/png;base64,AAAA")
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题", marks: [.bold])]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "要点"),
                                                DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        let source = Note(id: UUID(), title: "会议记录", document: document, folder: "工作", favorite: true,
                          updatedAt: Date(timeIntervalSince1970: 0), originalContentJson: "{\"type\":\"doc\"}")
        let model = NotesWorkspaceModel(initialNotes: [source])
        model.selectedID = source.id

        let copyID = model.createPlainTextCopy(source.id)
        let copy = try? XCTUnwrap(model.notes.first { $0.id == copyID })
        XCTAssertEqual(model.selectedID, copyID)
        XCTAssertEqual(copy?.title, "会议记录（纯文本副本）")
        // 内容：只保留段落文字，剥离标记与附件占位符
        XCTAssertEqual(copy?.document.plainText, "标题\n要点")
        XCTAssertTrue(copy?.document.blocks.allSatisfy { block in
            block.kind == .paragraph && block.runs.allSatisfy { $0.attachment == nil && $0.marks.isEmpty }
        } ?? false)
        // 副本是本地笔记，不再受保护；原笔记与原文 JSON 保持不动
        XCTAssertFalse(copy?.hasPreservedRichContent ?? true)
        XCTAssertEqual(model.notes.first { $0.id == source.id }?.originalContentJson, source.originalContentJson)
        XCTAssertEqual(model.notes.first { $0.id == source.id }?.document, document)

        // 无标题时命名为“（纯文本副本）”
        XCTAssertEqual(notePlainTextCopyTitle(""), "（纯文本副本）")
        XCTAssertEqual(notePlainTextCopyTitle("随笔"), "随笔（纯文本副本）")
    }

    func testPlainTextCopyRequiresPreservedRichContent() {
        let plain = Note(id: UUID(), title: "本地笔记", document: NativeDocument(plainText: "正文"),
                         folder: "未归档", updatedAt: Date(timeIntervalSince1970: 0))
        let model = NotesWorkspaceModel(initialNotes: [plain])
        model.selectedID = plain.id

        XCTAssertNil(model.createPlainTextCopy(plain.id))
        XCTAssertEqual(model.notes.count, 1)
        // 写入原始内容后进入受保护状态，可转换
        model.preserveOriginalContent(plain.id, json: "{}")
        XCTAssertTrue(model.selected?.hasPreservedRichContent ?? false)
        XCTAssertNotNil(model.createPlainTextCopy(plain.id))
    }

    // MARK: - originalContentJson additive Codable 往返

    func testOriginalContentJSONRoundTripAndLegacyDecode() throws {
        var note = Note(id: UUID(), title: "导入笔记", document: NativeDocument(plainText: "正文"),
                        folder: "未归档", updatedAt: Date(timeIntervalSince1970: 0),
                        originalContentJson: "{\"type\":\"doc\",\"content\":[]}")
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)
        XCTAssertEqual(decoded, note)
        XCTAssertTrue(decoded.hasPreservedRichContent)

        // 旧快照没有 originalContentJson 键：解码为 nil，不报错
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "originalContentJson")
        let legacyNote = try JSONDecoder().decode(Note.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(legacyNote.originalContentJson)
        XCTAssertFalse(legacyNote.hasPreservedRichContent)
        note.originalContentJson = nil
        XCTAssertEqual(legacyNote, note)
    }

    // MARK: - 关联任务区：taskProvider / openTask 接缝

    func testTaskProviderSeamListsTasksLinkedToNote() {
        let noteID = UUID()
        let note = Note(id: noteID, title: "笔记", document: .empty, folder: "未归档",
                        updatedAt: Date(timeIntervalSince1970: 0))
        let linked = makeTask(id: UUID(), title: "来自笔记的行动项", sourceNoteID: noteID)
        let deleted = makeTask(id: UUID(), title: "已删除", sourceNoteID: noteID, deletedAt: Date(timeIntervalSince1970: 5))
        let other = makeTask(id: UUID(), title: "别人的任务", sourceNoteID: UUID())
        let model = NotesWorkspaceModel(initialNotes: [note])

        // 未接线时安全降级为空
        XCTAssertNil(model.taskProvider)
        XCTAssertTrue(model.tasksLinkedToNote(note).isEmpty)

        model.taskProvider = { [linked, deleted, other] }
        XCTAssertEqual(model.tasksLinkedToNote(note).map(\.title), ["来自笔记的行动项"])
    }

    // MARK: - 格式工具条命令覆盖（迁移项：高亮/链接/时间/代码/引用/附件全部走命令通道）

    func testFormatToolbarCommandSetCoversMigratedMarksAndBlocks() {
        for mark in [DocumentMark.bold, .italic, .underline, .strikethrough, .highlight, .code] {
            XCTAssertNotNil(DocumentFormatCommand.commands.first { $0.mark == mark }, "缺少 \(mark) 命令")
        }
        let blocks: [DocumentBlockKind] = [.paragraph, .heading(1), .heading(2), .heading(3),
                                           .quote, .code, .bullet, .ordered, .checklist(false)]
        for kind in blocks {
            XCTAssertNotNil(DocumentFormatCommand.commands.first { $0.block == kind }, "缺少 \(kind) 命令")
        }
    }

    // MARK: - 链接 / 高亮 mark 命令往返（DocumentContentTests 风格）

    func testHighlightAndLinkMarkCommandsRoundTrip() throws {
        let editor = NativeTextView(frame: .zero, textContainer: nil)
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "重点句子")])])
        editor.textStorage?.setAttributedString(DocumentTextCodec.render(document))
        editor.setSelectedRange(NSRange(location: 0, length: 4))

        let highlight = try XCTUnwrap(DocumentFormatCommand.commands.first { $0.mark == .highlight })
        editor.applyFormat(highlight)
        editor.setDocumentLink("https://example.com/path", range: NSRange(location: 0, length: 4))

        let decoded = DocumentTextCodec.decode(editor.attributedString(), preserving: document)
        XCTAssertEqual(decoded.plainText, "重点句子")
        XCTAssertTrue(decoded.blocks[0].runs[0].marks.contains(.highlight))
        XCTAssertTrue(decoded.blocks[0].runs[0].marks.contains(.link("https://example.com/path")))

        // JSON 往返 + 再渲染仍保留
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(decoded))
        let rerendered = DocumentTextCodec.decode(DocumentTextCodec.render(restored), preserving: restored)
        XCTAssertEqual(rerendered.blocks[0].runs[0].marks, decoded.blocks[0].runs[0].marks)
    }

    // MARK: - 图片粘贴：data URL 附件块承载并往返

    func testPastedImageAttachmentRendersAsImageAndRoundTrips() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let cgImage = try XCTUnwrap(context.makeImage())
        let image = NSImage(cgImage: cgImage, size: NSSize(width: 2, height: 2))
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))

        let attachment = NativeAttachment(id: UUID(), name: "粘贴的图片.png",
                                          storedName: "data:image/png;base64," + png.base64EncodedString())
        let document = NativeDocument(blocks: [DocumentBlock(kind: .paragraph, runs: [
            DocumentRun(text: "前文 "), DocumentRun(text: "\u{FFFC}", attachment: attachment)
        ])])
        let rendered = DocumentTextCodec.render(document)
        // data URL 附件渲染成真实图片，而不是 📎 文本单元（“前文 ”为 3 个 UTF-16 单元，附件在其后）
        let textAttachment = try XCTUnwrap(rendered.attribute(.attachment, at: 3, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertNotNil(textAttachment.image)
        // data URL 不是文件路径：url(for:) 返回 nil，双击不会误打开
        XCTAssertNil(NativeAttachmentFiles.url(for: attachment))

        let decoded = DocumentTextCodec.decode(rendered, preserving: document)
        XCTAssertEqual(decoded.plainText, "前文 \u{FFFC}")
        XCTAssertEqual(decoded.blocks[0].runs[1].attachment, attachment)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(restored.blocks[0].runs[1].attachment, attachment)
        XCTAssertEqual(DocumentTextCodec.decode(DocumentTextCodec.render(restored), preserving: restored)
            .blocks[0].runs[1].attachment, attachment)

        // 缩放护栏：小于上限的图原样返回
        XCTAssertEqual(NativeTextView.normalizedPNG(png), png)
    }

    // MARK: - 工具

    private func makeTask(id: UUID, title: String, sourceNoteID: UUID?, deletedAt: Date? = nil) -> Task {
        Task(id: id, title: title, list: .inbox, priority: .none, schedule: TaskSchedule(),
             parentID: nil, childOrder: 0, createdAt: Date(timeIntervalSince1970: 0),
             updatedAt: Date(timeIntervalSince1970: 0), deletedAt: deletedAt, sourceNoteID: sourceNoteID)
    }
}
