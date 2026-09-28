import AppKit
import SwiftUI
import XCTest
@testable import WorkFollow

/// 快速输入组合规则的回归：换行批量添加、`#`/`@` 末尾片段识别与替换、候选/描述
/// 状态机，以及「粘贴保换行」这一 AppKit 桥接行为。
///
/// 前四组是纯逻辑，只注入固定字符串；只有粘贴那一组需要真的建一个 `NSTextView`
/// ——那条路径的行为由 AppKit 决定，只能实测，不能靠推理。
final class QuickAddCompositionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 换行批量添加

    func testBatchLinesKeepsSingleLineAsOneEntry() {
        XCTAssertEqual(QuickAddComposition.batchLines(in: "买牛奶"), ["买牛奶"])
        XCTAssertEqual(QuickAddComposition.batchLines(in: "  买牛奶  "), ["买牛奶"])
    }

    func testBatchLinesSplitsOnLineBreaksAndDropsBlanks() {
        XCTAssertEqual(QuickAddComposition.batchLines(in: "买牛奶\n写周报\n"), ["买牛奶", "写周报"])
        XCTAssertEqual(QuickAddComposition.batchLines(in: "买牛奶\n\n   \n写周报"), ["买牛奶", "写周报"])
        XCTAssertEqual(QuickAddComposition.batchLines(in: "\n\n  \n"), [])
        XCTAssertEqual(QuickAddComposition.batchLines(in: ""), [])
    }

    func testBatchLinesNormalizesWindowsAndLegacyLineBreaks() {
        // 从其它应用粘贴过来的文本常常是 CRLF，`\r` 不能当成普通字符留在标题里。
        XCTAssertEqual(QuickAddComposition.batchLines(in: "买牛奶\r\n写周报"), ["买牛奶", "写周报"])
        XCTAssertEqual(QuickAddComposition.batchLines(in: "买牛奶\r写周报"), ["买牛奶", "写周报"])
    }

    // MARK: - 末尾 `#`/`@` 片段

    func testMarkerQueryReadsTrailingTagFragment() throws {
        let marker = try XCTUnwrap(QuickAddComposition.markerQuery(in: "买牛奶 #工作"))

        XCTAssertEqual(marker.kind, .tag)
        XCTAssertEqual(marker.query, "工作")
        XCTAssertEqual(marker.raw, "#工作")
        // 「买牛奶 」占 4 个 UTF-16 位，片段从 4 开始、长 3。
        XCTAssertEqual(marker.range.location, 4)
        XCTAssertEqual(marker.range.length, 3)
    }

    func testMarkerQueryReadsTrailingListFragment() throws {
        let marker = try XCTUnwrap(QuickAddComposition.markerQuery(in: "整理资料 @个人"))

        XCTAssertEqual(marker.kind, .list)
        XCTAssertEqual(marker.query, "个人")
        XCTAssertEqual(marker.range.location, 5)
        XCTAssertEqual(marker.range.length, 3)
    }

    func testMarkerQueryAcceptsBareSymbolAtStartAndAfterWhitespace() throws {
        let bare = try XCTUnwrap(QuickAddComposition.markerQuery(in: "买牛奶 #"))
        XCTAssertEqual(bare.kind, .tag)
        XCTAssertEqual(bare.query, "")
        XCTAssertEqual(bare.raw, "#")
        XCTAssertEqual(bare.range.location, 4)

        let leading = try XCTUnwrap(QuickAddComposition.markerQuery(in: "#工"))
        XCTAssertEqual(leading.query, "工")
        XCTAssertEqual(leading.range.location, 0)
    }

    func testMarkerQueryIgnoresNonTrailingAndNonMarkerWords() {
        // 末尾是空白：没有正在输入的片段。
        XCTAssertNil(QuickAddComposition.markerQuery(in: "买牛奶 #工作 "))
        // 标记符不在词首：是正文里的普通字符，不是标记。
        XCTAssertNil(QuickAddComposition.markerQuery(in: "价格#高"))
        XCTAssertNil(QuickAddComposition.markerQuery(in: "牛奶@家"))
        // 没有标记符。
        XCTAssertNil(QuickAddComposition.markerQuery(in: "买牛奶"))
        XCTAssertNil(QuickAddComposition.markerQuery(in: ""))
    }

    func testMarkerQueryRejectsFragmentCarryingASecondMarker() {
        // 片段里再出现标记符，说明它已经不是「正在输入的名字」。
        XCTAssertNil(QuickAddComposition.markerQuery(in: "买牛奶 #工作#加班"))
        XCTAssertNil(QuickAddComposition.markerQuery(in: "买牛奶 #工作@个人"))
    }

    // MARK: - 候选收敛与过滤

    func testCandidatesFilterCaseInsensitivelyAndHonourEmptyQuery() {
        XCTAssertEqual(QuickAddComposition.candidates(["工作", "个人", "家务"], matching: ""),
                       ["工作", "个人", "家务"])
        XCTAssertEqual(QuickAddComposition.candidates(["工作", "个人", "家务"], matching: "工"), ["工作"])
        XCTAssertEqual(QuickAddComposition.candidates(["Work", "workout"], matching: "WORK"),
                       ["Work", "workout"])
        XCTAssertEqual(QuickAddComposition.candidates(["工作"], matching: "不存在"), [])
    }

    func testCandidatesAreCappedAtThePanelLimit() {
        let names = (1...10).map { "标签\($0)" }
        XCTAssertEqual(QuickAddComposition.candidates(names, matching: "").count,
                       QuickAddComposition.candidateLimit)
        XCTAssertEqual(QuickAddComposition.candidates(names, matching: "", limit: 3),
                       ["标签1", "标签2", "标签3"])
    }

    func testMarkerIsResolvedOnlyByAnExactNameMatch() throws {
        let marker = try XCTUnwrap(QuickAddComposition.markerQuery(in: "买牛奶 #工作"))
        XCTAssertTrue(marker.isResolved(by: ["工作", "家务"]))
        XCTAssertFalse(marker.isResolved(by: ["工作A"]))
        XCTAssertFalse(marker.isResolved(by: []))

        // 只敲下 `#` 时没有可收敛的余地，不该判定为已命中。
        let bare = try XCTUnwrap(QuickAddComposition.markerQuery(in: "买牛奶 #"))
        XCTAssertFalse(bare.isResolved(by: ["工作"]))
    }

    // MARK: - 提交候选

    func testReplacingTrailingMarkerCompletesNameAndAppendsSpace() {
        // 补空格是必要的：末尾不再是标记片段，候选列表随之收起。
        XCTAssertEqual(QuickAddComposition.replacingTrailingMarker(in: "买牛奶 #工", with: "工作"),
                       "买牛奶 #工作 ")
        XCTAssertEqual(QuickAddComposition.replacingTrailingMarker(in: "整理资料 @个", with: "个人"),
                       "整理资料 @个人 ")
        XCTAssertEqual(QuickAddComposition.replacingTrailingMarker(in: "买牛奶 #", with: "工作"),
                       "买牛奶 #工作 ")
    }

    func testReplacingTrailingMarkerLeavesTextWithoutMarkerUntouched() {
        XCTAssertEqual(QuickAddComposition.replacingTrailingMarker(in: "买牛奶", with: "工作"), "买牛奶")
        XCTAssertEqual(QuickAddComposition.replacingTrailingMarker(in: "", with: "工作"), "")
    }

    func testReplacedTextNoLongerCarriesAMarkerQuery() {
        // 提交之后候选列表必须自己消失，否则 Tab / 回车会被一直吞掉。
        let committed = QuickAddComposition.replacingTrailingMarker(in: "买牛奶 #工", with: "工作")
        XCTAssertNil(QuickAddComposition.markerQuery(in: committed))
    }

    // MARK: - 与解析器的配合

    func testCommittedTagAndListFragmentsAreRecognizedByTheParser() {
        let tagResult = QuickAddParser.parse(
            QuickAddComposition.replacingTrailingMarker(in: "写周报 #工", with: "工作"),
            now: now, calendar: calendar, knownLists: ["收集箱"])
        XCTAssertEqual(tagResult.tags, ["工作"])
        XCTAssertEqual(tagResult.title, "写周报")

        let listResult = QuickAddParser.parse(
            QuickAddComposition.replacingTrailingMarker(in: "写周报 @个", with: "个人"),
            now: now, calendar: calendar, knownLists: ["收集箱", "个人"])
        XCTAssertEqual(listResult.listName, "个人")
        XCTAssertEqual(listResult.title, "写周报")
    }

    // MARK: - 候选 / 描述状态机（列表快速添加条与全局面板共用）

    func testMarkerIsIgnoredWhileUnfocusedAndAfterEscape() {
        var state = QuickAddCandidateState()
        XCTAssertNil(state.marker(in: "买牛奶 #工", isFocused: false),
                     "输入框没聚焦时不该弹候选")
        XCTAssertNotNil(state.marker(in: "买牛奶 #工", isFocused: true))

        // 一次 Esc 只收掉候选列表这一层，草稿不动。
        state.dismiss(draft: "买牛奶 #工")
        XCTAssertNil(state.marker(in: "买牛奶 #工", isFocused: true))
        XCTAssertEqual(state.selection, 0)

        // 继续打字就重新给候选：忽略状态只在文本变化前有效。
        state.textDidChange()
        XCTAssertNotNil(state.marker(in: "买牛奶 #工作", isFocused: true))
    }

    func testCandidateListCollapsesOnceTheFragmentExactlyMatchesAName() {
        let state = QuickAddCandidateState()
        let names = ["工作", "家务"]

        // 片段还有收敛空间：列表要留着。
        XCTAssertTrue(state.isListVisible(marker: state.marker(in: "买牛奶 #工", isFocused: true),
                                          names: names))
        // 片段已经精确等于候选名：没有可收敛的空间，把 Tab（进描述）与回车（建任务）
        // 还给用户，否则按回车会一直「提交候选」而永远建不出任务。
        XCTAssertFalse(state.isListVisible(marker: state.marker(in: "买牛奶 #工作", isFocused: true),
                                           names: names))
    }

    func testCandidateListHidesWhenThereIsNothingToOffer() {
        let state = QuickAddCandidateState()
        let bare = state.marker(in: "买牛奶 #", isFocused: true)

        // 只敲了 `#` 但一个候选都没有：不必弹一块空面板。
        XCTAssertFalse(state.isListVisible(marker: bare, names: []))
        XCTAssertTrue(state.isListVisible(marker: bare, names: ["工作"]))
        XCTAssertFalse(state.isListVisible(marker: nil, names: ["工作"]))
    }

    func testSelectionWrapsAroundAndResetsOnTextChange() {
        var state = QuickAddCandidateState()
        XCTAssertTrue(state.move(by: 1, count: 3))
        XCTAssertEqual(state.selection, 1)
        XCTAssertTrue(state.move(by: -1, count: 3))
        XCTAssertEqual(state.selection, 0)
        XCTAssertTrue(state.move(by: -1, count: 3))
        XCTAssertEqual(state.selection, 2, "上键在首项要绕到末项")

        // 没有候选时上下键不该被消费，插入点照常移动。
        XCTAssertFalse(state.move(by: 1, count: 0))

        state.textDidChange()
        XCTAssertEqual(state.selection, 0)
    }

    func testResetClearsEveryLayer() {
        var state = QuickAddCandidateState()
        _ = state.move(by: 1, count: 3)
        state.descriptionVisible = true
        state.dismiss(draft: "买牛奶 #工")

        state.reset()
        XCTAssertEqual(state, QuickAddCandidateState())
    }

    // MARK: - 粘贴保换行（批量添加的入口）

    /// 单行 `NSTextField` 的默认插入路径会把换行换成空格（已实测），
    /// 所以多行粘贴必须由我们自己接管，否则「换行可添加多个任务」形同虚设。
    func testMultiLinePasteIsTakenOverAndKeepsNewlines() {
        var captured = ""
        let representable = QuickAddTextField(
            text: Binding(get: { captured }, set: { captured = $0 }),
            placeholder: "", tokens: [], focused: .constant(false),
            onSubmit: {}, onEscape: {}, onTab: {}, onShiftReturn: {},
            onMoveUp: { false }, onMoveDown: { false }, onFieldFocusChange: { _ in })

        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        XCTAssertTrue(representable.insertPreservingNewlines("买牛奶\n写周报", field: nil, editor: editor))
        XCTAssertEqual(captured, "买牛奶\n写周报", "换行必须原样保留，后续才能按行拆成多个任务")

        // 普通单行粘贴不接管，交回 AppKit 走默认路径（撤销、自动替换等系统行为仍在）。
        XCTAssertFalse(representable.insertPreservingNewlines("买牛奶", field: nil, editor: editor))
        XCTAssertEqual(captured, "买牛奶\n写周报")
    }

    func testPastedBatchIsSplittableIntoOneTaskPerLine() {
        var captured = ""
        let representable = QuickAddTextField(
            text: Binding(get: { captured }, set: { captured = $0 }),
            placeholder: "", tokens: [], focused: .constant(false),
            onSubmit: {}, onEscape: {}, onTab: {}, onShiftReturn: {},
            onMoveUp: { false }, onMoveDown: { false }, onFieldFocusChange: { _ in })
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))

        _ = representable.insertPreservingNewlines("买牛奶\r\n写周报\n\n交材料",
                                                   field: nil, editor: editor)
        XCTAssertEqual(QuickAddComposition.batchLines(in: captured), ["买牛奶", "写周报", "交材料"])
    }

    // MARK: - 按键到回调的路由

    /// 每个按键该走哪个回调，全在 `control(_:textView:doCommandBy:)` 的一张映射表里。
    /// 这张表最容易错的地方是「以为 Shift+↩︎ 也走 insertNewline」——AppKit 的标准键位
    /// 把 `~\r` 映射到 `insertNewlineIgnoringFieldEditor:`，漏接它 Shift+↩︎ 就静默无效。
    func testKeySelectorsRouteToTheMatchingCallback() {
        var log: [String] = []
        var focusLog: [Bool] = []
        let representable = QuickAddTextField(
            text: .constant(""), placeholder: "", tokens: [],
            focused: .constant(false),
            onSubmit: { log.append("submit") },
            onEscape: { log.append("escape") },
            onTab: { log.append("tab") },
            onShiftReturn: { log.append("shiftReturn") },
            onMoveUp: { log.append("up"); return true },
            onMoveDown: { log.append("down"); return true },
            onFieldFocusChange: { focusLog.append($0) })
        let coordinator = representable.makeCoordinator()
        let field = NSTextField()
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 20))

        func press(_ selector: Selector) -> Bool {
            coordinator.control(field, textView: editor, doCommandBy: selector)
        }

        XCTAssertTrue(press(#selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(press(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))))
        XCTAssertTrue(press(#selector(NSResponder.insertTab(_:))))
        XCTAssertTrue(press(#selector(NSResponder.cancelOperation(_:))))
        XCTAssertTrue(press(#selector(NSResponder.moveUp(_:))))
        XCTAssertTrue(press(#selector(NSResponder.moveDown(_:))))
        XCTAssertEqual(log, ["submit", "shiftReturn", "tab", "escape", "up", "down"])

        // 未接管的按键必须放行，否则插入点、选区、IME 都会被吃掉。
        XCTAssertFalse(press(#selector(NSResponder.moveLeft(_:))))
        XCTAssertEqual(log.count, 6)

        // 编辑开始/结束要单独上报聚焦状态，供界面用它决定展开与否。
        coordinator.controlTextDidBeginEditing(
            Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        coordinator.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertEqual(focusLog, [true, false],
                       "控件 → SwiftUI 的聚焦方向必须走这条回调，不能只依赖 delegate 的编辑通知")
    }

    // MARK: - 点击即展开（控件 → SwiftUI 的聚焦方向）

    /// 用户可见的原始诉求：**点一下**输入框就该展开日期/更多，不必先打字。
    ///
    /// 展开与否由「输入框聚焦了没有」决定，而聚焦有两个方向：SwiftUI → 控件
    /// （`focused`，程序化）与控件 → SwiftUI（`onFieldFocusChange`）。后者原先只挂在
    /// delegate 的 `controlTextDidBeginEditing` 上，但 AppKit 在「已经是第一响应者」
    /// 时**不会再发**那个通知——于是「点一下」这条路径可能被静默吞掉，而代码读起来
    /// 完全正常。
    ///
    /// 这里验证的是真正会坏的那两件事：交给 AppKit 的必须是会上报的子类；钩子必须接上，
    /// 且接上之后真的把 `true` 送到 SwiftUI 侧。至于子类里 `mouseDown` 的两行实现
    /// （先调钩子、再交给 `super`）只能靠读——无头测试进程里调 `mouseDown` 会让 AppKit
    /// 进入鼠标跟踪循环等 `mouseUp`，实测直接崩，不能放进用例。
    func testClickReportingFieldHandsFocusToSwiftUIBeforeAnyTyping() {
        var focusLog: [Bool] = []
        let field = QuickAddTextField.makeField(
            text: "", placeholder: "添加任务",
            font: .systemFont(ofSize: 13),
            onFocusChange: { focusLog.append($0) })

        XCTAssertTrue(field is QuickAddFocusReportingField,
                      "交给 AppKit 的必须是会在 mouseDown 时上报的子类，否则「点击」这条路径无人上报")
        XCTAssertEqual(field.identifier?.rawValue, "quick-add-title")
        XCTAssertTrue(focusLog.isEmpty, "还没点击时不该上报聚焦")

        // 直接触发子类在 `mouseDown` 里调用的那个钩子。
        field.onMouseDown?()

        XCTAssertEqual(focusLog, [true],
                       "点一下输入框就必须立刻上报聚焦；「等用户打字才展开」正是这次要修的缺陷")
    }

    // MARK: - 反向收回焦点的判据（「点击后被自己撤销」的护栏）

    /// 历史缺陷：`updateNSView` 在「意图说没聚焦」时当场 `makeFirstResponder(nil)`。
    /// 而当时的「意图」读的是挂在 `NSViewRepresentable` 上的 `@FocusState`——一个
    /// **恒假**的死信号，于是这个分支**每次点击**都命中，把刚拿到的焦点收走，
    /// 展开在同一轮 runloop 里被自己撤销。表现就是「点了没反应、打字才展开」。
    ///
    /// 表里第一行是这次要钉死的那条：意图为真时**绝不能**收回。
    func testRelinquishFocusNeverFiresWhileFocusIsIntended() {
        XCTAssertFalse(QuickAddTextField.shouldRelinquishFocus(intent: true, fieldOwnsFocus: true),
                       "意图要聚焦、控件也确实持有焦点 → 不能收回（否则点击当场被撤销）")
        XCTAssertFalse(QuickAddTextField.shouldRelinquishFocus(intent: true, fieldOwnsFocus: false),
                       "意图要聚焦但控件没有焦点 → 走正向聚焦分支，不是收回")
        XCTAssertTrue(QuickAddTextField.shouldRelinquishFocus(intent: false, fieldOwnsFocus: true),
                      "意图说没聚焦（Esc 第一下）且控件仍持有 → 才收回")
        XCTAssertFalse(QuickAddTextField.shouldRelinquishFocus(intent: false, fieldOwnsFocus: false),
                       "本来就没焦点 → 无事可做")
    }

    /// 程序化聚焦的意图必须是**可写**的普通状态。绑在 `@FocusState` 上时
    /// `wrappedValue = true` 是无效写，读出来永远是 false —— 类型上换掉它，
    /// 这条用例只是把「它现在真的可写」钉住。
    func testFocusIntentBindingIsWritable() {
        var intent = false
        let representable = QuickAddTextField(
            text: .constant(""), placeholder: "", tokens: [],
            focused: Binding(get: { intent }, set: { intent = $0 }),
            onSubmit: {}, onEscape: {}, onTab: {}, onShiftReturn: {},
            onMoveUp: { false }, onMoveDown: { false }, onFieldFocusChange: { _ in })

        let coordinator = representable.makeCoordinator()
        let field = NSTextField()
        coordinator.controlTextDidBeginEditing(
            Notification(name: NSControl.textDidBeginEditingNotification, object: field))
        XCTAssertTrue(intent, "delegate 上报开始编辑必须能写进聚焦意图")
        coordinator.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field))
        XCTAssertFalse(intent, "结束编辑必须能写回 false")
    }

    // MARK: - Tab 描述随任务创建

    func testCreateDraftAttachesDescriptionDocument() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createDraft(title: "写周报", list: "收集箱",
                                       schedule: TaskSchedule(), priority: .none,
                                       tags: [], reminder: nil, repeatFrequency: .never,
                                       document: NativeDocument(plainText: "第一行\n第二行")).taskID

            XCTAssertEqual(model.task(for: id!)?.document.plainText, "第一行\n第二行")
            XCTAssertEqual(model.task(for: id!)?.title, "写周报")
        }
    }

    func testCreateDraftWithoutDescriptionLeavesDocumentEmpty() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createDraft(title: "写周报", list: "收集箱",
                                       schedule: TaskSchedule(), priority: .none,
                                       tags: [], reminder: nil, repeatFrequency: .never).taskID

            XCTAssertEqual(model.task(for: id!)?.document.isEmpty, true)
        }
    }

    func testCreateDraftKeepsDescriptionAndOtherPropertiesInOneTask() async {
        await MainActor.run {
            let model = TaskWorkspaceModel(clock: { self.now }, calendar: self.calendar,
                                           seedDemoData: false)
            let id = model.createDraft(title: "写周报", list: "工作",
                                       schedule: TaskSchedule(), priority: .high,
                                       tags: ["周报"], reminder: nil, repeatFrequency: .weekly,
                                       document: NativeDocument(plainText: "季度总结")).taskID
            let task = model.task(for: id!)

            XCTAssertEqual(task?.document.plainText, "季度总结")
            XCTAssertEqual(task?.tags, ["周报"])
            XCTAssertEqual(task?.priority, .high)
            XCTAssertEqual(task?.list.name, "工作")
            XCTAssertEqual(task?.recurrence, .weekly)
        }
    }
}
