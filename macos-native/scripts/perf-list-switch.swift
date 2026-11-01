import AppKit
import SwiftUI
@testable import WorkFollow

/// 清单切换性能探针（独立于 XCTest，stdout 直接出数据）：
///
///   perf-list-switch <WorkFollow.app 副本内运行> [轮数]
///
/// 宿主真实 RootShellView + 60 条任务的 fixture，轮换 3 个自定义清单与
/// 今天/收集箱，逐次记录 Diagnostics 与墙钟。编译方式见
/// scripts/prepare-replica-acceptance.sh（swiftc 链接 WorkFollow.debug.dylib），
/// 运行时需把可执行文件放进 App 副本（mainBundle 依赖）。

@main
struct PerfListSwitch {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let rounds = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 20 : 20

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perf-list-switch-\(UUID().uuidString)", isDirectory: true)
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.backgroundAnimated = false
        environment.appearanceMaterial = .classic
        let workspace = environment.taskWorkspace
        let navigation = environment.navigation
        navigation.destination = .inbox

        let names = ["虚构工作", "虚构学习", "虚构个人"]
        let calendar = Calendar(identifier: .gregorian)
        var day = calendar.date(byAdding: .day, value: 2, to: workspace.clock())!
        for index in 0..<60 {
            var schedule = TaskSchedule()
            schedule.dueAt = day
            schedule.hasTime = false
            let list = index < 15 ? TaskList.inbox.name : names[(index - 15) / 15]
            workspace.createDraft(title: "虚构任务 \(index)", list: list, schedule: schedule,
                priority: .none, tags: [], reminder: nil, repeatFrequency: .never,
                document: NativeDocument(plainText: "虚构预览 \(index)"))
            if index % 20 == 19 { day = day.addingTimeInterval(86_400) }
        }

        let host = NSHostingView(rootView: RootShellView(workspace: workspace, navigation: navigation)
            .environmentObject(environment)
            .frame(width: 1280, height: 800))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        // 预热一轮，排除首次装载的重载成本。
        for name in names { navigation.openTaskList(name, in: workspace) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        print("round,list,route_ms,layout_ms,settle_ms,total_ms,cells,configs,update_ms,reload_ms,row_layout_ms,projections")
        for pass in 0..<max(1, rounds) {
            for name in names {
                NativeTaskOutline.Diagnostics.reset()
                let projections = workspace.projectionBuildCount
                let start = ProcessInfo.processInfo.systemUptime
                navigation.openTaskList(name, in: workspace)
                let routed = ProcessInfo.processInfo.systemUptime
                host.layoutSubtreeIfNeeded()
                let laidOut = ProcessInfo.processInfo.systemUptime
                RunLoop.main.run(until: Date().addingTimeInterval(0.001))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let end = ProcessInfo.processInfo.systemUptime
                let d = NativeTaskOutline.Diagnostics.self
                print("\(pass),\(name),\(fmt(routed - start)),\(fmt(laidOut - routed)),\(fmt(end - laidOut)),\(fmt(end - start)),\(d.createdCells),\(d.configurations),\(fmt(d.updateTime)),\(fmt(d.reloadTime)),\(fmt(d.rowLayoutTime)),\(workspace.projectionBuildCount - projections)")
            }
        }
        try? FileManager.default.removeItem(at: directory)
        exit(0)
    }

    private static func fmt(_ seconds: Double) -> String {
        String(format: "%.2f", seconds * 1000)
    }
}
