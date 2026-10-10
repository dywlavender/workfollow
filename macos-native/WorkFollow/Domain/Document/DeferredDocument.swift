import Foundation

struct DocumentSummary: Codable {
    let head: String
    let tail: String
    let length: Int
    let isEmpty: Bool
    let firstLine: String?
    let hasOriginalContent: Bool?
    init(_ document: NativeDocument, hasOriginalContent: Bool? = nil) {
        self.hasOriginalContent = hasOriginalContent
        let text = document.plainText
        head = String(text.prefix(160)); tail = String(text.suffix(160))
        length = text.count; isEmpty = document.isEmpty
        firstLine = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }.map { String($0.prefix(160)) }
    }
}

/// Shared immutable read reference. Value edits detach from this cache, leaving
/// prior values (including undo snapshots) with their original blocks.
final class DeferredDocument {
    let summary: DocumentSummary
    private let loader: () throws -> NativeDocument
    let search: (String, Bool) throws -> Bool
    private let report: (Error) -> Void
    private let lock = NSRecursiveLock()
    private var result: Result<NativeDocument, Error>?
    private let failureBlock = DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "正文读取失败")])

    init(summary: DocumentSummary, loader: @escaping () throws -> NativeDocument,
         search: @escaping (String, Bool) throws -> Bool, report: @escaping (Error) -> Void) {
        self.summary = summary; self.loader = loader; self.search = search; self.report = report
    }
    var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .success? = result { return true }; return false
    }
    var loadError: Error? {
        lock.lock(); defer { lock.unlock() }
        if case .failure(let error)? = result { return error }; return nil
    }
    func resolve() throws -> NativeDocument {
        lock.lock(); defer { lock.unlock() }
        if let result { return try result.get() }
        do { let document = try loader(); result = .success(document); return document }
        catch { result = .failure(error); report(error); throw error }
    }
    func displayBlocks() -> [DocumentBlock] {
        do { return try resolve().blocks } catch { return [failureBlock] }
    }
    func matches(_ query: String, lowercase: Bool) -> Bool {
        do { return try search(query, lowercase) }
        catch { report(error); return false }
    }
}

final class DeferredOriginalContent {
    let isPresent: Bool?
    private let loader: () throws -> String?
    private let lock = NSRecursiveLock()
    private var result: Result<String?, Error>?
    init(isPresent: Bool?, loader: @escaping () throws -> String?) { self.isPresent = isPresent; self.loader = loader }
    func resolve() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if let result { return try result.get() }
        do { let value = try loader(); result = .success(value); return value }
        catch { result = .failure(error); throw error }
    }
}
