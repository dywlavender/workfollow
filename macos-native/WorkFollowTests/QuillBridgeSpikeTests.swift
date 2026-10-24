import Combine
import WebKit
import XCTest
@testable import WorkFollow

/// P0 骨架验收。
///
/// ⚠️ 内核/桥的**运行时验证在真 app 进程**做（Debug 菜单 → 「Quill 内核 Spike」）：
/// 隔离测试 runner 未签名，WKWebView 的 WebContent 子进程在它下面拿不到
/// sandbox extension 会直接崩（Abort trap 6），不可作为 WebView 宿主。
/// 这里只覆盖与 WKWebView 无关的部分：运行时资源的解包与版本化。
@MainActor
final class QuillBridgeSpikeTests: XCTestCase {
    func testQuillRuntimeUnpacksAndIsVersioned() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-spike-\(UUID().uuidString)")
        let index = try await QuillResources.prepare(bundle: .main, cacheRoot: cacheRoot)
        // 入口页落在版本目录，quill 运行时在其旁边解压就位。
        XCTAssertEqual(index.lastPathComponent, "index.html")
        let runtimeJS = index.deletingLastPathComponent().appendingPathComponent("quill/quill.js")
        let js = try String(contentsOf: runtimeJS, encoding: .utf8)
        XCTAssertTrue(js.hasPrefix("/*! For license information"), "解压出的应是 Quill 官方分发")
        // 图标（滴答 Assets.car 提取）随包就位。
        for icon in ["icons/md_bold.png", "icons/md_orderList.png", "icons/md_arrow_down_alpha57.png",
                     "icons/wf_image.svg", "icons/wf_table.svg", "icons/wf_diagram.svg"] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: index.deletingLastPathComponent().appendingPathComponent(icon).path),
                "运行时缺图标：\(icon)")
        }
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    /// P2 Web 组件随包完整性：入口页 + 全部模块 + 协议要素。
    /// 运行时验证在真 app 进程（runner 无法承载 WebContent，见类注释）。
    func testQuillWebComponentsShipTheFullAssembly() throws {
        let html = try String(contentsOf: Bundle.main.url(forResource: "index", withExtension: "html")!, encoding: .utf8)
        for needle in ["quill/quill.js", "blots.js", "toolbar.js", "slash-menu.js",
                       "color-menu.js", "markdown.js", "bridge.js", "editor.css"] {
            XCTAssertTrue(html.contains(needle), "入口页缺少模块引用：\(needle)")
        }
        func webSource(_ name: String) throws -> String {
            try String(contentsOf: Bundle.main.url(forResource: name, withExtension: "js")!, encoding: .utf8)
        }
        let bridge = try webSource("bridge")
        for needle in ["workfollowQuill", "deltaChanged", "escapePressed", "heightChanged",
                       "requestAction", "WorkFollowSlashMenu", "WorkFollowMarkdown"] {
            XCTAssertTrue(bridge.contains(needle), "bridge 缺少协议要素：\(needle)")
        }
        let toolbar = try webSource("toolbar")
        // 滴答 19 钮 + drawio（保留项）：分组里的名字全集合。
        for name in ["color", "bold", "italic", "underline", "strike", "highlight",
                     "bullet", "ordered", "checklist", "blockquote", "code", "code-block",
                     "image", "attachment", "link", "table", "divider", "time", "more", "diagram"] {
            XCTAssertTrue(toolbar.contains("name: \"" + name + "\""), "工具条缺钮：\(name)")
        }
        let slash = try webSource("slash-menu")
        for title in ["文本", "标题1", "标题2", "标题3", "无序列表", "有序列表", "清单",
                      "引用", "代码块", "分割线", "图片", "附件", "表格", "流程图"] {
            XCTAssertTrue(slash.contains(title), "斜杠菜单缺项：\(title)")
        }
        let markdown = try webSource("markdown")
        // 滴答 8.0.80 口径的触发器要素。
        for needle in ["#{1,6}", "-\\s\\[x\\]", "blockquote", "::", "matchInline", "isFenceLine"] {
            XCTAssertTrue(markdown.contains(needle), "markdown 触发器缺要素：\(needle)")
        }
    }
}
