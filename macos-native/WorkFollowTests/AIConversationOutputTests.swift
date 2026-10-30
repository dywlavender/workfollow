import XCTest
@testable import WorkFollow

@MainActor
final class AIConversationOutputTests: XCTestCase {
    func testOrdinaryDiscussionAndCodeStayOrdinaryAfterShortcut() throws {
        let output = try AIConversationOutput.decode("解释如下。\n```json\n{\"tasks\":[]}\n```", preset: nil)
        XCTAssertTrue(output.artifacts.isEmpty)
        XCTAssertTrue(output.text.contains("```json"))
    }
    func testOptionalResultsKeepProseAndHideMachinePayloadWhileStreaming() throws {
        let raw = "已调整日期。\n```workfollow-tasks\n{\"tasks\":[{\"title\":\"核对成本\",\"date\":\"2026-11-04\"}]}\n```\n继续讨论也可以。"
        XCTAssertEqual(AIConversationOutput.preview(raw), "已调整日期。")
        let output = try AIConversationOutput.decode(raw, preset: nil)
        XCTAssertEqual(output.artifacts.count, 1)
        XCTAssertEqual(output.artifacts.first?.kind, .tasks)
        XCTAssertTrue(output.text.contains("继续讨论也可以。"))
        XCTAssertFalse(output.text.contains("workfollow-tasks"))
        let draft = try AIConversationOutput.decode("```workfollow-note\n{\"content\":\"正文\\n第二段\"}\n```", preset: nil)
        XCTAssertEqual(draft.artifacts.first?.content, "正文\n第二段")
    }
    func testReceiptsReachBothTransientSurfaces() {
        for scene in [AIConversationModel.Scene.note, .selection] {
            let model = AIConversationModel(record: .init(messages: [.init(role: .assistant, text: "")]), scene: scene)
            let token = UUID()
            let receipt = AIActionReceipt(title: "虚构笔记", url: nil, details: "已保存", undoID: token)
            XCTAssertTrue(AIConversationRegistry.shared.append(receipt, id: model.record.id))
            XCTAssertEqual(model.record.messages.last?.actions?.first?.title, "虚构笔记")
            AIConversationRegistry.shared.markUndone(token)
            XCTAssertTrue(model.record.messages.last?.actions?.first?.undone == true)
        }
    }
}
