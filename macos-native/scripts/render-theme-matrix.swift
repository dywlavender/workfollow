import AppKit
import SwiftUI
@testable import WorkFollow

/// 渲染「主题 × 明暗 × 材质」look 矩阵样张：
///
///   swiftc（见 scripts/prepare-replica-acceptance.sh 的链接方式）编译后运行：
///   render-theme-matrix <输出目录>
///
/// 每个组合一个真实 NSWindow（玻璃材质需要窗口服务器合成，离屏 cacheDisplay
/// 会画空），宿主 RootShellView + 真实 fixture 数据，CGWindowList 抓合成结果。
/// 输出 <主题>-<light|dark>-<classic|glass>.png，供肉眼逐张检查
/// （重点：玻璃 + 各主题色相下导航/浮层是否失效）。

@main
struct RenderThemeMatrix {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "ThemeMatrix", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Usage: render-theme-matrix <output-directory>"])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let storage = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("theme-matrix-\(UUID().uuidString)", isDirectory: true)
        let environment = AppEnvironment(directory: storage)
        environment.companionEnabled = false
        environment.backgroundAnimated = false
        environment.backgroundIntensity = .full
        // 用一份真实数据把列表撑起来（与 prepare-replica-fixture 同源的形态）。
        seedDemoTasks(into: environment.taskWorkspace)

        let themes: [NativeBackgroundTheme] = [.none, .peachSoda, .mintCloud, .creamSticker, .auroraJelly]
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        let materials: [(String, WFAppearanceMaterial)] = [("classic", .classic), ("glass", .liquidGlass)]

        for theme in themes {
            for (appearanceName, appearance) in appearances {
                for (materialName, material) in materials {
                    environment.backgroundTheme = theme
                    environment.appearanceMaterial = material
                    let file = "\(theme.rawValue)-\(appearanceName)-\(materialName).png"
                    let image = try render(output: output, windowFrame: NSRect(x: 60, y: 60, width: 1280, height: 800),
                                           appearance: appearance) { window in
                        window.contentView = NSHostingView(rootView: RootShellView(
                            workspace: environment.taskWorkspace,
                            navigation: environment.navigation)
                            .environmentObject(environment)
                            .frame(width: 1280, height: 800))
                    }
                    let rep = NSBitmapImageRep(cgImage: image)
                    guard let data = rep.representation(using: .png, properties: [:]) else {
                        throw NSError(domain: "ThemeMatrix", code: 2)
                    }
                    try data.write(to: output.appendingPathComponent(file))
                    print("rendered \(file) \(image.width)x\(image.height)")
                }
            }
        }
        print("done -> \(output.path)")
    }

    /// 建窗 → 挂内容 → 两轮 runloop → 从窗口服务器抓合成图。
    @MainActor
    private static func render(output: URL, windowFrame: NSRect, appearance: NSAppearance.Name,
                               content: (NSWindow) -> Void) throws -> CGImage {
        let window = NSWindow(contentRect: windowFrame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        content(window)
        window.makeKeyAndOrderFront(nil)
        // 玻璃材质与 SwiftUI 首帧都需要至少一个 runloop 周期；两轮取稳。
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        window.displayIfNeeded()
        let number = window.windowNumber
        let target = output.appendingPathComponent("capture.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(number)", target.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? Data(contentsOf: target),
              let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "ThemeMatrix", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "window capture failed"])
        }
        try? FileManager.default.removeItem(at: target)
        window.orderOut(nil)
        return image
    }

    /// 精简版演示数据：两条带截止与时间、一条高优、一条子任务，覆盖行的主要形态。
    @MainActor
    private static func seedDemoTasks(into workspace: TaskWorkspaceModel) {
        let calendar = Calendar(identifier: .gregorian)
        var components = calendar.dateComponents([.year, .month, .day], from: workspace.clock())
        components.hour = 10
        let base = calendar.date(from: components) ?? workspace.clock()
        func at(_ day: Int, _ hour: Int) -> Date {
            calendar.date(byAdding: .day, value: day, to: base)!
                .addingTimeInterval(TimeInterval(hour * 3600))
        }
        var schedule = TaskSchedule()
        schedule.dueAt = at(0, 10)
        schedule.hasTime = true
        let review = workspace.createDraft(title: "需求评审", list: "工作", schedule: schedule,
            priority: .high, tags: ["本周"], reminder: nil, repeatFrequency: .never,
            document: NativeDocument(plainText: "确认交互与验收范围\n整理待决事项，评审后同步结论。"))
        if let id = review.taskID {
            _ = workspace.createChild(id, title: "准备议程")
            _ = workspace.createChild(id, title: "检查演示材料")
        }
        var tomorrow = TaskSchedule()
        tomorrow.dueAt = at(1, 15)
        tomorrow.hasTime = true
        workspace.createDraft(title: "完善本周方案", list: "工作", schedule: tomorrow,
            priority: .medium, tags: [], reminder: nil, repeatFrequency: .never,
            document: NativeDocument(plainText: "梳理计划，记录实际投入。"))
        workspace.createDraft(title: "阅读 30 分钟", list: "生活", schedule: TaskSchedule(),
            priority: .low, tags: [], reminder: nil, repeatFrequency: .never,
            document: NativeDocument(plainText: ""))
        workspace.createDraft(title: "整理交付检查项", list: "工作", schedule: TaskSchedule(),
            priority: .none, tags: [], reminder: nil, repeatFrequency: .never,
            document: NativeDocument(plainText: ""))
    }
}
