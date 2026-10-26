import XCTest
@testable import WorkFollow

/// P1 转换器契约：`NativeDocument ↔ Quill Delta` 往返无损 + 旧档兼容读 +
/// 持久化新形态。内核切换后所有既有数据走这条链，必须钉死。
final class QuillDeltaCodecTests: XCTestCase {
    private func assertRoundTrip(_ document: NativeDocument,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let ops = QuillDeltaCodec.delta(from: document)
        let restored = QuillDeltaCodec.document(from: ops)
        if restored != document {
            print("== 原始 ==")
            document.blocks.forEach { print("  \($0.kind) id=\($0.id) runs=\($0.runs)") }
            print("== 还原 ==")
            restored.blocks.forEach { print("  \($0.kind) id=\($0.id) runs=\($0.runs)") }
        }
        XCTAssertEqual(restored, document, "往返必须无损", file: file, line: line)
        XCTAssertEqual(QuillDeltaCodec.plainText(of: ops), document.plainText,
                       "纯文本投影必须逐字节一致", file: file, line: line)
    }

    func testPlainParagraphsRoundTrip() {
        assertRoundTrip(NativeDocument(plainText: "第一行\n第二行\n\n第四行"))
    }

    func testExistingQuillImageEmbedSurvivesOpeningAndSavingNatively() throws {
        let source = "data:image/png;base64,iVBORw0KGgo="
        let document = QuillDeltaCodec.document(from: [
            QuillDeltaOp(insert: .object(["image": .string(source)])),
            QuillDeltaOp(insert: .string("\n"))
        ])
        let attachment = try XCTUnwrap(document.blocks.first?.runs.first?.attachment)
        XCTAssertEqual(attachment.storedName, source)
        let reopened = try JSONDecoder().decode(NativeDocument.self,
            from: JSONEncoder().encode(document))
        XCTAssertEqual(reopened, document)
        XCTAssertEqual(reopened.blocks.first?.runs.first?.attachment, attachment)
    }

    func testEveryBlockKindRoundTrips() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文")]),
            DocumentBlock(kind: .bullet, runs: [DocumentRun(text: "无序项")]),
            DocumentBlock(kind: .ordered, runs: [DocumentRun(text: "有序项")]),
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "待办")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成")]),
            DocumentBlock(kind: .quote, runs: [DocumentRun(text: "引用")]),
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "let x = 1")]),
            DocumentBlock(kind: .code, runs: [DocumentRun(text: "let y = 2")]),
            DocumentBlock(kind: .divider, runs: [DocumentRun(text: "\u{FFFC}")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "")])
        ])
        assertRoundTrip(document)
    }

    func testEveryInlineMarkRoundTrips() {
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "粗体", marks: [.bold]),
                DocumentRun(text: "斜体", marks: [.italic]),
                DocumentRun(text: "下划线", marks: [.underline]),
                DocumentRun(text: "删除线", marks: [.strikethrough]),
                DocumentRun(text: "高亮", marks: [.highlight]),
                DocumentRun(text: "代码", marks: [.code]),
                DocumentRun(text: "链接", marks: [.link("https://example.com")]),
                DocumentRun(text: "组合", marks: [.bold, .italic, .highlight])
            ])
        ])
        assertRoundTrip(document)
    }

    func testAttachmentAndDiagramEmbedsRoundTrip() {
        let diagram = NativeDiagram(id: UUID(), title: "架构图",
                                    xml: "<mxfile>…</mxfile>",
                                    previewPNG: Data([0x89, 0x50, 0x4E, 0x47]))
        let attachment = NativeAttachment(id: UUID(), name: "周报.pdf", storedName: "abc.pdf")
        let document = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [
                DocumentRun(text: "附件："),
                DocumentRun(text: "\u{FFFC}", attachment: attachment),
                DocumentRun(text: " 图："),
                DocumentRun(text: "\u{FFFC}", diagram: diagram)
            ])
        ])
        assertRoundTrip(document)
    }

    func testChineseAndEmptyDocumentsRoundTrip() {
        assertRoundTrip(NativeDocument(plainText: ""))
        assertRoundTrip(NativeDocument(plainText: "中文内容\n混合 English 与 123\n\n尾行"))
    }

    // MARK: 持久化形态

    func testEncodingUsesDeltaCanonicalForm() throws {
        let document = NativeDocument(plainText: "标题行\n清单项")
        let data = try JSONEncoder().encode(document)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"ops\":"), "持久化应为 Delta 真源形态")
        XCTAssertTrue(json.contains("\"plainText\":"), "双轨投影 plainText 应随行")
        XCTAssertFalse(json.contains("\"blocks\":"), "不应再写旧形态")
    }

    func testLegacyBlocksSnapshotStillDecodes() throws {
        // 旧档形态 {blocks:[…]}（历史 workspace.json / 导入包）必须可读。
        let legacy = """
        {"blocks":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-000000000001","kind":{"heading":{"_0":2}},
        "runs":[{"text":"旧档标题","marks":[]}]},
        {"id":"AAAAAAAA-BBBB-CCCC-DDDD-000000000002","kind":{"paragraph":{}},
        "runs":[{"text":"旧档正文","marks":[]}]}]}
        """
        let document = try JSONDecoder().decode(NativeDocument.self, from: Data(legacy.utf8))
        XCTAssertEqual(document.plainText, "旧档标题\n旧档正文")
        XCTAssertEqual(document.blocks.first?.kind, .heading(2))
        XCTAssertEqual(document.blocks.last?.kind, .paragraph)
    }

    func testDeltaFormDecodesBackThroughCodec() throws {
        let original = NativeDocument(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "任务")])
        ])
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: data)
        XCTAssertEqual(restored, original)
    }

    func testDecodingIgnoresUnknownAttributesAndEmbeds() throws {
        // 内核演进宽容度：未知属性 / 未知 embed 不炸档。
        let future = """
        {"ops":[{"insert":"文本\\n","attributes":{"bold":true,"future-mark":"x"}},
        {"insert":{"workfollow-block":{"type":"new-thing"}}},
        {"insert":"\\n"}],"plainText":"文本\\n"}
        """
        let document = try JSONDecoder().decode(NativeDocument.self, from: Data(future.utf8))
        XCTAssertEqual(document.blocks.first?.runs.first?.marks, [.bold])
        XCTAssertEqual(document.plainText, "文本\n[new-thing]")
    }
}
