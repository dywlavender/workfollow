import Foundation
import XCTest
@testable import WorkFollow

final class ArrowlessTaskPopupContractTests: XCTestCase {
    func testInspectorActionsUseIndependentPanelInsteadOfDismissalShield() throws {
        let source = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskInspector/TaskInspectorShell.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("title: \"任务详情操作\""))
        XCTAssertFalse(source.contains(".onTapGesture(perform: dismissFooterPopover)"),
                       "Outside dismissal must return the original event, not intercept a pane-sized tap")
    }

    func testMigratedTaskContextMenusDoNotUseSystemPopover() throws {
        for name in ["TaskContextMenuPresenter.swift", "TaskContextMenuPopover.swift"] {
            let file = businessSourceRoot.appendingPathComponent("Features/Tasks/TaskList/\(name)")
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(try occurrenceCount(of: "\\.popover\\s*\\(", in: source), 0,
                           "\(name) must keep its borderless presentation shell")
        }
    }

    func testBusinessSourceDoesNotConstructNSPopoverDirectly() throws {
        let violations = try businessSourceFiles().compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            let count = try occurrenceCount(of: "\\bNSPopover\\s*\\(", in: source)
            guard count > 0 else { return nil }
            return "\(relativePath(of: file)): \(count) direct constructor(s)"
        }

        XCTAssertTrue(violations.isEmpty,
                      "Use the shared popup presentation path; direct NSPopover construction found: "
                        + violations.joined(separator: ", "))
    }

    func testQuickAddAndTaskRowPropertiesKeepArrowlessPresentation() throws {
        let properties = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskList/QuickAddPropertiesPopover.swift"), encoding: .utf8)
        XCTAssertEqual(try occurrenceCount(of: "\\.popover\\s*\\(", in: properties), 0)
        let list = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskList/TaskListView.swift"), encoding: .utf8)
        XCTAssertEqual(try occurrenceCount(of: "\\.popover\\s*\\(", in: list), 0)
        XCTAssertTrue(list.contains("AnchoredPropertyPanel(isPresented: $showQuickAddProperties"))
        XCTAssertTrue(list.contains("AnchoredPropertyPanel(isPresented: $showTagPicker"))
    }

    func testFocusAndNavigationKeepArrowlessPresentation() throws {
        for path in ["Features/Focus/FocusTaskPickerPopover.swift",
                     "Features/Focus/FocusTimerPane.swift",
                     "Features/Shell/RootShellView.swift",
                     "Features/Notes/NotesWorkspaceView.swift"] {
            let source = try String(contentsOf: businessSourceRoot.appendingPathComponent(path),
                                    encoding: .utf8)
            XCTAssertEqual(try occurrenceCount(of: "\\.popover\\s*\\(", in: source), 0, path)
            XCTAssertTrue(source.contains("AnchoredPropertyPanel"), path)
        }
    }

    func testTaskContextMenuAndInspectorActionsDoNotSpecifyArrowEdge() throws {
        let files = try businessSourceFiles().filter { file in
            let path = relativePath(of: file)
            return path == "Features/Tasks/TaskList/TaskContextMenuPresenter.swift"
                || path == "Features/Tasks/TaskList/TaskContextMenuPopover.swift"
                || path.hasPrefix("Features/Tasks/TaskInspector/")
        }

        var violations: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let count = try occurrenceCount(of: "\\barrowEdge\\s*:", in: source)
            if count > 0 {
                violations.append("\(relativePath(of: file)): \(count)")
            }
        }

        XCTAssertTrue(violations.isEmpty,
                      "Task context menu and inspector action popups must omit arrowEdge: "
                        + violations.joined(separator: ", "))
    }

    func testGlobalArrowEdgeCountIsZero() throws {
        var actual: [String: Int] = [:]
        for file in try businessSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let count = try occurrenceCount(of: "\\barrowEdge\\s*:", in: source)
            if count > 0 {
                actual[relativePath(of: file)] = count
            }
        }

        XCTAssertEqual(actual.values.reduce(0, +), 0,
                       "Business UI must not request system popup arrows: \(actual)")
    }

    func testBusinessSourceDoesNotUseSystemPopover() throws {
        var actual: [String: Int] = [:]
        for file in try businessSourceFiles() {
            let count = try occurrenceCount(of: "\\.popover\\s*\\(",
                                            in: String(contentsOf: file, encoding: .utf8))
            if count > 0 { actual[relativePath(of: file)] = count }
        }
        XCTAssertTrue(actual.isEmpty,
                      "Business popups must use shared arrowless presentation: \(actual)")
    }

    func testContainerScheduleEntrypointsDeclareTheirControlAnchor() throws {
        let paths = ["Features/Tasks/TaskList/TaskListView.swift",
                     "Features/Tasks/TaskInspector/TaskInspectorHeader.swift",
                     "Features/Tasks/TaskList/TaskBatchPanelView.swift",
                     "Features/Planning/TaskQuickComposer.swift",
                     "Features/Planning/MatrixWorkspaceView.swift"]
        for path in paths {
            let source = try String(contentsOf: businessSourceRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(".scheduleTrigger("), "Missing control anchor: \(path)")
        }
        let list = try String(contentsOf: businessSourceRoot.appendingPathComponent(paths[0]), encoding: .utf8)
        XCTAssertTrue(list.contains("explicitAnchor: contextDateAnchor"))
        let inspector = try String(contentsOf: businessSourceRoot.appendingPathComponent("Features/Tasks/TaskInspector/TaskInspectorShell.swift"), encoding: .utf8)
        XCTAssertTrue(inspector.contains("trigger: .recurrence"))
    }

    private var businessSourceRoot: URL {
        // Resolve from this test's location so the contract does not depend on the test runner's cwd.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WorkFollow", isDirectory: true)
    }

    private func businessSourceFiles() throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: businessSourceRoot,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ),
            "Could not enumerate business source at \(businessSourceRoot.path)"
        )

        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        // 防空转守卫:枚举因权限或路径故障返回空/残缺时,调用方的"零违规"
        // 断言会静默通过(实测:测试宿主进程无文稿目录授权时即如此)。
        // 金丝雀文件缺失必须响亮失败,而不是给出无效的绿灯。
        try XCTUnwrap(!files.isEmpty,
                      "Source enumeration returned no files; contract would pass vacuously")
        _ = try XCTUnwrap(files.first { $0.lastPathComponent == "AppEnvironment.swift" },
                          "Enumeration missed AppEnvironment.swift; source scan is incomplete")
        return files
    }

    private func relativePath(of file: URL) -> String {
        String(file.path.dropFirst(businessSourceRoot.path.count + 1))
    }

    private func occurrenceCount(of pattern: String, in source: String) throws -> Int {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.numberOfMatches(in: source, range: range)
    }
}
