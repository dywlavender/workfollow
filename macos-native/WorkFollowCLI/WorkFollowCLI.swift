import AppKit
import Foundation
import MachO

@main
struct WorkFollowCLI {
    @MainActor
    static func main() async {
        let tokens = Array(CommandLine.arguments.dropFirst())
        var request = AutomationRequest(operation: "status", arguments: [:])
        var json = tokens.contains("--json")
        do {
            let invocation = try AutomationInvocation.parse(tokens) { path in
                let data = path == "-" ? FileHandle.standardInput.readDataToEndOfFile()
                    : try Data(contentsOf: URL(fileURLWithPath: path))
                guard let text = String(data: data, encoding: .utf8) else { throw AutomationFailure.argument("正文文件须为 UTF-8 文本。") }
                return text
            }
            guard let input = invocation.request else { print(AutomationInvocation.help); return }
            request = input; json = invocation.json
            request.conversationID = ProcessInfo.processInfo.environment["WORKFOLLOW_CONVERSATION_ID"].flatMap(UUID.init(uuidString:))
            let app = try applicationURL(invocation.appPath)
            let workspace = workspaceDirectory(app)
            let channel = AutomationChannel(workspaceDirectory: workspace)
            try channel.submit(request)
            do {
                let running = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleURL?.resolvingSymlinksInPath() == app.resolvingSymlinksInPath() && !$0.isTerminated
                }
                if !running {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    configuration.addsToRecentItems = false
                    configuration.arguments = [AutomationChannel.launchArgument]
                    _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
                }
                while Date() < request.expiresAt {
                    if let response = try channel.response(for: request.id) {
                        try? channel.removeResponse(request.id)
                        output(response, json: json)
                        exit(response.ok ? 0 : 1)
                    }
                    try await _Concurrency.Task.sleep(nanoseconds: 30_000_000)
                }
                throw AutomationFailure(code: "timeout", message: "等待 App 响应超时。请确认使用了附带 CLI 接口的新版 App；可用 --app 指定应用、--timeout 调整等待时间。")
            } catch {
                try? channel.removeRequest(request.id)
                throw error
            }
        } catch {
            let failure = error as? AutomationFailure ?? AutomationFailure(code: "unavailable", message: error.localizedDescription)
            output(.failure(request, failure), json: json)
            exit(failure.code == "invalid_argument" ? 2 : 1)
        }
    }

    private static func executableURL() -> URL {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        _NSGetExecutablePath(&buffer, &size)
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }
    @MainActor
    private static func applicationURL(_ explicit: String?) throws -> URL {
        let embedded = executableURL().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app: URL?
        if let explicit { app = URL(fileURLWithPath: explicit).standardizedFileURL }
        else if embedded.pathExtension == "app" { app = embedded }
        else { app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.workfollow.native.preview") }
        guard let app, app.pathExtension == "app", let bundle = Bundle(url: app),
              bundle.executableURL.map({ FileManager.default.isExecutableFile(atPath: $0.path) }) == true else {
            throw AutomationFailure.argument("找不到 WorkFollow App，请使用应用附带的 workfollowctl，或通过 --app 指定 WorkFollow.app。")
        }
        return app
    }
    private static func workspaceDirectory(_ app: URL) -> URL {
        #if DEBUG
        if let path = Bundle(url: app)?.object(forInfoDictionaryKey: "WorkFollowAcceptanceStorageRoot") as? String,
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkFollowNativePreview", isDirectory: true)
    }
    private static func output(_ response: AutomationResponse, json: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = json ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(response) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
    }
}
