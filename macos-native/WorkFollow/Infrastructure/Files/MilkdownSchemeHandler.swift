import WebKit

@MainActor
final class MilkdownSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "workfollow-milkdown"
    var directory: URL?
    var asset: ((UUID) -> (Data, String)?)?
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        do {
            let data: Data, mime: String
            if url.pathComponents.contains("asset"), let id = UUID(uuidString: url.lastPathComponent), let value = asset?(id) {
                (data, mime) = value
            } else {
                guard let directory else { throw URLError(.fileDoesNotExist) }
                let file = directory.appendingPathComponent(url.path).standardizedFileURL
                guard file.path.hasPrefix(directory.standardizedFileURL.path + "/") else { throw URLError(.badURL) }
                data = try Data(contentsOf: file)
                mime = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
                    "woff2": "font/woff2", "woff": "font/woff", "ttf": "font/ttf", "png": "image/png", "svg": "image/svg+xml"][file.pathExtension] ?? "application/octet-stream"
            }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": mime, "Cache-Control": "no-store"]) else { throw URLError(.badServerResponse) }
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch { task.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
