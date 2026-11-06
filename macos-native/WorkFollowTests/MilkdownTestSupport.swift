import AppKit
import WebKit
import XCTest
@testable import WorkFollow

/// Inspects the real production WebKit body. No TextKit surrogate is used.
@MainActor
enum MilkdownTestSupport {
    static func editors(in view: NSView) -> [MilkdownWebView] {
        ([view as? MilkdownWebView].compactMap { $0 }) + view.subviews.flatMap { editors(in: $0) }
    }

    static func editor(in host: NSView, id: UUID? = nil, readOnly: Bool? = nil) throws -> MilkdownWebView {
        try wait("Milkdown body did not finish loading") {
            editors(in: host).contains { $0.isDocumentReady && (id == nil || $0.documentIdentity == id)
                && (readOnly == nil || $0.isReadOnly == readOnly) }
        }
        return try XCTUnwrap(editors(in: host).first {
            $0.isDocumentReady && (id == nil || $0.documentIdentity == id) && (readOnly == nil || $0.isReadOnly == readOnly)
        })
    }

    static func editorAsync(in host: NSView, id: UUID? = nil) async throws -> MilkdownWebView {
        for _ in 0..<600 {
            if let view = editors(in: host).first(where: { $0.isDocumentReady && (id == nil || $0.documentIdentity == id) }) { return view }
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "MilkdownTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Milkdown body did not finish loading"])
    }

    static func wait(_ message: String, timeout: TimeInterval = 10, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard condition() else { throw NSError(domain: "MilkdownTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    @discardableResult
    static func call(_ view: MilkdownWebView, _ method: String, _ payload: [String: Any] = [:]) throws -> Any {
        var result: Result<Any, Error>?
        view.webView.callAsyncJavaScript("const api=window.workfollowEditor; return method==='command' ? api.command(payload.name,payload.payload||{}) : api[method](payload);",
            arguments: ["method": method, "payload": payload], in: nil, in: .page) { result = $0 }
        try wait("WebKit command timed out") { result != nil }
        let value = try result!.get()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        return value
    }

    @discardableResult
    static func command(_ view: MilkdownWebView, _ name: String, _ payload: [String: Any] = [:]) throws -> Any {
        try call(view, "command", ["name": name, "payload": payload])
    }

    @discardableResult
    static func script(_ view: MilkdownWebView, _ source: String) throws -> Any? {
        var result: Result<Any?, Error>?
        view.webView.evaluateJavaScript(source) { value, error in
            result = error.map { .failure($0) } ?? .success(value)
        }
        try wait("WebKit inspection timed out") { result != nil }
        return try result!.get()
    }

    static func select(_ view: MilkdownWebView, _ range: NSRange) throws {
        try command(view, "selectPlain", ["from": range.location, "to": NSMaxRange(range)])
    }

    static func selection(_ view: MilkdownWebView) throws -> MilkdownSelection {
        let object = try XCTUnwrap(call(view, "getSelection") as? [String: Any])
        return try JSONDecoder().decode(MilkdownSelection.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func range(_ view: MilkdownWebView) throws -> NSRange {
        let value = try selection(view)
        return NSRange(location: value.plainFrom, length: value.plainTo - value.plainFrom)
    }
    static func chooseMenu(_ view: MilkdownWebView, title: String) throws {
        let menu = try XCTUnwrap(call(view, "getMenu") as? [String: Any])
        let items = try XCTUnwrap(menu["items"] as? [[String: Any]])
        let index = try XCTUnwrap(items.firstIndex { ($0["title"] as? String)?.contains(title) == true })
        try command(view, "popupChoose", ["session": try XCTUnwrap(menu["session"]), "index": index])
    }

    /// CSS coordinates, as used by the production host's pointer bridge.
    static func characterRect(_ view: MilkdownWebView, at index: Int) throws -> NSRect {
        try command(view, "focus")
        let count = view.document.plainText.utf16.count
        try select(view, NSRange(location: min(index, count), length: index < count ? 1 : 0))
        let values = try XCTUnwrap(script(view, "(() => { const r=window.getSelection().getRangeAt(0).getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })()") as? [String: CGFloat])
        return NSRect(x: values["x"] ?? 0, y: values["y"] ?? 0, width: values["width"] ?? 0, height: values["height"] ?? 0)
    }

    static func inputClient(_ view: MilkdownWebView) throws -> any NSTextInputClient {
        try command(view, "focus")
        if let responder = view.window?.firstResponder as? NSView,
           (responder === view.webView || responder.isDescendant(of: view.webView)),
           let client = responder as? any NSTextInputClient { return client }
        func find(_ root: NSView) -> (any NSTextInputClient)? {
            if let client = root as? any NSTextInputClient { return client }
            return root.subviews.lazy.compactMap { find($0) }.first
        }
        return try XCTUnwrap(find(view.webView))
    }

    static func isFocused(_ view: MilkdownWebView) -> Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder === view.webView || responder.isDescendant(of: view.webView)
    }
}
