import XCTest
@testable import WorkFollow

final class MilkdownDocumentCodecTests: XCTestCase {
    func testAllNativeFieldsAndMarksRoundTripWithoutSendingBinaryAssets() throws {
        let marks: Set<DocumentMark> = [.bold, .italic, .underline, .highlight, .strikethrough, .code,
            .link("https://example.com/中文"), .muted, .caption, .symbol(.calendar), .ink(.argb(0xff334455)),
            .textColor("#123456"), .highlightColor("#ffe98a")]
        let file = NativeAttachment(id: UUID(), name: "截图.png", storedName: "data:image/png;base64," + Data(repeating: 6, count: 1024).base64EncodedString(), displayWidth: 320.5, displayHeight: 160)
        let drawing = NativeDiagram(title: "流程图", xml: "<mxfile>原图资料</mxfile>", previewPNG: Data([1, 2, 3]))
        let source = NativeDocument(blocks: [
            DocumentBlock(kind: .paragraph, runs: [.init(text: "全部样式", marks: marks)], indentLevel: 2, align: .justify, bodySize: .large),
            DocumentBlock(kind: .heading(5), runs: [.init(text: "标题")]),
            DocumentBlock(kind: .bullet, runs: [.init(text: "无序")], indentLevel: 3),
            DocumentBlock(kind: .ordered, runs: [.init(text: "有序")], listStart: 9),
            DocumentBlock(kind: .checklist(true), runs: [.init(text: "检查项")], checklist: .init(completedAt: Date(timeIntervalSinceReferenceDate: 400), reminderAt: Date(timeIntervalSinceReferenceDate: 800), allDay: true)),
            DocumentBlock(kind: .quote, runs: [.init(text: "引用")]),
            DocumentBlock(kind: .code, runs: [.init(text: "let a = 1")]),
            DocumentBlock(kind: .divider),
            DocumentBlock(kind: .paragraph, runs: [.init(text: "\u{fffc}", attachment: file), .init(text: "\u{fffc}", diagram: drawing),
                .init(text: "\u{fffc}", table: .empty()), .init(text: "\u{fffc}", formula: .init(latex: "\\frac{1}{2}"))]),
        ])
        var codec = MilkdownDocumentCodec()
        let wire = try codec.encode(source)
        XCTAssertEqual(try codec.decode(wire), source)
        let json = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
        XCTAssertFalse(json.contains("原图资料")); XCTAssertFalse(json.contains("base64,"))
        XCTAssertEqual(wire.blocks.map(\.id), source.blocks.map(\.id))
    }

    func testEmbedEditingRetainsNativeFileAndDiagramPayloads() throws {
        let image = NativeAttachment(id: UUID(), name: "图片.png", storedName: "data:image/png;base64,AQID")
        let drawing = NativeDiagram(title: "原名", xml: "原始 XML", previewPNG: Data([4, 5, 6]))
        let source = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", attachment: image), .init(text: "\u{fffc}", diagram: drawing)])])
        var codec = MilkdownDocumentCodec(), wire = try codec.encode(source)
        wire.blocks[0].runs[0].embed?.width = 400; wire.blocks[0].runs[0].embed?.height = 200
        wire.blocks[0].runs[1].embed?.name = "新图名"
        let decoded = try codec.decode(wire)
        XCTAssertEqual(decoded.blocks[0].runs[0].attachment?.storedName, image.storedName)
        XCTAssertEqual(decoded.blocks[0].runs[0].attachment?.displayWidth, 400)
        XCTAssertEqual(decoded.blocks[0].runs[1].diagram?.xml, drawing.xml)
        XCTAssertEqual(decoded.blocks[0].runs[1].diagram?.previewPNG, drawing.previewPNG)
        XCTAssertEqual(decoded.blocks[0].runs[1].diagram?.title, "新图名")
    }

    func testPersistedDeltaStillLoadsAndSavesThroughTheSameFormat() throws {
        let old = NativeDocument(blocks: [.init(kind: .heading(2), runs: [.init(text: "旧资料", marks: [.bold])]),
            .init(kind: .checklist(false), runs: [.init(text: "旧检查项")], checklist: .init(reminderAt: Date(timeIntervalSinceReferenceDate: 1234)))])
        let persisted = try JSONEncoder().encode(old)
        let canonical = try JSONDecoder().decode(NativeDocument.self, from: persisted)
        var codec = MilkdownDocumentCodec()
        var wire = try codec.encode(canonical)
        wire.blocks[0].runs[0].text += " 已编辑"
        let next = try codec.decode(wire)
        let output = try JSONEncoder().encode(next)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertNotNil(object["ops"]); XCTAssertNil(object["blocks"])
        let restored = try JSONDecoder().decode(NativeDocument.self, from: output)
        XCTAssertTrue(restored.plainText.contains("旧资料 已编辑"))
        XCTAssertEqual(restored.blocks.last?.checklist?.reminderAt, canonical.blocks.last?.checklist?.reminderAt)
    }

    func testResizedImageSurvivesMilkdownAndFullNativeDocumentJSONRoundTrip() throws {
        let image = NativeAttachment(id: UUID(), name: "调整后的图片.png", storedName: "data:image/png;base64,AQID",
                                     displayWidth: 320.5, displayHeight: 160.25)
        let original = NativeDocument(blocks: [
            .init(kind: .heading(2), runs: [.init(text: "图片说明", marks: [.bold])]),
            .init(kind: .paragraph, runs: [.init(text: "前文"), .init(text: "\u{fffc}", attachment: image), .init(text: "后文")])
        ])
        var codec = MilkdownDocumentCodec()
        let wire = try codec.encode(original)
        let edited = try codec.decode(wire)
        let data = try JSONEncoder().encode(edited)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["blocks"])
        let ops = try XCTUnwrap(json["ops"] as? [[String: Any]])
        let embed = try XCTUnwrap(ops.compactMap { ($0["insert"] as? [String: Any])?["workfollow-block"] as? [String: Any] }.first)
        XCTAssertEqual(embed["displayWidth"] as? Double, 320.5)
        XCTAssertEqual(embed["displayHeight"] as? Double, 160.25)
        let restored = try JSONDecoder().decode(NativeDocument.self, from: data)
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.blocks[1].runs[1].attachment, image)
        var reopenedCodec = MilkdownDocumentCodec()
        let reopenedWire = try reopenedCodec.encode(restored)
        XCTAssertEqual(try reopenedCodec.decode(reopenedWire), original)
    }

    func testOldAttachmentDeltaAndInvalidSizesRemainReadableWithoutMigration() throws {
        let invalidFields = ["", ",\"displayWidth\":300", ",\"displayWidth\":0,\"displayHeight\":200",
                             ",\"displayWidth\":300,\"displayHeight\":-1",
                             ",\"displayWidth\":\"invalid\",\"displayHeight\":200"]
        for fields in invalidFields {
            let json = """
            {"ops":[{"insert":{"workfollow-block":{"type":"attachment","id":"AAAAAAAA-BBBB-CCCC-DDDD-000000000001","name":"旧图片","storedName":"data:image/png;base64,AQID"\(fields)}}},{"insert":"\\n"}],"plainText":""}
            """
            let restored = try JSONDecoder().decode(NativeDocument.self, from: Data(json.utf8))
            let file = try XCTUnwrap(restored.blocks[0].runs[0].attachment)
            XCTAssertNil(file.displayWidth, fields)
            XCTAssertNil(file.displayHeight, fields)
            XCTAssertEqual(file.name, "旧图片")
            XCTAssertEqual(try JSONDecoder().decode(NativeDocument.self, from: JSONEncoder().encode(restored)), restored)
        }
    }

    func testInvalidNativeAttachmentSizeIsOmittedFromDeltaJSON() throws {
        for (width, height) in [(Double.nan, 200.0), (300.0, .infinity), (0.0, 200.0), (300.0, 0.5)] {
            let image = NativeAttachment(id: UUID(), name: "图片", storedName: "data:image/png;base64,AQID",
                                         displayWidth: width, displayHeight: height)
            let document = NativeDocument(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", attachment: image)])])
            let data = try JSONEncoder().encode(document)
            let restored = try JSONDecoder().decode(NativeDocument.self, from: data)
            XCTAssertNil(restored.blocks[0].runs[0].attachment?.displaySize)
            let json = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(json.contains("displayWidth")); XCTAssertFalse(json.contains("displayHeight"))
        }
    }

    func testDrawingHistoryKeepsEachNativePayloadVersion() throws {
        let first = NativeDiagram(title: "原图", xml: "第一版", previewPNG: Data([1]))
        var next = first; next.xml = "第二版"; next.previewPNG = Data([2])
        func document(_ drawing: NativeDiagram) -> NativeDocument {
            .init(blocks: [.init(kind: .paragraph, runs: [.init(text: "\u{fffc}", diagram: drawing)])])
        }
        var codec = MilkdownDocumentCodec()
        let original = document(first), updated = document(next)
        let before = try codec.encode(original), after = try codec.encode(updated)
        XCTAssertNotEqual(before.blocks[0].runs[0].embed?.assetKey, after.blocks[0].runs[0].embed?.assetKey)
        XCTAssertEqual(try codec.decode(before), original)
        XCTAssertEqual(try codec.decode(after), updated)
    }
}
