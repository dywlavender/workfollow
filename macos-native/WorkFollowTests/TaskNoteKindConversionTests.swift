import AppKit
import XCTest
@testable import WorkFollow

@MainActor
final class TaskNoteKindConversionTests: XCTestCase {
    func testInspectorConvertsInPlaceAndBackWithoutLosingRichBody() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-note-kind-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = AppEnvironment(directory: directory)
        let workspace = environment.taskWorkspace
        let id = try XCTUnwrap(workspace.createTask(title: "任务笔记共用正文", in: .inbox).taskID)
        let child = try XCTUnwrap(workspace.createChild(id, title: "子任务").taskID)
        let attachment = NativeAttachment(id: UUID(), name: "资料.pdf", storedName: "sample.pdf")
        let body = NativeDocument(blocks: [
            DocumentBlock(kind: .heading(1), runs: [DocumentRun(text: "标题")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "已完成", marks: [.bold])]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "\u{FFFC}", attachment: attachment)])
        ])
        workspace.setDocument(id, body)
        workspace.select(id)
        let destination = environment.navigation.destination
        var frames: [InspectorRenderAnchor: CGRect] = [:]
        let host = InspectorPanelTestSupport.inspectorHost(workspace: workspace,
            environment: environment, onFrames: { frames = $0 })
        let window = InspectorPanelTestSupport.ownerWindow(for: host)
        defer { window.close() }
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.footerMore]), in: host, window: window)
        var panel = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.clickButton(containing: "转换为笔记", in: panel)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.selectedTaskID, id)
        XCTAssertEqual(environment.navigation.destination, destination)
        XCTAssertEqual(workspace.task(for: id)?.kind, .note)
        XCTAssertEqual(workspace.task(for: id)?.document, body)
        XCTAssertEqual(workspace.task(for: child)?.parentID, id)
        XCTAssertEqual(environment.notesWorkspace.notes.map(\.id), [id])
        XCTAssertNil(workspace.task(for: id)?.convertedNoteID)
        try InspectorPanelTestSupport.click(try XCTUnwrap(frames[.footerMore]), in: host, window: window)
        panel = try InspectorPanelTestSupport.actionPanel(in: window)
        try InspectorPanelTestSupport.clickButton(containing: "转换为任务", in: panel)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(workspace.task(for: id)?.kind, .text)
        XCTAssertEqual(workspace.task(for: id)?.document, body)
        XCTAssertTrue(environment.notesWorkspace.notes.isEmpty)
        workspace.undo()
        XCTAssertEqual(workspace.task(for: id)?.kind, .note)
        XCTAssertEqual(workspace.task(for: id)?.document, body)
        XCTAssertEqual(environment.notesWorkspace.notes.map(\.id), [id])
    }
}
