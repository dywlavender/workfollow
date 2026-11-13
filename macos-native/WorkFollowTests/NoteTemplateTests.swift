import XCTest
@testable import WorkFollow

@MainActor
final class NoteTemplateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - kind 精确过滤与 additive 兼容

    func testCatalogFiltersByKindPrecisely() {
        let task = TaskTemplate(name: "任务模板 A", title: "任务", createdAt: now)
        let summary = TaskTemplate(name: "摘要模板 A", title: "摘要", createdAt: now, kind: "summary")
        let note = TaskTemplate(name: "笔记模板 A", title: "笔记", createdAt: now, kind: "note")

        let noteItems = TaskTemplateCatalog.items(
            userTemplates: [task, summary, note],
            builtIns: BuiltInNoteTemplates.all,
            kind: .note)
        XCTAssertEqual(noteItems.map(\.source), [.builtIn, .builtIn, .builtIn, .builtIn, .builtIn, .user])
        XCTAssertEqual(noteItems.last?.id, note.id)
        XCTAssertTrue(noteItems.allSatisfy { $0.template.templateKind == .note })

        let taskItems = TaskTemplateCatalog.items(
            userTemplates: [task, summary, note],
            builtIns: BuiltInTaskTemplates.all,
            kind: .task)
        XCTAssertEqual(taskItems.map(\.source), [.builtIn, .builtIn, .builtIn, .user])
        XCTAssertEqual(taskItems.last?.id, task.id)
        XCTAssertTrue(taskItems.allSatisfy { $0.template.templateKind == .task })
    }

    func testLegacyTemplateWithoutKindDecodesAsTaskNotNote() throws {
        let legacy = """
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","name":"站会","title":"站会",
        "document":{"blocks":[]},"tags":[],"childTitles":[],
        "createdAt":0}
        """
        let template = try JSONDecoder().decode(TaskTemplate.self, from: Data(legacy.utf8))
        XCTAssertNil(template.kind)
        XCTAssertFalse(template.isNoteTemplate)
        XCTAssertFalse(template.isSummaryTemplate)
        XCTAssertEqual(template.templateKind, .task)
    }

    func testNoteTemplateKindSurvivesRoundTrip() throws {
        let template = TaskTemplate(name: "笔记模板", title: "笔记模板",
                                    document: NativeDocument(plainText: "正文内容"),
                                    createdAt: now, kind: "note")
        XCTAssertTrue(template.isNoteTemplate)
        XCTAssertEqual(template.templateKind, .note)

        let decoded = try JSONDecoder().decode(TaskTemplate.self,
                                               from: JSONEncoder().encode(template))
        XCTAssertEqual(decoded.kind, "note")
        XCTAssertTrue(decoded.isNoteTemplate)
        XCTAssertEqual(decoded.document.plainText, "正文内容")
    }

    // MARK: - 内置笔记模板只在内存，不落盘

    func testBuiltInNoteTemplatesAreInMemoryOnly() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TemplateStore(directory: directory)
        XCTAssertTrue(store.templates.isEmpty)

        let items = TaskTemplateCatalog.items(userTemplates: store.templates,
                                              builtIns: BuiltInNoteTemplates.all,
                                              kind: .note)
        XCTAssertEqual(items.map(\.source), Array(repeating: .builtIn, count: 5))
        XCTAssertEqual(store.templates.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("templates.json").path))

        // 目录按内置数组的声明顺序展示（会议纪要、周报、每日记录、读书笔记、项目复盘）。
        XCTAssertEqual(BuiltInNoteTemplates.all.map(\.id), [
            UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000004")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000002")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000005")!,
            UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
        ])
        XCTAssertTrue(BuiltInNoteTemplates.all.allSatisfy { $0.isNoteTemplate })
        XCTAssertTrue(BuiltInNoteTemplates.all.allSatisfy { !$0.document.isEmpty })
    }

    // MARK: - saveNoteTemplate

    func testSaveNoteTemplateStoresKindTitleAndDocument() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TemplateStore(clock: { self.now }, directory: directory)
        let note = Note(id: UUID(), title: "我的笔记",
                        document: NativeDocument(plainText: "第一行\n第二行"),
                        folder: "未归档", updatedAt: now)

        XCTAssertTrue(store.saveNoteTemplate(name: "笔记模板 甲", from: note))
        let saved = try XCTUnwrap(store.template(named: "笔记模板 甲"))
        XCTAssertTrue(saved.isNoteTemplate)
        XCTAssertEqual(saved.templateKind, .note)
        XCTAssertEqual(saved.title, "我的笔记")
        XCTAssertEqual(saved.document.plainText, "第一行\n第二行")

        // 笔记模板不串到任务选择器；只出现在笔记选择器里。
        let taskItems = TaskTemplateCatalog.items(userTemplates: store.templates, kind: .task)
        XCTAssertFalse(taskItems.contains { $0.source == .user })
        let noteItems = TaskTemplateCatalog.items(userTemplates: store.templates,
                                                  builtIns: BuiltInNoteTemplates.all,
                                                  kind: .note)
        XCTAssertTrue(noteItems.contains { $0.source == .user && $0.template.name == "笔记模板 甲" })

        XCTAssertFalse(store.saveNoteTemplate(name: "  ", from: note))
        XCTAssertFalse(store.saveNoteTemplate(name: "笔记模板 甲", from: note))
    }

    // MARK: - create(title:document:) 把模板正文写进新笔记

    func testCreateWithTitleAndDocumentWritesTemplateBody() throws {
        let notes = NotesWorkspaceModel()
        let template = try XCTUnwrap(BuiltInNoteTemplates.all.first)

        let id = notes.create(title: template.title, document: template.document)
        let note = try XCTUnwrap(notes.notes.first { $0.id == id })

        XCTAssertEqual(note.title, template.title)
        XCTAssertEqual(note.document.plainText, template.document.plainText)
        XCTAssertEqual(note.document.blocks.map(\.kind), template.document.blocks.map(\.kind))
        XCTAssertEqual(notes.selectedID, id)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteTemplateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
