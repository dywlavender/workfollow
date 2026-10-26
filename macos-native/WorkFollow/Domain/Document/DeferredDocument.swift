import Foundation

/// 检查项提醒的列表/调度投影。只存未完成项，避免把已完成项继续排进通知。
struct ChecklistReminderSummary: Codable, Equatable {
    let blockID: UUID
    let title: String
    let fireDate: Date
}

/// 清单任务的正文投影：总数、完成数、未完成项提醒。
/// 列表与提醒调度只读它，不触发 `DeferredDocument.resolve()`。
struct ChecklistSummary: Codable, Equatable {
    let total: Int
    let done: Int
    let reminders: [ChecklistReminderSummary]

    init(total: Int, done: Int, reminders: [ChecklistReminderSummary]) {
        self.total = total
        self.done = done
        self.reminders = reminders
    }

    init(blocks: [DocumentBlock]) {
        var total = 0
        var done = 0
        var reminders: [ChecklistReminderSummary] = []
        for block in blocks {
            guard case .checklist(let checked) = block.kind else { continue }
            total += 1
            if checked {
                done += 1
                continue
            }
            guard let reminderAt = block.checklist?.reminderAt else { continue }
            let title = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            reminders.append(ChecklistReminderSummary(
                blockID: block.id,
                title: title.isEmpty ? "检查事项" : title,
                fireDate: reminderAt))
        }
        self.total = total
        self.done = done
        self.reminders = reminders.sorted {
            $0.fireDate == $1.fireDate
                ? $0.blockID.uuidString < $1.blockID.uuidString
                : $0.fireDate < $1.fireDate
        }
    }
}

struct DocumentSummary: Codable {
    let head: String
    let tail: String
    let length: Int
    let isEmpty: Bool
    let firstLine: String?
    let hasOriginalContent: Bool?
    /// 旧摘要没有这个键 → nil；v3 迁移会按正文回填。
    let checklist: ChecklistSummary?
    init(_ document: NativeDocument, hasOriginalContent: Bool? = nil) {
        self.hasOriginalContent = hasOriginalContent
        let text = document.plainText
        head = String(text.prefix(160)); tail = String(text.suffix(160))
        length = text.count; isEmpty = document.isEmpty
        firstLine = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }.map { String($0.prefix(160)) }
        let summary = ChecklistSummary(blocks: document.blocks)
        checklist = summary.total > 0 ? summary : nil
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
