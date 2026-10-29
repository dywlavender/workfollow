import Combine
import Foundation

struct KnowledgeAnswer: Decodable, Equatable, Sendable {
    struct Citation: Decodable, Equatable, Sendable { let source: String; let quote: String }
    struct Paragraph: Decodable, Equatable, Sendable { let text: String; let citations: [Citation] }
    let paragraphs: [Paragraph]
    let insufficient: Bool
    let sourceIDs: [String]
}

@MainActor
final class KnowledgeAnswerSession: ObservableObject {
    enum Phase: Equatable { case idle, searching, answering, ready, noResults, failed(String) }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var question = ""
    @Published private(set) var result = KnowledgeSearchResult()
    @Published private(set) var answer: KnowledgeAnswer?
    @Published private(set) var retryAt: Date?
    @Published private(set) var preview = ""
    @Published private(set) var status = "正在根据资料整理回答…"
    private var operation: _Concurrency.Task<Void, Never>?
    private var generation = UUID()
    var isBusy: Bool { phase == .searching || phase == .answering }
    var usedSources: [KnowledgePassage] { result.sources.filter { answer?.sourceIDs.contains($0.id) ?? true } }

    func ask(question raw: String, corpus: KnowledgeCorpus,
             generate: @escaping @MainActor (String, [KnowledgePassage], @escaping @Sendable (AITextUpdate) -> Void) async throws -> KnowledgeAnswer) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, question.count <= 500 else { return }
        guard !(isBusy && self.question == question) else { return }
        guard self.question != question || (retryAt.map({ $0 <= Date() }) ?? true) else { return }
        cancel()
        let token = UUID(); generation = token
        self.question = question; answer = nil; result = KnowledgeSearchResult(); phase = .searching; retryAt = nil
        preview = ""; status = "正在根据资料整理回答…"
        operation = _Concurrency.Task { [weak self] in
            let search = _Concurrency.Task.detached(priority: .utility) { try corpus.search(question) }
            do {
                let found = try await withTaskCancellationHandler { try await search.value }
                    onCancel: { search.cancel() }
                try _Concurrency.Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.result = found
                guard !found.sources.isEmpty else { self.phase = .noResults; self.operation = nil; return }
                self.phase = .answering
                let answer = try await generate(question, found.sources) { [weak self] value in
                    _Concurrency.Task { @MainActor in
                        guard let self, self.generation == token, self.isBusy else { return }
                        if value.kind == "text" { self.preview = value.text ?? "" }
                        if value.kind == "status" { self.status = value.message ?? "正在生成…" }
                    }
                }
                try _Concurrency.Task.checkCancellation()
                guard self.generation == token else { return }
                self.answer = answer; self.phase = .ready; self.operation = nil
            } catch is CancellationError { }
            catch {
                guard let self, self.generation == token else { return }
                if let seconds = (error as? AIBackendError)?.retryAfterSeconds { self.retryAt = Date().addingTimeInterval(seconds) }
                self.phase = .failed(error.localizedDescription); self.operation = nil
            }
        }
    }

    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil
        if isBusy { phase = .idle }
    }
}
