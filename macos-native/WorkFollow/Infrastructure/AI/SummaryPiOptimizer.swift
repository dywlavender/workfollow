import Foundation

/// 摘要 AI 优化的参数（对齐滴答「内容优化」：长度 / 语言风格 / 职业 + 自定义要求）。
struct SummaryAIOptions: Equatable, Codable {
    enum Length: String, CaseIterable, Codable {
        case brief = "简短"
        case normal = "默认"
        case detailed = "详细"
    }

    enum Style: String, CaseIterable, Codable {
        case plain = "平实"
        case warm = "温暖"
        case formal = "正式"
    }

    var length: Length = .normal
    var style: Style = .plain
    var profession: String = ""
    /// 滴答的 `ai_improve_hint`：一句话补充要求。
    var hint: String = ""
    var weeklyStructure = false
    var isWeeklyPeriod = true

    static var weeklyReview: SummaryAIOptions {
        var value = SummaryAIOptions()
        value.length = .brief
        value.weeklyStructure = true
        return value
    }
}

enum SummaryPiError: LocalizedError {
    case unavailable
    case timedOut
    case failed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unavailable: "找不到 pi 可执行文件（需要先安装 pi）"
        case .timedOut: "AI 优化超时，请稍后重试"
        case .failed(let message): message
        case .emptyResult: "AI 没有返回内容"
        }
    }
}

/// 摘要的 AI 优化：直接调本机 `pi`（与会议纪要同一条通道），不做模型端点请求。
///
/// 与 `MeetingPiClient` 保持同样的隔离参数：一次性 `--print`、禁用会话、工具、
/// 扩展、技能、提示模板与上下文文件，避免把仓库里的提示词带进结果。
struct SummaryPiOptimizer {
    var executable: String = "/opt/homebrew/bin/pi"
    var timeout: TimeInterval = 90

    func optimize(text: String, options: SummaryAIOptions) async throws -> String {
        let prompt = Self.prompt(text: text, options: options)
        return try await withTaskCancellationHandler {
            try await _Concurrency.Task.detached(priority: .userInitiated) {
                try Self.run(executable: executable, prompt: prompt, timeout: timeout)
            }.value
        } onCancel: {}
    }

    static func prompt(text: String, options: SummaryAIOptions) -> String {
        var lines = [
            "把下面这份工作周报改写成一段连贯的总结文字。",
            "长度：\(options.length.rawValue)",
            "语言风格：\(options.style.rawValue)",
        ]
        if options.weeklyStructure {
            let results = options.isWeeklyPeriod ? "本周成果" : "本期成果"
            let reflection = options.isWeeklyPeriod ? "本周复盘" : "本期复盘"
            let next = options.isWeeklyPeriod ? "下周重点" : "下一周期任务"
            lines[0] = "根据所给任务事实，整理一份简洁中文任务回顾，遵守原文的日期范围。"
            lines += [
                "固定保留四个标题：\(results)、进展与调整、\(reflection)、\(next)。",
                "只能使用原文中的事实，不编造成果、原因、数字、完成状态或下周安排。",
                "子任务推进不能描述成整个父任务已完成；结转任务不能描述成成果。",
                "保留手写复盘的意思，缺少复盘时留空，不补写评价。",
                "每个标题单独一行，任务用短列表，避免空话。"
            ]
        }
        if !options.profession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("职业：\(options.profession)")
        }
        if !options.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("额外要求：\(options.hint)")
        }
        lines.append(options.weeklyStructure
            ? "只输出改写后的正文，使用上述四个标题，不要额外解释。"
            : "只输出改写后的正文，不要解释、不要重复原文、不要加标题。")
        lines.append("")
        lines.append("原文：")
        lines.append(text)
        return lines.joined(separator: "\n")
    }

    private static func run(executable: String, prompt: String, timeout: TimeInterval) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw SummaryPiError.unavailable
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = ["--print", "--no-session", "--no-tools", "--no-extensions",
                           "--no-skills", "--no-prompt-templates", "--no-context-files",
                           "--offline", prompt]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        child.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        child.standardOutput = stdout
        child.standardError = stderr

        do {
            try child.run()
        } catch {
            throw SummaryPiError.failed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while child.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if child.isRunning {
            child.terminate()
            throw SummaryPiError.timedOut
        }

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard child.terminationStatus == 0 else {
            let message = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SummaryPiError.failed(message.isEmpty ? "pi 退出码 \(child.terminationStatus)" : message)
        }
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw SummaryPiError.emptyResult }
        return result
    }
}
