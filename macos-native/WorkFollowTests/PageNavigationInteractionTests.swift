import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WorkFollow

@MainActor
final class PageNavigationInteractionTests: XCTestCase {
    func testLeavingNotesOnlyChangesFrozenWindowWidthWhenNeeded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let now = Date()
        let note = Note(id: UUID(), title: "虚构笔记", document: NativeDocument(plainText: "页面切换回归正文"), folder: "未归档", updatedAt: now)
        try NativePreviewRepository(directory: directory).save(.init(tasks: [], notes: [note]))
        let environment = AppEnvironment(directory: directory)
        environment.companionEnabled = false
        environment.notesWorkspace.aiPaneVisible = false
        environment.navigation.destination = .notes
        let host = NSHostingView(rootView: RootShellView(workspace: environment.taskWorkspace, navigation: environment.navigation)
            .environmentObject(environment).frame(width: 1280, height: 800))
        let window = InspectorPanelTestSupport.ownerWindow(for: host, width: 1280, height: 800)
        defer { window.contentView = nil; window.close() }
        XCTAssertNil(environment.notesAIFrozenWindowWidth)
        var changes = 0
        var noteSelectionChanges = 0
        let subscription = environment.$notesAIFrozenWindowWidth.dropFirst().sink { _ in changes += 1 }
        let noteSubscription = environment.notesWorkspace.$selectedID.dropFirst().sink { _ in noteSelectionChanges += 1 }
        defer { subscription.cancel(); noteSubscription.cancel() }
        environment.navigate(to: .inbox)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(changes, 0, "未展开 AI 的笔记页离开时，不应重新发布相同的全局布局状态")
        environment.navigate(to: .notes)
        InspectorPanelTestSupport.settle(window)
        XCTAssertEqual(noteSelectionChanges, 0, "回访笔记时，空选中项不应重复发布")
        environment.notesWorkspace.selectedID = note.id
        environment.navigate(to: .inbox)
        InspectorPanelTestSupport.settle(window)
        environment.navigate(to: .notes)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNil(environment.notesWorkspace.selectedID)
        XCTAssertEqual(noteSelectionChanges, 2, "真实选中项仍须按导航规则清除")
        environment.notesAIFrozenWindowWidth = 1280
        InspectorPanelTestSupport.settle(window)
        let beforeLeaving = changes
        environment.navigate(to: .inbox)
        InspectorPanelTestSupport.settle(window)
        XCTAssertNil(environment.notesAIFrozenWindowWidth, "真实存在的冻结宽度仍须在离开笔记时清除")
        XCTAssertEqual(changes, beforeLeaving + 1)
    }
}
