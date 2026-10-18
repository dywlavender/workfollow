import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-16b：格式工具条「更多」溢出菜单。
///
/// 滴答证据：`TTMDActionButtonsViewController.moreButtonClicked:`、资源 `md_more`。
/// 本地在工具条尾部给一个 `…` 菜单，窄列里横向滚动之外还有一条到达全部命令的出口。
@MainActor
final class DocumentToolbarOverflowTests: XCTestCase {

    func testOverflowListsResolveToRealCommands() {
        let ids = DocumentToolbarOverflow.paragraphIDs + DocumentToolbarOverflow.inlineIDs
        XCTAssertEqual(ids.count, 9)
        for id in ids {
            let command = EditorCommandCatalog.format(id)
            XCTAssertNotNil(command, "溢出菜单命令不存在：\(id)")
            XCTAssertFalse(command?.title.isEmpty ?? true, "命令缺标题：\(id)")
        }
        XCTAssertEqual(DocumentToolbarOverflow.paragraphIDs,
                       ["format.paragraph", "format.quote", "format.codeBlock"])
        XCTAssertEqual(DocumentToolbarOverflow.inlineIDs,
                       ["format.bold", "format.italic", "format.underline",
                        "format.strikethrough", "format.highlight", "format.inlineCode"])
    }

    func testToolbarStillLaysOutAtTheContractSize() {
        let host = NSHostingView(rootView: DocumentFormatToolbarView(handle: DocumentEditorHandle()))
        host.frame = NSRect(x: 0, y: 0, width: 444, height: 38)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 445, "工具条宽度仍受 444 契约约束")
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
