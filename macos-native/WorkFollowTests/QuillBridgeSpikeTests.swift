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
        let bridge = try await QuillResources.prepare(bundle: .main, cacheRoot: cacheRoot)
        // bridge 落在版本目录，quill 运行时在其旁边解压就位。
        XCTAssertEqual(bridge.lastPathComponent, "bridge.html")
        let runtimeJS = bridge.deletingLastPathComponent().appendingPathComponent("quill/quill.js")
        let js = try String(contentsOf: runtimeJS, encoding: .utf8)
        XCTAssertTrue(js.hasPrefix("/*! For license information"), "解压出的应是 Quill 官方分发")
        try? FileManager.default.removeItem(at: cacheRoot)
    }

    func testQuillBridgeHtmlShipsTheProtocol() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "QuillBridge", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        for needle in ["workfollowQuill", "deltaChanged", "escapePressed", "heightChanged",
                       "quill/quill.js", "quill/quill.snow.css"] {
            XCTAssertTrue(html.contains(needle), "bridge 缺少协议要素：\(needle)")
        }
    }
}
