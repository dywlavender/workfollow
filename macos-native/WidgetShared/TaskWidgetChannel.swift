import Foundation

struct TaskWidgetCompletion: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let taskID: UUID
    let expectedUpdatedAt: Date
    var requestedAt = Date()
}

struct TaskWidgetReceipt: Codable, Sendable {
    let commandID: UUID
    let error: String?
}

enum TaskWidgetError: LocalizedError {
    case unavailable, message(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "无法连接 WorkFollow，请先打开应用。"
        case let .message(text): text
        }
    }
}

/// Atomic, independent request files avoid a cross-process read/modify/write of
/// the task database. Only the containing app applies and acknowledges commands.
struct TaskWidgetChannel: Sendable {
    static let groupID = "group.com.workfollow.native.widgets"
    static let kind = "WorkFollowToday"
    static let notification = "com.workfollow.native.widget-completion"
    let directory: URL
    var requiredContainer: URL? = nil

    static func shared() throws -> Self {
        let bundle = Bundle.main
        switch bundle.object(forInfoDictionaryKey: "WorkFollowWidgetTransport") as? String ?? "appGroup" {
        case "widgetContainer":
            let isExtension = bundle.bundleURL.pathExtension == "appex"
            guard let identifier = bundle.bundleIdentifier else { throw TaskWidgetError.unavailable }
            return localContainer(extensionID: isExtension ? identifier : identifier + ".widgets",
                isExtension: isExtension, home: FileManager.default.homeDirectoryForCurrentUser,
                applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
        case "appGroup":
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
                throw TaskWidgetError.unavailable
            }
            return Self(directory: url.appendingPathComponent("TodayWidget", isDirectory: true))
        default:
            throw TaskWidgetError.unavailable
        }
    }
    /// Local ad-hoc builds share only the widget's own sandbox container. The
    /// system must create that container before the host starts publishing.
    static func localContainer(extensionID: String, isExtension: Bool, home: URL, applicationSupport: URL) -> Self {
        if isExtension {
            return Self(directory: applicationSupport.appendingPathComponent("TodayWidget", isDirectory: true))
        }
        let container = home.appendingPathComponent("Library/Containers/\(extensionID)/Data", isDirectory: true)
        return Self(directory: container.appendingPathComponent("Library/Application Support/TodayWidget", isDirectory: true),
                    requiredContainer: container)
    }
    func readSnapshot() throws -> TaskWidgetSnapshot? {
        let url = directory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let snapshot = try JSONDecoder().decode(TaskWidgetSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 1 else { throw TaskWidgetError.unavailable }
        return snapshot
    }
    func publish(_ snapshot: TaskWidgetSnapshot) throws { try write(snapshot, to: directory.appendingPathComponent("snapshot.json")) }
    func submit(_ command: TaskWidgetCompletion) throws {
        try write(command, to: requestURL(command.id))
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(Self.notification), object: nil, userInfo: nil, deliverImmediately: true)
    }
    func pending() throws -> [TaskWidgetCompletion] {
        let folder = directory.appendingPathComponent("requests", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(TaskWidgetCompletion.self, from: Data(contentsOf: $0)) }
            .sorted { $0.requestedAt < $1.requestedAt }
    }
    func receipt(for id: UUID) throws -> TaskWidgetReceipt? {
        let url = receiptURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(TaskWidgetReceipt.self, from: Data(contentsOf: url))
    }
    func acknowledge(_ command: TaskWidgetCompletion, error: String?) throws {
        try write(TaskWidgetReceipt(commandID: command.id, error: error), to: receiptURL(command.id))
        try FileManager.default.removeItem(at: requestURL(command.id))
    }
    func removeReceipt(_ id: UUID) throws { try FileManager.default.removeItem(at: receiptURL(id)) }
    private func requestURL(_ id: UUID) -> URL { directory.appendingPathComponent("requests/\(id.uuidString).json") }
    private func receiptURL(_ id: UUID) -> URL { directory.appendingPathComponent("receipts/\(id.uuidString).json") }
    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        if let requiredContainer, !FileManager.default.fileExists(atPath: requiredContainer.path) {
            throw TaskWidgetError.unavailable
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}
