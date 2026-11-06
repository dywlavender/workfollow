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
    /// 选区 AI 的三个动作都必须能回写；provider 不按结果块格式返回时也一样。
    func testAllThreeSelectionPresetsStayAdoptableWithPlainTextResult() throws {
        for preset: AIConversationPreset in [.polish, .organize, .translate] {
            let output = try AIConversationOutput.decode("译文正文", preset: preset)
            XCTAssertEqual(output.artifacts.count, 1, "\(preset.rawValue) 应产生可采纳文稿")
            XCTAssertEqual(output.artifacts.first?.kind, .writing)
            XCTAssertEqual(output.artifacts.first?.content, "译文正文")
            XCTAssertEqual(output.text, "")
        }
        let chat = try AIConversationOutput.decode("自由讨论的回复", preset: nil)
        XCTAssertTrue(chat.artifacts.isEmpty, "普通聊天不能凭空冒出可采纳按钮")
        XCTAssertEqual(chat.text, "自由讨论的回复")
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
