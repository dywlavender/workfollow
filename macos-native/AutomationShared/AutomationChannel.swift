import Foundation

struct AutomationChannel: Sendable {
    static let launchArgument = "--automation"
    static let notification = Notification.Name("com.workfollow.native.automation")
    let directory: URL

    init(workspaceDirectory: URL) { directory = workspaceDirectory.appendingPathComponent("automation", isDirectory: true) }
    func submit(_ request: AutomationRequest) throws {
        try write(request, to: requestURL(request.id))
        DistributedNotificationCenter.default().postNotificationName(Self.notification, object: directory.path,
            userInfo: nil, deliverImmediately: true)
    }
    func pending() throws -> [AutomationRequest] {
        let folder = directory.appendingPathComponent("requests", isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(AutomationRequest.self, from: Data(contentsOf: $0)) }
            .sorted { $0.requestedAt < $1.requestedAt }
    }
    func response(for id: UUID) throws -> AutomationResponse? {
        let url = responseURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AutomationResponse.self, from: Data(contentsOf: url))
    }
    func respond(_ response: AutomationResponse) throws {
        try write(response, to: responseURL(response.requestID))
        try removeRequest(response.requestID)
    }
    func removeRequest(_ id: UUID) throws {
        let url = requestURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    func removeResponse(_ id: UUID) throws { try FileManager.default.removeItem(at: responseURL(id)) }
    private func requestURL(_ id: UUID) -> URL { directory.appendingPathComponent("requests/\(id.uuidString).json") }
    private func responseURL(_ id: UUID) -> URL { directory.appendingPathComponent("responses/\(id.uuidString).json") }
    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
