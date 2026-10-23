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
        let rowStart = try XCTUnwrap(list.range(of: "struct TaskRowView: View"))
        let row = String(list[rowStart.lowerBound...])
        XCTAssertEqual(try occurrenceCount(of: "\\.popover\\s*\\(", in: row), 0)
        XCTAssertTrue(list.contains("AnchoredPropertyPanel(isPresented: $showQuickAddProperties"))
        XCTAssertTrue(row.contains(".schedulePopover("))
        let contextMenu = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskList/TaskContextMenuPopover.swift"), encoding: .utf8)
        XCTAssertTrue(contextMenu.contains("TaskTagPickerPopover(initialTags:"))
        XCTAssertTrue(contextMenu.contains(".background(AnchoredPropertyPanel("))
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

    /// 「分组是清单里面的二级菜单」：清单是第一级、分组是第二级（合起来是菜单的第三层）。
    ///
    /// 盯的是**结构**不是文案：分组选择器必须由 `TaskContextListPicker` 的清单行展开，
    /// 而不是回到顶层当一个与「移动到清单」平级的行。子任务是唯一例外——
    /// `moveToList` 不收子任务，它没有「移动到清单」可用，所以保留一条顶层入口。
    func testSectionPickerNestsUnderTheListSubmenu() throws {
        let source = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskList/TaskContextMenuPopover.swift"), encoding: .utf8)

        let pickerStart = try XCTUnwrap(
            source.range(of: "private struct TaskContextListPicker: View")?.lowerBound)
        let sectionStart = try XCTUnwrap(
            source.range(of: "private struct TaskContextSectionPicker: View")?.lowerBound)
        XCTAssertLessThan(pickerStart, sectionStart, "两个 struct 的顺序变了，下面的切片不成立")
        let picker = String(source[pickerStart..<sectionStart])
        XCTAssertTrue(picker.contains("TaskContextSectionPicker("),
                      "分组选择器必须由清单行展开，而不是另开一个顶层入口")
        XCTAssertTrue(picker.contains("placement: .submenu"),
                      "分组面板挂在清单行右侧（`.submenu` = 锚点行右侧）")

        XCTAssertEqual(try occurrenceCount(of: "menuRow\\(\"移动到分组\"", in: source), 1,
                       "顶层只剩子任务那一条兼容入口；根任务不再有「移动到分组」行")
        XCTAssertTrue(source.contains("if task.parentID != nil, task.list.name != TaskList.inbox.name"),
                      "那条入口只给子任务；根任务走「移动到清单 → 分组」")
    }

    /// 「可反复改的属性」点完**不收**菜单，「一次性命令」点完收。
    ///
    /// 这条盯的是那条分界线本身。混进来一个，用户就得重新右键一次才能改主意——
    /// 而菜单本来就在手边、鼠标也还在上面。反过来把命令类做成不收，
    /// 删除/转换之后菜单还杵在那里，更糟。
    func testRepeatablePropertiesKeepMenuOpenWhileCommandsDismissIt() throws {
        let source = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskList/TaskContextMenuPopover.swift"), encoding: .utf8)

        // 可反复改的属性 → apply（就地执行，菜单留着）
        // `clearDueDate` 已经不在菜单里（日期改由日程面板清除），从清单里去掉。
        for call in ["workspace.moveDueDate(", "workspace.setPriority(",
                     "workspace.moveToList(", "workspace.setTaskSection("] {
            XCTAssertTrue(source.contains("apply { _ = \(call)"),
                          "\(call) 是可反复改的属性，必须走 apply（点完不收菜单）")
            XCTAssertFalse(source.contains("perform { _ = \(call)"),
                           "\(call) 不该走 perform——那会让用户改一次就得重新右键")
        }

        // 一次性命令 / 会开别的窗口 / 不可逆 → perform（先关菜单再执行）
        for call in ["workspace.delete(", "workspace.skip(", "workspace.duplicate(",
                     "environment.convertTaskToNote("] {
            XCTAssertTrue(source.contains("perform { _ = \(call)")
                            || source.contains("perform { \(call)"),
                          "\(call) 是一次性命令，必须走 perform（点完收菜单）")
        }

        // 「开始专注」抽成了私有方法，收菜单写在方法体里——断言同样要盯住
        // 「点完就收」，而不是它有没有用 perform 这个字面写法。
        let focusStart = try XCTUnwrap(source.range(of: "private func startFocus("),
                                       "开始专注的入口不见了")
        let focusBody = String(source[focusStart.lowerBound...].prefix(700))
        XCTAssertTrue(focusBody.contains("isPresented = false"),
                      "开始专注是一次性命令，执行后必须收菜单")
    }

    /// 「可反复改的属性」点完必须留着面板。
    ///
    /// ⚠️ 这三处（清单颜色 / 清单图标 / 倒数日图标）原来都是 `改值` 紧接一个关闭调用，
    /// 用户想换个色得把面板重新点开一遍。留着的前提是**选中态读活值**
    /// （`listMeta` / `symbol` 都随写入更新），否则「不关」会退化成「不刷新」——
    /// 那就比原来更糟。
    func testRepeatablePropertyPickersKeepTheirPanelOpen() throws {
        let management = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Tasks/TaskManagementViews.swift"), encoding: .utf8)

        let colorAction = try actionBody(
            in: management, from: "_ = workspace.setListColor(name, colorIndex: index)")
        XCTAssertFalse(colorAction.contains("onDismiss"),
                       "选颜色是可反复改的属性，点完不该关面板")

        let iconAction = try actionBody(in: management, from: "_ = workspace.setListIcon(name, emoji)")
        XCTAssertFalse(iconAction.contains("onDismiss"),
                       "选图标是可反复改的属性，点完不该关面板")

        let clearAction = try actionBody(in: management, from: "_ = workspace.setListIcon(name, nil)")
        XCTAssertFalse(clearAction.contains("onDismiss"),
                       "「无图标」清除后要留在面板里，否则看不到它变成「无图标（当前）」")

        // 呈现宿主必须还在：Esc（`PopupEscapeRegistry` 按键名次、子面板压过宿主）
        // 与「点面板外」（`PopupInteractionRegistry`）都由 AnchoredPropertyPanel 提供。
        // 换掉它，这两条关闭通道会一起消失，面板就再也关不掉了。
        for marker in ["isPresented: $showColorPicker", "isPresented: $showIconPicker"] {
            XCTAssertTrue(management.contains("AnchoredPropertyPanel(\(marker)"),
                          "\(marker) 必须仍由 AnchoredPropertyPanel 呈现")
        }

        let countdown = try String(contentsOf: businessSourceRoot.appendingPathComponent(
            "Features/Countdown/CountdownEditorView.swift"), encoding: .utf8)
        let symbolAction = try actionBody(in: countdown, from: "symbol = option")
        XCTAssertFalse(symbolAction.contains("symbolPickerOpen = false"),
                       "换图标不提交任何东西（仍要按确定），点完不该关面板")
        XCTAssertTrue(countdown.contains(".background(AnchoredPropertyPanel(isPresented: $symbolPickerOpen"),
                      "倒数日图标面板必须仍由 AnchoredPropertyPanel 呈现")
        // 留着的面板需要一个**看得见**的关闭口：再点一次图标按钮。
        XCTAssertTrue(countdown.contains("symbolPickerOpen.toggle()"),
                      "图标按钮必须仍是 toggle——面板留着时它是唯一可见的关闭口")
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

    /// 取「某个写入调用 → 它所在闭包的 `} label:`」之间那段源码。
    /// 这一段的职责就是「点下去做什么」，所以「点完关不关面板」在这里断言最贴切：
    /// 关闭调用一定紧跟写入，写成别处就说明改法变了。
    private func actionBody(in source: String, from marker: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: marker), "源码里找不到标记：\(marker)")
        let tail = source[start.upperBound...]
        let end = try XCTUnwrap(tail.range(of: "} label:"),
                                "标记之后找不到 `} label:`，闭包形状变了：\(marker)")
        return String(tail[..<end.lowerBound])
    }

    private func occurrenceCount(of pattern: String, in source: String) throws -> Int {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.numberOfMatches(in: source, range: range)
    }
}
