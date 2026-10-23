import AppIntents
import AppKit
import WidgetKit

struct CompleteWidgetTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "完成任务"
    static let isDiscoverable = false
    @Parameter(title: "任务") var taskID: String
    @Parameter(title: "任务版本") var revision: String

    init() {}
    init(item: TaskWidgetItem) { taskID = item.id.uuidString; revision = String(item.updatedAt.timeIntervalSinceReferenceDate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID), let timestamp = Double(revision), timestamp.isFinite else {
            throw TaskWidgetError.unavailable
        }
        let channel = try TaskWidgetChannel.shared()
        let command = TaskWidgetCompletion(taskID: id, expectedUpdatedAt: Date(timeIntervalSinceReferenceDate: timestamp))
        try channel.submit(command)
        // Wake the containing app without moving keyboard focus away from the
        // user's current work. It remains the only workspace writer.
        let bundle = Bundle.main.bundleURL
        let host = bundle.pathExtension == "appex"
            ? bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : bundle
        guard host.pathExtension == "app" else { throw TaskWidgetError.unavailable }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: host, configuration: configuration)
        for _ in 0..<80 {
            if let receipt = try channel.receipt(for: command.id) {
                try? channel.removeReceipt(command.id)
                WidgetCenter.shared.reloadTimelines(ofKind: TaskWidgetChannel.kind)
                if let error = receipt.error { throw TaskWidgetError.message(error) }
                return .result()
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(100))
        }
        throw TaskWidgetError.message("任务仍在处理中，请打开 WorkFollow 查看结果。")
    }
}
