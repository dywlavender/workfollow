import Foundation
import XCTest
@testable import WorkFollow

final class ArrowlessTaskPopupContractTests: XCTestCase {
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

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
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
