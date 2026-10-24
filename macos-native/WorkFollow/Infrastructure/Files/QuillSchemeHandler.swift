import Foundation
import WebKit

/// `workfollow-quill://` 自定义协议：编辑器 WebView 的全部资源都走它，
/// 全程离线（对齐 DrawioSchemeHandler 的口径：本机目录映射 + 路径穿越防护）。
final class QuillSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "workfollow-quill"
    /// 资源就绪后由宿主注入：bridge.html 所在的版本目录。
    var directory: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "editor",
              let directory else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let base = directory.standardizedFileURL
        let target = base.appendingPathComponent(url.path).standardizedFileURL
        guard target.path.hasPrefix(base.path + "/") else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        guard let data = try? Data(contentsOf: target) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime: String
        switch target.pathExtension {
        case "js": mime = "text/javascript"
        case "css": mime = "text/css"
        case "html": mime = "text/html"
        case "png": mime = "image/png"
        case "svg": mime = "image/svg+xml"
        default: mime = "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
