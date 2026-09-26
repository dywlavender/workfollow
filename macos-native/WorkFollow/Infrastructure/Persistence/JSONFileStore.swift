import Foundation

/// Generic JSON file persistence for module stores: debounced atomic writes on
/// a serial queue, synchronous load. One file per store under `modules/`.
final class JSONFileStore<Value: Codable> {
    static var moduleDirectory: URL {
        NativePreviewRepository.directory.appendingPathComponent("modules", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "WorkFollow.module.persistence", qos: .utility)
    private let file: URL
    private let delay: TimeInterval
    private var pending: Value?
    private var work: DispatchWorkItem?

    init(filename: String, directory: URL = JSONFileStore.moduleDirectory, delay: TimeInterval = 0.4) {
        file = directory.appendingPathComponent(filename)
        self.delay = delay
    }

    func load() -> Value? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func schedule(_ value: Value) {
        queue.async { [self] in
            pending = value
            work?.cancel()
            let next = DispatchWorkItem { [weak self] in self?.writePending() }
            work = next
            queue.asyncAfter(deadline: .now() + delay, execute: next)
        }
    }

    /// Writes the pending value immediately; safe to call during termination.
    func flush(_ completion: @escaping (Error?) -> Void = { _ in }) {
        queue.async { [self] in
            work?.cancel()
            let error = writePending()
            completion(error)
        }
    }

    @discardableResult
    private func writePending() -> Error? {
        guard let value = pending else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: file, options: .atomic)
            pending = nil
            return nil
        } catch {
            // Keep the latest value available for a retry/termination flush.
            return error
        }
    }
}

/// Stores owned by feature modules implement this so termination can flush them.
@MainActor protocol ModuleStoreFlushable {
    func flush(_ completion: @escaping (Error?) -> Void)
}
