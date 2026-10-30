import AppKit
import XCTest
@testable import WorkFollow

/// TI2-16：标题级别 H4–H5 与三档正文字号（H6 已按产品口径移除）。
@MainActor
final class HeadingLevelTests: XCTestCase {

    func testHeadingPickerOffersBodySizesThenFiveLevels() {
        XCTAssertEqual(EditorCommandCatalog.headingPickerIDs,
                       ["format.paragraph", "format.body1", "format.body2", "format.body3",
                        "format.heading1", "format.heading2",
                        "format.heading3", "format.heading4", "format.heading5"])
        for level in 4...5 {
            let command = EditorCommandCatalog.format("format.heading\(level)")
            XCTAssertEqual(command?.block, .heading(level))
            XCTAssertEqual(command?.title, ["四级标题", "五级标题"][level - 4])
        }
        XCTAssertFalse(EditorCommandCatalog.headingPickerIDs.contains("format.heading6"),
                       "六级标题不再出现在标题选择器里")
        XCTAssertNil(EditorCommandCatalog.format("format.heading6"),
                     "六级标题命令已按产品口径删除（旧档仍可渲染）")
        XCTAssertEqual(DocumentToolbarPicker.heading.titles,
                       ["正文", "正文 1", "正文 2", "正文 3",
                        "一级标题", "二级标题", "三级标题", "四级标题", "五级标题"])
    }

    /// 正文 2 应用到段落：字号 16、块模型记住档位、Delta 往返不丢，再点一次回默认正文。
    func testBodySizeAppliesTogglesAndRoundTripsThroughDelta() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        view.textStorage?.setAttributedString(DocumentTextCodec.render(
            NativeDocument(blocks: [DocumentBlock(kind: .paragraph,
                                                  runs: [DocumentRun(text: "正文档位")])])))
        view.setSelectedRange(NSRange(location: 0, length: 2))
        let command = try XCTUnwrap(EditorCommandCatalog.format("format.body2"))
        view.applyFormat(command)
        let applied = DocumentTextCodec.decode(view.attributedString(), preserving: .empty)
        XCTAssertEqual(applied.blocks.first?.bodySize, .medium)
        XCTAssertEqual((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
                       16)

        let ops = QuillDeltaCodec.delta(from: applied)
        XCTAssertEqual(QuillDeltaCodec.document(from: ops).blocks.first?.bodySize, .medium,
                       "正文档位要写进 Delta 行属性并读回")

        view.applyFormat(command)
        let toggledOff = DocumentTextCodec.decode(view.attributedString(), preserving: .empty)
        XCTAssertNil(toggledOff.blocks.first?.bodySize)
        XCTAssertEqual((view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
                       EditorPreferences.bodyFontSize, "取消档位回到设置页的正文默认字号")
    }

    func testBodySizeCommandsMapToTwelveSixteenEighteenPoints() {
        for (id, size, points) in [("format.body1", DocumentBodySize.small, CGFloat(12)),
                                   ("format.body2", .medium, 16), ("format.body3", .large, 18)] {
            let command = try? XCTUnwrap(EditorCommandCatalog.format(id))
            XCTAssertEqual(command?.bodySize, size)
            let attributes = DocumentTextCodec.attributes(kind: .paragraph, marks: [], bodySize: size)
            XCTAssertEqual((attributes[.font] as? NSFont)?.pointSize, points, id)
        }
    }

    /// 四级及以下沿用 14pt（与 H3 同阶，`DocumentFormatStyleTests` 的滴答实测合同），
    /// 这里锁住"新增级别不偷偷改字阶"。
    func testHeadingFourToSixKeepTheExistingScale() {
        for level in 3...6 {
            let attributes = DocumentTextCodec.attributes(kind: .heading(level), marks: [])
            let font = try? XCTUnwrap(attributes[.font] as? NSFont)
            XCTAssertEqual(font?.pointSize, 14, "H\(level) 应为 14pt")
        }
    }

    /// 输入期：`#### ` 起头已经是 H4（MarkdownSyntax 早就支持，本轮补的是命令/选择器）。
    func testTypingFourHashesCreatesHeadingFour() throws {
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200), textContainer: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeFirstResponder(view)
        defer { window.close() }
        for character in "#### 标题四" {
            view.insertText(String(character), replacementRange: view.selectedRange())
        }

        let document = DocumentTextCodec.decode(view.attributedString(), preserving: NativeDocument(plainText: ""),
                                                trailing: view.pendingTrailingBlock)
        XCTAssertEqual(document.blocks.first?.kind, .heading(4))
        XCTAssertEqual(document.blocks.first?.runs.map(\.text).joined(), "标题四")
    }
}

/// TI2-11：打印稿排版（打印动作本身走系统面板，测试只锁内容）。
@MainActor
final class TaskPrintServiceTests: XCTestCase {

    func testPrintDocumentCarriesTitleMetaBodyAndSubtasks() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let parent = try XCTUnwrap(workspace.createTask(title: "季度复盘", in: .inbox).taskID)
        let childA = try XCTUnwrap(workspace.createChild(parent, title: "整理数据").taskID)
        let childB = try XCTUnwrap(workspace.createChild(parent, title: "写结论").taskID)
        workspace.setTags(parent, ["工作"])
        workspace.setPriority(parent, .high)
        workspace.setDocument(parent, NativeDocument(blocks: [
            DocumentBlock(kind: .heading(2), runs: [DocumentRun(text: "背景")]),
            DocumentBlock(kind: .paragraph, runs: [DocumentRun(text: "本季度目标回顾")]),
            DocumentBlock(kind: .checklist(true), runs: [DocumentRun(text: "收集周报")])
        ]))
        let task = try XCTUnwrap(workspace.task(for: parent))
        let completed = try XCTUnwrap(workspace.task(for: childA))
        _ = workspace.changeStatus(completed)
        let subtasks = [try XCTUnwrap(workspace.task(for: childA)),
                        try XCTUnwrap(workspace.task(for: childB))]
            .sorted { $0.childOrder < $1.childOrder }

        let document = TaskPrintService.document(for: task, subtasks: subtasks,
                                                 calendar: workspace.calendar,
                                                 now: Date(timeIntervalSince1970: 1_790_000_000))
        let text = document.string
        XCTAssertTrue(text.contains("季度复盘"))
        XCTAssertTrue(text.contains("收集箱"))
        XCTAssertTrue(text.contains("#工作"))
        XCTAssertTrue(text.contains("高优先级"))
        XCTAssertTrue(text.contains("背景"))
        XCTAssertTrue(text.contains("本季度目标回顾"))
        XCTAssertTrue(text.contains("☑  收集周报"), "勾选状态要带进打印稿")
        XCTAssertTrue(text.contains("子任务"))
        XCTAssertTrue(text.contains("☑  整理数据"), "已完成子任务用勾选符号")
        XCTAssertTrue(text.contains("☐  写结论"))

        let titleFont = document.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(titleFont?.pointSize, 18)
    }

    func testEmptyDocumentStillPrintsTitleAndMeta() throws {
        let workspace = TaskWorkspaceModel(seedDemoData: false)
        let id = try XCTUnwrap(workspace.createTask(title: "只有标题", in: .inbox).taskID)
        let task = try XCTUnwrap(workspace.task(for: id))
        let text = TaskPrintService.document(for: task, subtasks: [],
                                             calendar: workspace.calendar,
                                             now: Date(timeIntervalSince1970: 1_790_000_000)).string
        XCTAssertTrue(text.contains("只有标题"))
        XCTAssertFalse(text.contains("子任务"))
    }
}
