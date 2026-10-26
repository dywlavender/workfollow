import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class DocumentRTFStructureCodecTests: XCTestCase {
    func testDirectOutlineMetadataRestoresHeadingAndBody() throws {
        let data = rtf(#"\pard\outlinelevel1 Heading\par\pard Body"#)
        let value = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: data))
        XCTAssertEqual(value.string, "Heading\nBody")
        XCTAssertEqual(levels(value), [2, 0])
    }

    func testWordStylesheetUsesRealStyleLevelAndInheritance() throws {
        let table = #"{\stylesheet{\s0 Normal;}{\s17\outlinelevel2 Heading 3;}{\s29\sbasedon17 Custom section;}}"#
        let value = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from:
            rtf(table + #"\pard\s29 Section\par\pard\s0 Body"#)))
        XCTAssertEqual(levels(value), [3, 0])
        XCTAssertEqual(value.string, "Section\nBody")
    }

    func testNamedHeadingStylesSupportUnicodeWithoutGuessingNumericStyleIDs() throws {
        let table = #"{\stylesheet{\s1 Big text;}{\s45 Heading 2;}{\s72\uc1\u26631?\u39064? 1;}}"#
        let body = #"\pard\s1\b\fs60 Large\par\pard\s45 English\par\pard\s72\u20013?\u25991?"#
        let value = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: rtf(table + body)))
        XCTAssertEqual(value.string, "Large\nEnglish\n中文")
        XCTAssertEqual(levels(value), [0, 2, 1], "An arbitrary s1 or bold large font is not heading metadata")
    }

    func testCocoaExportRoundTripsChineseUnicodeHeadingBodyAndListFormatting() throws {
        let value = NSMutableAttributedString(string: "中文标题 🧭\n普通正文\n第一项\n第二项")
        let text = value.string as NSString
        let first = text.paragraphRange(for: NSRange(location: 0, length: 0))
        let heading = NSMutableParagraphStyle(); heading.headerLevel = 2
        value.addAttributes([.paragraphStyle: heading, .font: NSFont.boldSystemFont(ofSize: 18)], range: first)
        let body = text.paragraphRange(for: NSRange(location: NSMaxRange(first), length: 0))
        value.addAttributes([.paragraphStyle: NSParagraphStyle.default, .font: NSFont.systemFont(ofSize: 14)], range: body)
        let list = NSTextList(markerFormat: .decimal, options: 0)
        let listStyle = NSMutableParagraphStyle(); listStyle.textLists = [list]
        let listStart = NSMaxRange(body)
        value.addAttribute(.paragraphStyle, value: listStyle, range: NSRange(location: listStart, length: value.length - listStart))
        let data = try XCTUnwrap(DocumentRTFStructureCodec.data(from: value))
        let read = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: data))
        XCTAssertEqual(levels(read), [2, 0, 0, 0])
        XCTAssertTrue(read.string.hasPrefix("中文标题 🧭\n普通正文\n"))
        let listLocation = (read.string as NSString).range(of: "第一项").location
        let readStyle = try XCTUnwrap(read.attribute(.paragraphStyle, at: listLocation, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(readStyle.textLists.last?.markerFormat, .decimal)
        let font = try XCTUnwrap(read.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testConsecutiveHeadingsAndEmptyParagraphsKeepCorrectBoundaries() throws {
        let value = NSMutableAttributedString(string: "一\n\n二\n正文\n")
        let first = NSMutableParagraphStyle(); first.headerLevel = 1
        let second = NSMutableParagraphStyle(); second.headerLevel = 3
        value.addAttribute(.paragraphStyle, value: first, range: NSRange(location: 0, length: 2))
        value.addAttribute(.paragraphStyle, value: second, range: NSRange(location: 3, length: 2))
        let data = try XCTUnwrap(DocumentRTFStructureCodec.data(from: value))
        let read = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: data))
        XCTAssertEqual(read.string, value.string)
        XCTAssertEqual(levels(read), [1, 0, 3, 0])
    }

    func testOrdinaryBoldLargeTextIsNotInventedAsHeading() throws {
        let value = NSAttributedString(string: "普通大号粗体", attributes: [.font: NSFont.boldSystemFont(ofSize: 30)])
        let data = try XCTUnwrap(DocumentRTFStructureCodec.data(from: value))
        let read = try XCTUnwrap(DocumentRTFStructureCodec.attributedString(from: data))
        XCTAssertEqual(read.string, value.string)
        XCTAssertEqual(levels(read), [0])
    }

    private func rtf(_ body: String) -> Data {
        Data((#"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0 "# + body + "}").utf8)
    }

    private func levels(_ value: NSAttributedString) -> [Int] {
        let text = value.string as NSString
        var result: [Int] = [], offset = 0
        while offset < value.length {
            result.append((value.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0)
            offset = NSMaxRange(text.paragraphRange(for: NSRange(location: offset, length: 0)))
        }
        return result
    }
}
