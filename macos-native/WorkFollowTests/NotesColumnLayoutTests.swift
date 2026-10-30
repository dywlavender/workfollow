import XCTest
@testable import WorkFollow

final class NotesColumnLayoutTests: XCTestCase {
    private func layout(_ contentWidth: CGFloat, aiWidth: CGFloat = 360,
                        aiOpen: Bool = true, detailOnly: Bool = false,
                        noteExists: Bool = true, trash: Bool = false) -> NotesColumnLayout {
        NotesColumnLayoutEngine.layout(contentWidth: contentWidth,
                                       storedPaneWidth: WFMetrics.listPreferred,
                                       storedAIWidth: aiWidth,
                                       aiOpen: aiOpen, detailOnly: detailOnly,
                                       noteExists: noteExists, trash: trash)
    }

    func testFiveColumnThresholdMatchesDefaults() {
        // 图标栏 62 + 文件夹 212 + 列表 320 + 正文 480 + AI 360 + 两条分割线。
        XCTAssertEqual(NotesFolderColumnMetrics.requiredWindowWidth(listWidth: 320, aiWidth: 360), 1436)
    }

    func testFolderOnlyYieldsWhenItSavesTheList() {
        // 收起文件夹后，列表 + 正文 480 + AI 280 仍能并排的最小窗口宽度。
        XCTAssertEqual(NotesFolderColumnMetrics.requiredWindowWidthForList(listWidth: 320), 1144)
    }

    func testWideWindowKeepsListEditorAndDockedAI() {
        let result = layout(1162)
        XCTAssertTrue(result.wide)
        XCTAssertTrue(result.showList)
        XCTAssertTrue(result.aiVisible)
        XCTAssertEqual(result.paneWidth, 320)
        XCTAssertEqual(result.aiWidth, 360)
    }

    func testFolderHiddenRangeKeepsListWithNarrowedAI() {
        // 1200 窗口、文件夹已收起：列表 + 正文 480 + AI 336。
        let content = 1200 - WFMetrics.railWidth
        let result = layout(content)
        XCTAssertTrue(result.wide)
        XCTAssertTrue(result.showList)
        XCTAssertEqual(result.aiWidth, 336)
        XCTAssertEqual(content - result.paneWidth - WFMetrics.divider
                           - result.aiWidth - WFMetrics.divider,
                       NoteAIPaneMetrics.editorMinimumWidth)
    }

    func testListYieldsWhenThreeColumnsCannotStayComfortable() {
        // 1120 窗口、文件夹保留：列表让位，正文 485 + AI 360，与改动前的窄窗口行为一致。
        let content = 1120 - WFMetrics.railWidth - WFMetrics.navigationWidth
        let result = layout(content)
        XCTAssertTrue(result.wide)
        XCTAssertFalse(result.showList)
        XCTAssertTrue(result.aiVisible)
        XCTAssertEqual(result.aiWidth, 360)
        XCTAssertEqual(content - result.aiWidth - WFMetrics.divider, 485)
    }

    func testTighterWindowShrinksAIOnlyAfterListYields() {
        // 1000 窗口、文件夹保留：AI 退到最小宽度，正文 445。
        let content = 1000 - WFMetrics.railWidth - WFMetrics.navigationWidth
        let result = layout(content)
        XCTAssertFalse(result.showList)
        XCTAssertEqual(result.aiWidth, NoteAIPaneMetrics.minimumWidth)
        XCTAssertEqual(content - result.aiWidth - WFMetrics.divider, 445)
    }

    func testNavigationBreakpointWindowStillHidesListForAI() {
        // 840 窗口没有文件夹列：列表让位，正文 480 + AI 297。
        let content = 840 - WFMetrics.railWidth
        let result = layout(content)
        XCTAssertTrue(result.wide)
        XCTAssertFalse(result.showList)
        XCTAssertEqual(result.aiWidth, 297)
        XCTAssertEqual(content - result.aiWidth - WFMetrics.divider,
                       NoteAIPaneMetrics.editorMinimumWidth)
    }

    func testBelowSplitMinimumFallsBackToSingleColumn() {
        let listOnly = layout(600)
        XCTAssertFalse(listOnly.wide)
        XCTAssertTrue(listOnly.showList)
        XCTAssertFalse(listOnly.aiVisible)

        let editing = layout(600, detailOnly: true)
        XCTAssertFalse(editing.wide)
        XCTAssertFalse(editing.showList)
        XCTAssertTrue(editing.aiVisible)
        XCTAssertEqual(editing.aiWidth, NoteAIPaneMetrics.minimumWidth)
    }

    func testExpandedWindowKeepsOriginalColumnWidths() {
        // 900 内容宽度原本是列表 320 + 正文 579；右扩 360 后列表不变，正文只让出新增的分割线。
        let base: CGFloat = 900
        let expanded = layout(base + 360, aiWidth: 360)
        XCTAssertTrue(expanded.wide)
        XCTAssertTrue(expanded.showList)
        XCTAssertEqual(expanded.aiWidth, 360)
        XCTAssertEqual(expanded.paneWidth, WFMetrics.listPreferred)
        let baseEditor = base - WFMetrics.listPreferred - WFMetrics.divider
        let expandedEditor = base + 360 - expanded.paneWidth
            - WFMetrics.divider * 2 - expanded.aiWidth
        XCTAssertEqual(expandedEditor, baseEditor - WFMetrics.divider)
    }

    func testExpandedNarrowWindowShowsEditorAndAI() {
        // 600 的单栏列表页右扩 360 后能放下正文 + AI，列表让位而不是继续只显示列表。
        let result = layout(960, aiWidth: 360)
        XCTAssertTrue(result.wide)
        XCTAssertFalse(result.showList)
        XCTAssertTrue(result.aiVisible)
        XCTAssertEqual(result.aiWidth, 360)
        XCTAssertEqual(960 - 360 - WFMetrics.divider, 599)
    }

    func testAIDormantWithoutNoteOrInTrash() {
        XCTAssertFalse(layout(1162, noteExists: false).aiVisible)
        XCTAssertFalse(layout(1162, trash: true).aiVisible)
        XCTAssertFalse(layout(1162, aiOpen: false).aiVisible)
    }

    func testAIClosedKeepsListEvenWhenTight() {
        let result = layout(700, aiOpen: false)
        XCTAssertTrue(result.wide)
        XCTAssertTrue(result.showList)
        XCTAssertEqual(result.paneWidth, WFMetrics.listPreferred)
    }

    func testListWidthClampsToAvailableWidth() {
        let result = layout(700, aiOpen: false)
        XCTAssertEqual(result.maximumPaneWidth,
                       700 - WFMetrics.inspectorMinimum - WFMetrics.divider)
    }
}
