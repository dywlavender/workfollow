import XCTest
@testable import WorkFollow

/// 摘要 AI 优化：底层直接调本机 `pi`。默认不跑（真实模型调用慢且要网络），
/// 需要时用 `SUMMARY_AI_INTEGRATION=1` 打开。
final class SummaryPiOptimizerTests: XCTestCase {
    func testWeeklyDraftUsesFixedStructureAndFactualConstraints() {
        let prompt = SummaryPiOptimizer.prompt(text: "原任务事实", options: .weeklyReview)
        for section in ["本周成果", "进展与调整", "本周复盘", "下周重点"] { XCTAssertTrue(prompt.contains(section)) }
        XCTAssertTrue(prompt.contains("不编造"))
        XCTAssertTrue(prompt.contains("子任务推进不能描述成整个父任务已完成"))
        XCTAssertTrue(prompt.contains("原任务事实"))
    }

    func testPromptCarriesOptionsAndSource() {
        var options = SummaryAIOptions()
        options.length = .brief
        options.style = .formal
        options.profession = "产品经理"
        options.hint = "不要用第一人称"
        let prompt = SummaryPiOptimizer.prompt(text: "已完成：写周报", options: options)
        XCTAssertTrue(prompt.contains("长度：简短"))
        XCTAssertTrue(prompt.contains("语言风格：正式"))
        XCTAssertTrue(prompt.contains("职业：产品经理"))
        XCTAssertTrue(prompt.contains("额外要求：不要用第一人称"))
        XCTAssertTrue(prompt.contains("已完成：写周报"))
        XCTAssertTrue(prompt.contains("只输出改写后的正文"))
    }

    func testSummaryPromptPreservesGroupHeadingsInsteadOfAddingWeeklySections() {
        let prompt = SummaryPiOptimizer.prompt(text: "已完成\n- 写周报", options: SummaryAIOptions())
        XCTAssertTrue(prompt.contains("保留原文的日期范围"))
        XCTAssertTrue(prompt.contains("不要新增或删除分组标题"))
        XCTAssertTrue(prompt.contains("Markdown 标题与列表"))
        XCTAssertFalse(prompt.contains("本周成果"))
        XCTAssertFalse(prompt.contains("进展与调整"))
    }

    func testMarkdownHeadingsKeepFlatSummaryStructure() {
        let title = "10月19日-10月25日"
        let response = """
        # \(title)
        ## 已完成
        - [10月20日] 写周报
        ### 备注
        - 手写补充
        ## 未完成
        - 整理文档
        """
        let document = WeeklyReportBuilder.aiDocument(text: response, title: title)
        XCTAssertEqual(document.blocks.first?.kind, .heading(1))
        XCTAssertEqual(document.blocks.filter { $0.plainText == title }.count, 1)
        XCTAssertEqual(document.blocks.filter { $0.kind == .heading(2) }.map(\.plainText), ["已完成", "未完成"])
        XCTAssertTrue(document.blocks.contains { $0.kind == .heading(3) && $0.plainText == "备注" })
        XCTAssertEqual(document.blocks.filter { $0.kind == .bullet }.count, 3)
    }

    func testFormattedResponseKeepsOneDateTitleAndEditableReflection() {
        let title = "10月19日-10月25日"
        let response = """
        10月19日-10月25日
        **本周成果**
        - 接口联调已完成。
        **进展与调整**
        - 交付文档仍需补充说明。
        **本周复盘**
        - 下次评审前先核对接口清单。
        **下周重点**
        - 安排用户访谈。
        """
        let document = WeeklyReportBuilder.aiDocument(text: response, title: title)
        XCTAssertEqual(document.blocks.first?.kind, .heading(1))
        XCTAssertEqual(document.blocks.filter { $0.plainText == title }.count, 1)
        XCTAssertTrue(WeeklyReportBuilder.reflection(in: document).contains { $0.plainText == "下次评审前先核对接口清单。" })
    }

    func testOptimizerReportsUnavailableForMissingBinary() async {
        var optimizer = SummaryPiOptimizer()
        optimizer.executable = "/nonexistent/pi"
        do {
            _ = try await optimizer.optimize(text: "任一文本", options: SummaryAIOptions())
            XCTFail("缺失 pi 时应抛错")
        } catch let error as SummaryPiError {
            guard case .unavailable = error else {
                return XCTFail("期望 unavailable，实际 \(error)")
            }
        } catch {
            XCTFail("期望 SummaryPiError，实际 \(error)")
        }
    }

    func testCancellationStopsTheOwnedGenerationProcess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("fake-pi")
        try "#!/usr/bin/env python3\nimport pathlib, time\npathlib.Path(__file__).with_name('started').write_text('ready')\ntime.sleep(10)\nprint('late result')\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var optimizer = SummaryPiOptimizer(); optimizer.executable = script.path
        let work = _Concurrency.Task { try await optimizer.optimize(text: "任务事实", options: .weeklyReview) }
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: folder.appendingPathComponent("started").path) && Date() < deadline {
            try await _Concurrency.Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("started").path))
        let cancelledAt = Date()
        work.cancel()
        do { _ = try await work.value; XCTFail("取消后不应交付草稿") }
        catch is CancellationError { }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 2)
    }

    func testLongModelOutputDoesNotBlockOnPipeCapacity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("summary-output-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("fake-pi")
        try "#!/usr/bin/env python3\nprint('x' * 100000)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        var optimizer = SummaryPiOptimizer(); optimizer.executable = script.path; optimizer.timeout = 3
        let text = try await optimizer.optimize(text: "任务事实", options: .weeklyReview)
        XCTAssertEqual(text.count, 100000)
    }

    func testOptimizerCallsPiWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["SUMMARY_AI_INTEGRATION"] == "1" else {
            throw XCTSkip("Enable SUMMARY_AI_INTEGRATION=1 to call the real model")
        }
        let optimizer = SummaryPiOptimizer()
        guard FileManager.default.isExecutableFile(atPath: optimizer.executable) else {
            throw XCTSkip("pi not installed")
        }
        for isWeekly in [true, false] {
            var options = SummaryAIOptions.weeklyReview
            options.isWeeklyPeriod = isWeekly
            let title = isWeekly ? "10月19日-10月25日" : "10月1日-10月31日"
            let results = isWeekly ? "本周成果" : "本期成果"
            let reflection = isWeekly ? "本周复盘" : "本期复盘"
            let next = isWeekly ? "下周重点" : "下一周期任务"
            let source = """
            \(title)
            \(results)
            已完成：接口联调，10月20日完成。
            进展与调整
            未完成：交付文档，仍需补充使用说明。
            \(reflection)
            下次评审前先核对接口清单。
            \(next)
            安排一次用户访谈。
            """
            let result = try await optimizer.optimize(text: source, options: options)
            XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let document = WeeklyReportBuilder.aiDocument(text: result, title: title)
            XCTAssertEqual(document.blocks.filter { $0.plainText == title }.count, 1)
            let headings = document.blocks.filter { $0.kind == .heading(2) }.map(\.plainText)
            XCTAssertEqual(headings, [results, "进展与调整", reflection, next])
            XCTAssertFalse(WeeklyReportBuilder.reflection(in: document).isEmpty)
            print("AI 真实调用验收（虚构任务，\(title)）：\n\(result)")
        }
    }
}
