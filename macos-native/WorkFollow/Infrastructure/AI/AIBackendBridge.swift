import Foundation

enum AIBackendError: LocalizedError {
    case unavailable, disconnected, timedOut, invalidResponse, failed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "内置 AI 组件缺失，请重新安装完整应用。"
        case .disconnected: "AI 服务已退出，请重试。已有内容保留。"
        case .timedOut: "AI 请求超时，请稍后重试。"
        case .invalidResponse: "AI 服务返回的结果无效。"
        case .failed(let message): message
        }
    }
}

/// One App-owned backend, shared by all windows and AI scenarios. Only this
/// transport knows how the backend is launched; callers send scenario data.
final class AIBackendBridge: @unchecked Sendable {
    static let shared = AIBackendBridge()
    private let root: URL?
    private let launch: ((URL) -> (URL, [String]))?
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "workfollow.ai.backend.writer")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var pending: [String: BackendCall] = [:]
    private var events: [String: @Sendable (Data) -> Void] = [:]

    init(root: URL? = Bundle.main.resourceURL?.appendingPathComponent("AIBackend", isDirectory: true),
         launch: ((URL) -> (URL, [String]))? = nil) {
        self.root = root; self.launch = launch
    }

    func prewarm() async {
        struct Health: Decodable { let `protocol`: Int }
        _ = try? await call("health", timeout: 20) as Health
    }

    func call<T: Decodable>(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 120) async throws -> T {
        let data = try await request(method, params: params, timeout: timeout)
        try _Concurrency.Task.checkCancellation()
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AIBackendError.invalidResponse }
    }

    func request(_ method: String, params: [String: Any] = [:], timeout: TimeInterval = 120) async throws -> Data {
        let id = UUID().uuidString, call = BackendCall()
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]) + Data([10])
        return try await withTaskCancellationHandler {
            try _Concurrency.Task.checkCancellation()
            try await _Concurrency.Task.detached(priority: .utility) { try self.startIfNeeded() }.value
            try _Concurrency.Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                call.attach(continuation)
                let timer = DispatchWorkItem { [weak self] in self?.cancel(id, error: AIBackendError.timedOut) }
                let accepted = lock.withLock {
                    guard !call.finished, process?.isRunning == true else { return false }
                    pending[id] = call; call.installTimer(timer)
                    return true
                }
                guard accepted else { call.finish(.failure(AIBackendError.disconnected)); return }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
                write(data, requestID: id)
            }
        } onCancel: {
            call.finish(.failure(CancellationError()))
            self.cancel(id, error: CancellationError())
        }
    }

    func subscribe(_ channel: String, handler: @escaping @Sendable (Data) -> Void) {
        lock.withLock { events[channel] = handler }
    }
    func unsubscribe(_ channel: String) { _ = lock.withLock { events.removeValue(forKey: channel) } }

    private func startIfNeeded() throws {
        try lock.withLock {
            if process?.isRunning == true { return }
            guard let root else { throw AIBackendError.unavailable }
            let command = launch?(root) ?? (
                root.appendingPathComponent("runtime/arm64/python/bin/python3"),
                ["-I", "-B", root.appendingPathComponent("backend/ai_entry.py").path, "--root", root.path])
            guard FileManager.default.isExecutableFile(atPath: command.0.path) else { throw AIBackendError.unavailable }
            let child = Process(), stdin = Pipe(), stdout = Pipe(), token = UUID()
            child.executableURL = command.0; child.arguments = command.1
            child.currentDirectoryURL = FileManager.default.temporaryDirectory
            var environment = ProcessInfo.processInfo.environment
            // The bundled interpreter ignores user Python installations. Pi's
            // provider credentials remain in the user's existing Pi directory.
            environment.removeValue(forKey: "PYTHONHOME")
            environment.removeValue(forKey: "PYTHONPATH")
            child.environment = environment
            child.standardInput = stdin; child.standardOutput = stdout
            child.standardError = FileHandle.nullDevice
            child.terminationHandler = { [weak self] _ in self?.disconnected(token) }
            generation = token; buffer = Data()
            process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let bytes = handle.availableData
                if bytes.isEmpty { self?.disconnected(token) }
                else { self?.receive(bytes, generation: token) }
            }
            do { try child.run() }
            catch {
                output?.readabilityHandler = nil
                process = nil; input = nil; output = nil
                throw AIBackendError.unavailable
            }
        }
    }

    private func receive(_ bytes: Data, generation token: UUID) {
        let lines: [Data] = lock.withLock {
            guard generation == token else { return [] }
            buffer.append(bytes)
            var lines: [Data] = []
            while let end = buffer.firstIndex(of: 10) {
                lines.append(Data(buffer[..<end])); buffer.removeSubrange(...end)
            }
            return lines
        }
        for line in lines {
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let channel = message["channel"] as? String, let event = message["event"],
               let payload = try? JSONSerialization.data(withJSONObject: event) {
                lock.withLock { events[channel] }?(payload)
            } else if let id = message["id"] as? String {
                let call = lock.withLock { pending.removeValue(forKey: id) }
                if let error = message["error"] as? [String: String] {
                    let result: Error = error["code"] == "cancelled" ? CancellationError() :
                        AIBackendError.failed(error["message"] ?? "AI 调用失败。")
                    call?.finish(.failure(result))
                } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                    call?.finish(.success(data))
                } else { call?.finish(.failure(AIBackendError.invalidResponse)) }
            }
        }
    }

    private func write(_ data: Data, requestID: String? = nil) {
        writer.async { [weak self] in
            guard let self else { return }
            do {
                let handle = self.lock.withLock { () -> FileHandle? in
                    // A cancellation can be queued while Python is starting.
                    // Never send that original request after its cancel message.
                    if let id = requestID, self.pending[id] == nil { return nil }
                    return self.input
                }
                guard let handle else { throw AIBackendError.disconnected }
                try handle.write(contentsOf: data)
            } catch {
                if let id = requestID {
                    self.lock.withLock { self.pending.removeValue(forKey: id) }?.finish(.failure(AIBackendError.disconnected))
                }
            }
        }
    }

    private func cancel(_ id: String, error: Error) {
        lock.withLock { pending.removeValue(forKey: id) }?.finish(.failure(error))
        if let data = try? JSONSerialization.data(withJSONObject: ["method": "cancel", "params": ["requestID": id]]) {
            write(data + Data([10]))
        }
    }

    private func disconnected(_ token: UUID) {
        let state: ([BackendCall], [@Sendable (Data) -> Void]) = lock.withLock {
            guard generation == token, process != nil else { return ([], []) }
            output?.readabilityHandler = nil
            try? input?.close(); try? output?.close()
            process = nil; input = nil; output = nil
            let calls = Array(pending.values); pending.removeAll()
            return (calls, Array(events.values))
        }
        state.0.forEach { $0.finish(.failure(AIBackendError.disconnected)) }
        let event = Data(#"{"kind":"error","message":"AI 服务已退出，请重新开始转写。本地录音继续保存。"}"#.utf8)
        state.1.forEach { $0(event) }
    }

    func shutdown() {
        let child = lock.withLock { process }
        // Closing stdin is the normal shutdown path: the backend drains its
        // cancellation cleanup and closes every engine session on EOF.
        try? lock.withLock { input }?.close()
        guard let child else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            if child.isRunning { child.terminate() }
        }
    }
}

private final class BackendCall: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    private var timer: DispatchWorkItem?
    var finished: Bool { lock.withLock { result != nil } }
    func installTimer(_ timer: DispatchWorkItem) {
        lock.withLock {
            if result != nil { timer.cancel() } else { self.timer = timer }
        }
    }
    func attach(_ continuation: CheckedContinuation<Data, Error>) {
        let result = lock.withLock {
            self.continuation = continuation
            return self.result
        }
        if let result { continuation.resume(with: result) }
    }
    func finish(_ result: Result<Data, Error>) {
        let continuation: CheckedContinuation<Data, Error>? = lock.withLock {
            guard self.result == nil else { return nil }
            self.result = result; timer?.cancel(); return self.continuation
        }
        continuation?.resume(with: result)
    }
}
