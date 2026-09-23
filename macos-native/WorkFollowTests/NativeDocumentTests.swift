import XCTest
@testable import WorkFollow

final class NativeDocumentTests: XCTestCase {
    func testPlainTextCreatesParagraphBlocksAndRoundTripsNewlines() {
        let document = NativeDocument(plainText: "first\nsecond\n")

        XCTAssertEqual(document.blocks.map(\.kind), [.paragraph, .paragraph, .paragraph])
        XCTAssertEqual(document.plainText, "first\nsecond\n")
        XCTAssertEqual(document.blocks.map(\.plainText), ["first", "second", ""])
    }

    func testEmptyDocumentsReceiveIndependentParagraphIdentity() {
        let first = NativeDocument.empty
        let second = NativeDocument.empty

        XCTAssertTrue(first.isEmpty)
        XCTAssertNotEqual(first.blocks[0].id, second.blocks[0].id)
    }

    func testReplacingTextRetainsBlockIDsAroundAnEditedParagraph() {
        let original = NativeDocument(plainText: "first\nsecond\nthird")
        let updated = original.replacingPlainText("first\nsecond revised\nthird")

        XCTAssertEqual(updated.plainText, "first\nsecond revised\nthird")
        XCTAssertEqual(updated.blocks.map(\.id), original.blocks.map(\.id))
    }

    func testInsertionRetainsUnchangedParagraphIDs() {
        let original = NativeDocument(plainText: "first\nlast")
        let updated = original.replacingPlainText("new\nfirst\nlast")

        XCTAssertEqual(updated.blocks[1].id, original.blocks[0].id)
        XCTAssertEqual(updated.blocks[2].id, original.blocks[1].id)
        XCTAssertNotEqual(updated.blocks[0].id, original.blocks[0].id)
    }
}
