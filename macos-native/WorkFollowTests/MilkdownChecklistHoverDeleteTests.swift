import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import WorkFollow

/// 生产笔记编辑器（Milkdown / WKWebView）里「检查项行尾 hover 删除」的行为契约。
/// 旧 NativeTextView 的同名功能由 ChecklistEditorInteractionTests 覆盖，两者不是同一条链路，
/// 所以这里从头构造真实的 DocumentEditor + WebKit 编辑器来验证。
@MainActor
final class MilkdownChecklistHoverDeleteTests: XCTestCase {
    @MainActor final class Model: ObservableObject {
        @Published var id = UUID()
        @Published var document = NativeDocument(plainText: "")
        let handle = DocumentEditorHandle()
        var profile = DocumentProfile()
    }

    struct Host: View {
        @ObservedObject var model: Model
        var readOnly = false
        var body: some View {
            DocumentEditor(documentID: model.id, document: model.document,
                onDocumentChange: { model.document = $0 }, onEscape: { .keepInspector },
                onEditingChanged: { _ in }, profile: model.profile,
                contentSized: false, handle: model.handle, readOnly: readOnly)
                .frame(width: 700, height: 460)
        }
    }

    private func wait(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "MilkdownChecklistHoverDelete", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func fixture(readOnly: Bool = false,
                         blocks: [DocumentBlock]) async throws -> (Model, MilkdownWebView) {
        let model = Model()
        model.document = NativeDocument(blocks: blocks)
        let host = NSHostingView(rootView: Host(model: model, readOnly: readOnly))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 720, height: 480)
        addTeardownBlock { @MainActor in window.contentView = nil; window.close() }
        try await wait("编辑器未加载：\(model.handle.webView?.loadError ?? "等待 WebKit")") {
            model.handle.webView?.isDocumentReady == true
        }
        return (model, try XCTUnwrap(model.handle.webView))
    }

    private func count(_ view: MilkdownWebView, _ selector: String) throws -> Int {
        let value = try MilkdownTestSupport.script(view, "document.querySelectorAll('\(selector)').length")
        return try XCTUnwrap(value as? NSNumber).intValue
    }

    private static let threeBlocks: [DocumentBlock] = [
        DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "甲")]),
        DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "普通段落")]),
        DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "乙")])
    ]

    /// 删除按钮只属于可编辑的检查项行，且默认隐藏（hover 才出现）。
    func testDeleteButtonOnlyAppearsOnEditableChecklistBlocks() async throws {
        let (_, view) = try await fixture(blocks: Self.threeBlocks)
        XCTAssertEqual(try count(view, ".wf-checklist .wf-delete:not([hidden])"), 2)
        XCTAssertEqual(try count(view, ".wf-delete:not([hidden])"), 2, "普通段落不该有删除按钮")
        let opacity = try MilkdownTestSupport.script(view,
            "getComputedStyle(document.querySelector('.wf-checklist .wf-delete')).opacity") as? String
        XCTAssertEqual(opacity, "0", "默认不显示；CSS 只在该行 hover 时把 opacity 切到 1")
        let label = try MilkdownTestSupport.script(view,
            "document.querySelector('.wf-checklist .wf-delete').getAttribute('aria-label')") as? String
        XCTAssertEqual(label, "删除检查事项")
        // 真实指针的 :hover 需要解锁会话才能验；这里至少确认 CSSOM 里规则已加载，
        // 与既有 .wf-reminder / .wf-block-handle 的 hover 规则同构。
        // CSSOM 会把选择器规范化成 ".wf-block:hover > .wf-delete"（带空格），
        // 所以按语义匹配而不是写死字面串。
        let selectors = try MilkdownTestSupport.script(view, """
            Array.from(document.styleSheets).flatMap(s => { try {
              return Array.from(s.cssRules).filter(r => r.selectorText && r.selectorText.includes('wf-delete'))
                .map(r => r.selectorText);
            } catch (e) { return []; } })
            """) as? [String]
        let hasHoverRule = selectors?.contains { $0.contains(":hover") && $0.contains(".wf-delete") } ?? false
        XCTAssertTrue(hasHoverRule, "CSS 必须包含 hover 显示删除按钮的规则")
    }

    /// 删整项 → 写回 NativeDocument；undo 能整项恢复。
    func testClickingDeleteRemovesWholeChecklistBlockAndUndoRestoresIt() async throws {
        let (model, view) = try await fixture(blocks: Self.threeBlocks)
        XCTAssertEqual(model.document.blocks.count, 3)
        try MilkdownTestSupport.script(view,
            "document.querySelectorAll('.wf-checklist .wf-delete')[0].click()")
        try await wait("删除未写回 NativeDocument") { model.document.blocks.count == 2 }
        XCTAssertFalse(model.document.plainText.contains("甲"), "整项（含文字）要一起删掉")
        XCTAssertTrue(model.document.plainText.contains("普通段落"))
        XCTAssertTrue(model.document.plainText.contains("乙"))
        try MilkdownTestSupport.command(view, "undo")
        try await wait("undo 未恢复被删的检查项") { model.document.blocks.count == 3 }
        XCTAssertTrue(model.document.plainText.contains("甲"))
    }

    /// doc 的 content 约束是 wf_block+：删掉唯一一块不能留下空文档。
    func testDeletingOnlyChecklistBlockKeepsValidEmptyParagraph() async throws {
        let (model, view) = try await fixture(blocks: [
            DocumentBlock(kind: .checklist(false), runs: [DocumentRun(text: "唯一一项")])
        ])
        try MilkdownTestSupport.script(view, "document.querySelector('.wf-checklist .wf-delete').click()")
        try await wait("唯一块删除后未写回") { model.document.plainText.isEmpty }
        XCTAssertEqual(model.document.blocks.count, 1, "文档至少要有一个 wf_block")
        let first = try XCTUnwrap(model.document.blocks.first)
        XCTAssertEqual(first.kind, .paragraph, "唯一的检查项应降级为空段落而不是删到文档非法")
    }

    /// 只读预览不该出现删除入口（由 CSS .wf-readonly 控制，不依赖构造时的 editable()）。
    func testReadOnlyEditorHidesDeleteButton() async throws {
        let (_, view) = try await fixture(readOnly: true, blocks: Self.threeBlocks)
        let state = try MilkdownTestSupport.script(view, """
            (() => { const d = document.querySelector('.wf-checklist .wf-delete');
                     return { readonly: String(document.body.classList.contains('wf-readonly')),
                              display: getComputedStyle(d).display }; })()
            """) as? [String: Any]
        XCTAssertEqual(state?["readonly"] as? String, "true")
        XCTAssertEqual(state?["display"] as? String, "none", "只读时由 CSS 隐藏删除入口")
    }

    /// 回归：NodeView 首次构造时若因 current/settings 未就绪把删除按钮设成 hidden，
    /// 之后 configure() 必须把它刷回来。真机上曾因此表现为「笔记里根本没这个功能」——
    /// configure 原本只刷 marker / handle / reminder，漏了新加的删除按钮。
    func testConfigureRestoresDeleteButtonAfterHiddenInitialState() async throws {
        let (_, view) = try await fixture(blocks: Self.threeBlocks)
        try MilkdownTestSupport.script(view,
            "document.querySelectorAll('.wf-delete').forEach(b => { b.hidden = true; })")
        XCTAssertEqual(try count(view, ".wf-delete:not([hidden])"), 0, "先造出构造时序造成的错误初态")
        try MilkdownTestSupport.call(view, "configure", [:])
        XCTAssertEqual(try count(view, ".wf-checklist .wf-delete:not([hidden])"), 2,
                       "configure 必须一并刷新删除按钮")
        XCTAssertEqual(try count(view, ".wf-delete:not([hidden])"), 2,
                       "普通段落的删除按钮仍应隐藏")
    }

    /// 铃铛与删除按钮的几何是 CSS 常驻固定的：不依赖 bridge 配置的到达时机，
    /// 也不随 hover 变化。曾试过按 settings 切 class，NodeView 首次构造早于
    /// configure()，文档未变时 update() 不会重跑，class 永远加不上。
    func testTrailingButtonsKeepFixedNonOverlappingGeometry() async throws {
        let (_, view) = try await fixture(blocks: Self.threeBlocks)
        let geometry = try MilkdownTestSupport.script(view, """
            (() => { const b = document.querySelector('.wf-checklist'),
                           r = b.querySelector('.wf-reminder'),
                           d = b.querySelector('.wf-delete');
                     return { padding: getComputedStyle(b).paddingRight,
                              reminderRight: getComputedStyle(r).right,
                              deleteRight: getComputedStyle(d).right }; })()
            """) as? [String: Any]
        XCTAssertEqual(geometry?["padding"] as? String, "50px", "两个按钮位常驻预留")
        XCTAssertEqual(geometry?["reminderRight"] as? String, "26px", "铃铛固定让位到删除左侧")
        XCTAssertEqual(geometry?["deleteRight"] as? String, "2px")
        let overlap = try MilkdownTestSupport.script(view, """
            (() => { const d = document.querySelector('.wf-delete').getBoundingClientRect(),
                           r = document.querySelector('.wf-reminder').getBoundingClientRect();
                     return d.left < r.right && r.left < d.right; })()
            """) as? Bool
        XCTAssertEqual(overlap, false, "两个按钮不能重叠")
    }

    /// 视觉预览：用 WKWebView 官方 takeSnapshot 抓真实 Web 内容，不依赖锁屏/前台。
    /// 注意：这里用 JS 把按钮强制成 opacity:1 来**模拟** hover 后的样子，
    /// 不是 CSS :hover 的真实验收（真实指针验收需解锁会话后另做）。
    func testRenderHoverPreviewSnapshot() async throws {
        let (_, view) = try await fixture(blocks: Self.threeBlocks)
        try MilkdownTestSupport.script(view, """
            (() => { const d = document.querySelectorAll('.wf-checklist')[0].querySelector('.wf-delete');
                     d.style.opacity = '1'; d.style.pointerEvents = 'auto'; return true; })()
            """)
        var image: NSImage?
        view.webView.takeSnapshot(with: WKSnapshotConfiguration()) { img, _ in image = img }
        try await wait("WebKit 截图未完成") { image != nil }
        // takeSnapshot 返回的 NSImage 内部是 WebKit 私有快照 rep，不能直接强转。
        let tiff = try XCTUnwrap(try XCTUnwrap(image).tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/tmp/wf-hover-preview-milkdown.png")
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 1000, "预览截图应包含真实 Web 内容：\(url.path)")
    }
}
