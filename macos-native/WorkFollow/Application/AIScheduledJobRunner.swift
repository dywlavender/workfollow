import Combine
import Foundation

@MainActor
final class AIScheduledJobRunner: ObservableObject {
    typealias Generator = (AIScheduledJob, AIScheduledRun, AIConversationModel) -> AIConversationModel.Generate
    @Published private(set) var runningJobID: UUID?
    @Published private(set) var error: String?
    private let store: AIScheduledJobStore
    private let chats: AIChatStore
    private let generate: Generator
    private let canRun: () -> Bool
    private var model: AIConversationModel?
    private var runID: UUID?
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var pending: [UUID] = []
    private var active = false
    private var timersEnabled = true

    init(store: AIScheduledJobStore, chats: AIChatStore, canRun: @escaping () -> Bool = { true }, generate: @escaping Generator) {
        self.store = store; self.chats = chats; self.canRun = canRun; self.generate = generate
        store.onChange = { [weak self] in self?.error = nil; self?.arm() }
    }

    func start(timers: Bool = true) { active = true; timersEnabled = timers; checkDue() }

    func runNow(_ id: UUID) throws {
        guard store.job(id) != nil else { throw AutomationFailure(code: "not_found", message: "定时任务已不存在。") }
        guard runningJobID != id else { throw AutomationFailure.argument("该定时任务正在执行。") }
        if !pending.contains(id) { pending.append(id) }
        active = true; error = nil; checkDue()
    }

    func stop(_ id: UUID) {
        pending.removeAll { $0 == id }
        if runningJobID == id { model?.stop(); finishIfNeeded() }
    }

    func shutdown() {
        active = false; timer?.invalidate(); timer = nil; pending = []
        model?.stop(); finishIfNeeded()
    }

    func checkDue() {
        timer?.invalidate(); timer = nil
        guard active, canRun() else { return }
        guard model == nil else { arm(); return }
        let job: AIScheduledJob?
        var manual = false
        pending.removeAll { store.job($0) == nil }
        if let id = pending.first { pending.removeFirst(); job = store.job(id); manual = true }
        else {
            let now = store.clock()
            job = store.jobs.filter { $0.isEnabled && $0.nextRunAt.map { $0 <= now } == true }
                .min { ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture) }
        }
        guard let job else { arm(); return }
        do {
            let conversation = AIConversationModel(directory: chats.sessionDirectory)
            let run = try store.begin(job.id, manual: manual, conversationID: conversation.record.id)
            model = conversation; runningJobID = job.id; runID = run.id
            chats.trackBackground(conversation)
            observation = conversation.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async { self?.finishIfNeeded() }
            }
            conversation.input = "定时任务：\(job.title)\n\n\(job.instruction)"
            conversation.send(using: generate(job, run, conversation))
            arm()
        } catch { self.error = error.localizedDescription }
    }

    private func finishIfNeeded() {
        guard let model, !model.isRunning, let answer = model.record.messages.last,
              answer.role == .assistant, answer.state != .generating,
              let id = runningJobID, let runID else { return }
        let state: AIScheduledRun.State = answer.state == .complete ? .complete : answer.state == .stopped ? .interrupted : .failed
        observation?.cancel(); observation = nil; self.model = nil; runningJobID = nil; self.runID = nil
        do {
            try store.finish(id, runID: runID, state: state,
                error: state == .interrupted ? "本轮已停止，已完成的操作保留；不会自动重复执行。" : answer.error)
            arm()
        } catch { self.error = error.localizedDescription }
    }

    private func arm() {
        timer?.invalidate(); timer = nil
        guard active, canRun(), error == nil else { return }
        if let id = runningJobID {
            if store.job(id) == nil { model?.stop(); finishIfNeeded() }
            return
        }
        guard timersEnabled else { return }
        let next = pending.isEmpty ? store.jobs.filter(\.isEnabled).compactMap(\.nextRunAt).min() : store.clock()
        guard let next else { return }
        let nextTimer = Timer(timeInterval: max(0.05, next.timeIntervalSince(store.clock())), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDue() }
        }
        timer = nextTimer; RunLoop.main.add(nextTimer, forMode: .common)
    }
}
