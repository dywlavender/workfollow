import AppIntents
import AppKit

enum WidgetQuickAddLaunch {
    static let argument = "--widget-quick-add"

    static func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.arguments = [argument]
        return configuration
    }
}

struct OpenWidgetQuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "快速新增任务"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let bundle = Bundle.main.bundleURL
        let host = bundle.pathExtension == "appex"
            ? bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() : bundle
        guard host.pathExtension == "app" else { throw TaskWidgetError.unavailable }
        // Cold launches carry an explicit purpose before SwiftUI restores any
        // windows. The URL also delivers the action to an already running app.
        _ = try await NSWorkspace.shared.open([TaskWidgetLink.quickAdd], withApplicationAt: host,
                                             configuration: WidgetQuickAddLaunch.configuration())
        return .result()
    }
}
