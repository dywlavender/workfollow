import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 正文格式工具条的「插入」浮条：固定在最右，只放入插入类动作。
/// （文件名沿用旧“溢出”测试，避免工程文件引用变动。）
@MainActor
final class DocumentToolbarInsertTests: XCTestCase {

    func testInsertCatalogCoversAllExistingInsertActions() {
        let items = DocumentInsertCatalog.items
        XCTAssertEqual(items.map(\.id),
                       ["insert.image", "insert.table", "insert.formula", "insert.link",
                        "insert.codeBlock", "insert.divider", "insert.quote",
                        "insert.attachment", "insert.diagram"])
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "插入项 id 不得重复")
        for item in items {
            XCTAssertFalse(item.title.isEmpty, "插入项缺标题：\(item.id)")
            XCTAssertFalse(item.symbol.isEmpty, "插入项缺图标：\(item.id)")
        }
        // 代码块 / 引用复用既有格式命令。
        XCTAssertEqual(EditorCommandCatalog.format("format.codeBlock")?.title, "代码块")
        XCTAssertEqual(EditorCommandCatalog.format("format.quote")?.title, "引用")
    }

    func testToolbarStillLaysOutAtTheContractSize() {
        let host = NSHostingView(rootView: DocumentFormatToolbarView(handle: DocumentEditorHandle()))
        host.frame = NSRect(x: 0, y: 0, width: 444, height: 38)
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, 445, "工具条宽度仍受 444 契约约束")
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}
