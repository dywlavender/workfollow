import Foundation
import WebKit
import UniformTypeIdentifiers

/// WebKit loads an offline, same-origin application without a localhost server
/// or file-URL sandbox grants to its auxiliary processes.
final class DrawioSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "workfollow-drawio"
    var directory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let directory, let url = urlSchemeTask.request.url,
              url.host == "editor" else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let file = directory.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(directory.standardizedFileURL.path + "/"),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let mime: String
        switch file.pathExtension.lowercased() {
        case "js": mime = "text/javascript"
        case "css": mime = "text/css"
        case "html": mime = "text/html"
        default: mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime + (mime.hasPrefix("text/") ? "; charset=utf-8" : ""),
            "Access-Control-Allow-Origin": "*"
        ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
