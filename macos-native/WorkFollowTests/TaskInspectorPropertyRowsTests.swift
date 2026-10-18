import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// TI2-02 / TI2-03：正文后的两行属性（标签 chips、附件列表）与拖放导入。
///
/// 滴答证据：`TTTaskDetailTagCollectionCell`（chip 集合）与附件 cell +
/// `TTTaskDetailDropFileView`（拖文件到详情）。本地此前标签只在底栏浮层里可见、
/// 附件存进库但详情不渲染——这两条用例锁住"可见 + 顺序 + 导入通道"。
@MainActor
final class TaskInspectorPropertyRowsTests: XCTestCase {

    // MARK: - 标签 chips

    func testTagStripAppearsOnlyWhenTheTaskHasTags() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "标签用例", in: .inbox).taskID)
        workspace.select(id)

        var frames = try renderShell(workspace)
        XCTAssertNil(frames[.tagStrip], "没有标签时不占行高")

        workspace.setTags(id, ["工作", "重要"])
        frames = try renderShell(workspace)
        let strip = try XCTUnwrap(frames[.tagStrip], "有标签时详情里要看得见")
        XCTAssertGreaterThan(strip.width, 0)
        XCTAssertEqual(strip.minX, TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
        XCTAssertNil(frames[.attachments])
    }

    // MARK: - 附件行

    func testAttachmentRowAppearsOnlyWhenTheTaskHasAttachments() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "附件用例", in: .inbox).taskID)
        workspace.select(id)

        var frames = try renderShell(workspace)
        XCTAssertNil(frames[.attachments], "没有附件时不占行高")

        workspace.setAttachments(id, [NativeAttachment(id: UUID(), name: "方案.pdf",
                                                      storedName: "方案.pdf")])
        frames = try renderShell(workspace)
        let row = try XCTUnwrap(frames[.attachments], "上传过的附件必须能在详情里看到")
        XCTAssertGreaterThan(row.width, 0)
        XCTAssertEqual(row.minX, TaskInspectorMetrics.horizontalPadding, accuracy: 0.5)
    }

    // MARK: - 顺序：正文 → 附件 → 标签 → 子任务

    func testPropertyRowsSitBetweenDocumentAndSubtasks() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "顺序用例", in: .inbox).taskID)
        _ = workspace.createChild(id, title: "子任务")
        workspace.setTags(id, ["工作"])
        workspace.setAttachments(id, [NativeAttachment(id: UUID(), name: "记录.txt",
                                                      storedName: "记录.txt")])
        workspace.select(id)

        let frames = try renderShell(workspace)
        let document = try XCTUnwrap(frames[.document])
        let attachments = try XCTUnwrap(frames[.attachments])
        let tags = try XCTUnwrap(frames[.tagStrip])
        let children = try XCTUnwrap(frames[.childSection])
        XCTAssertLessThanOrEqual(document.maxY, attachments.minY + 0.5)
        XCTAssertLessThanOrEqual(attachments.maxY, tags.minY + 0.5)
        XCTAssertLessThanOrEqual(tags.maxY, children.minY + 0.5)
    }

    // MARK: - 拖放导入通道

    func testDropImportCollectsFileURLsInDragOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["甲.txt", "乙.txt", "丙.txt"].map { directory.appendingPathComponent($0) }
        for (index, url) in urls.enumerated() {
            try "内容\(index)".write(to: url, atomically: true, encoding: .utf8)
        }
        let providers = urls.compactMap { NSItemProvider(contentsOf: $0) }
        XCTAssertEqual(providers.count, 3)

        let expectation = expectation(description: "collect")
        var collected: [URL] = []
        AttachmentDropImport.collect(from: providers) { collected = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(collected.map(\.lastPathComponent), urls.map(\.lastPathComponent),
                       "落盘顺序必须与拖入顺序一致")
    }

    func testDropImportIgnoresProvidersWithoutFileURLs() throws {
        let provider = NSItemProvider(object: "只是文本" as NSString)
        let expectation = expectation(description: "collect")
        var collected: [URL] = []
        AttachmentDropImport.collect(from: [provider]) { collected = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
        XCTAssertTrue(collected.isEmpty)
    }

    // MARK: - 落盘规则

    func testImportFilesCopiesIntoSandboxAndKeepsDisplayName() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("导入-\(UUID().uuidString).txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        let imported = try NativeAttachmentFiles.importFiles([source])
        defer {
            for attachment in imported {
                if let url = NativeAttachmentFiles.url(for: attachment) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        let attachment = try XCTUnwrap(imported.first)
        XCTAssertEqual(attachment.name, source.lastPathComponent, "展示名保留原文件名")
        XCTAssertNotEqual(attachment.storedName, attachment.name, "落盘名用 UUID，避免重名覆盖")
        let stored = try XCTUnwrap(NativeAttachmentFiles.url(for: attachment))
        XCTAssertEqual(try String(contentsOf: stored, encoding: .utf8), "hello")
    }

    // MARK: - Helpers

    private func renderShell(_ workspace: TaskWorkspaceModel) throws -> [InspectorRenderAnchor: CGRect] {
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let root = TaskInspectorShell(workspace: workspace, showBack: false)
            .environmentObject(AppEnvironment())
            .frame(width: 880, height: 900)
            .environment(\.colorScheme, .light)
            .coordinateSpace(name: "inspector-render")
            .onPreferenceChange(InspectorFramesKey.self) { frames = $0 }
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        return frames
    }
}
