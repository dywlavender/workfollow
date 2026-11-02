import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 「外观」从「浅色」切回「跟随系统」时界面不变色，要关掉设置窗或切窗口才刷新。
///
/// 根因有两层：
/// 1. `AppEnvironment.appearance` 的 `didSet` 只写 UserDefaults，从不同步 AppKit；
/// 2. 同步时若按「窗口 appearance 已是目标值就跳过」去优化，会漏掉
///    `contentView.appearance` 上上一轮留下的覆盖——标题栏变了、正文没变。
@MainActor
final class AppearanceSwitchTests: XCTestCase {
    private func makeWindow() -> (NSWindow, NSView) {
        let host = NSHostingView(rootView: Color.clear.frame(width: 100, height: 100))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 200, height: 200)
        return (window, host)
    }

    /// 系统暗色下切回「跟随系统」，窗口**和内容视图**都要立刻跟随，不等窗口事件。
    func testSwitchingBackToSystemUpdatesWindowAndContentWithoutWindowEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(clock: { Date() }, calendar: .current, directory: directory)
        let (window, host) = makeWindow()
        defer { window.close() }

        environment.appearance = .light
        XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .aqua,
                       "浅色档应立刻变浅")

        environment.appearance = .system
        let expected: NSAppearance.Name = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .darkAqua : .aqua
        XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected,
                       "切回「跟随系统」后窗口外观应立刻跟随系统")
        // 这一条是上一版漏掉的：窗口对了不代表内容对了。
        XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected,
                       "内容视图也必须跟随，不能只有标题栏变")
        XCTAssertNil(host.appearance,
                     "内容视图上不应残留上一轮的显式覆盖")
    }

    /// 真实故障态：窗口 appearance 已是目标值（nil），但 contentView 上残留
    /// 上一轮的 `aqua`。这正是「标题栏变黑、正文还是白的」那一刻。
    /// 旧实现按「窗口已是目标值就跳过」优化，于是永远清不掉这层残留。
    func testStaleContentOverrideIsClearedEvenWhenWindowAlreadyMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(clock: { Date() }, calendar: .current, directory: directory)
        let (window, host) = makeWindow()
        defer { window.close() }

        // 手工构造故障态。
        window.appearance = nil
        host.appearance = NSAppearance(named: .aqua)

        environment.appearance = .system

        let expected: NSAppearance.Name = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .darkAqua : .aqua
        XCTAssertEqual(host.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), expected,
                       "窗口已匹配时也必须清理 contentView 上的残留覆盖")
        XCTAssertNil(host.appearance, "contentView 的显式覆盖应被清掉")
    }

    /// 反复横跳后不能残留任何显式覆盖。
    func testRepeatedSwitchingLeavesNoStaleOverride() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(clock: { Date() }, calendar: .current, directory: directory)
        let (window, host) = makeWindow()
        defer { window.close() }

        for appearance in [NativeAppearance.light, .dark, .system, .dark, .light, .system] {
            environment.appearance = appearance
        }
        XCTAssertNil(window.appearance, "窗口不应残留显式覆盖")
        XCTAssertNil(host.appearance, "内容视图不应残留显式覆盖")
    }

    /// 三档映射本身：跟随系统 = nil（不覆盖），浅/深各有确定值。
    func testAppearanceMapping() {
        XCTAssertNil(NativeAppearance.system.nsAppearance)
        XCTAssertEqual(NativeAppearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(NativeAppearance.dark.nsAppearance?.name, .darkAqua)
    }
}
