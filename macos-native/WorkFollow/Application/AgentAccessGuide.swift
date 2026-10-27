import Foundation

struct AgentAccessGuide {
    enum Agent: String, CaseIterable, Identifiable {
        case workbuddy, codex

        var id: String { rawValue }
        var title: String { self == .workbuddy ? "WorkBuddy" : "Codex" }
    }

    let appURL: URL
    let userDirectory: URL
    let codexDirectory: URL

    init(appURL: URL = Bundle.main.bundleURL,
         userDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         codexDirectory: URL? = nil) {
        self.appURL = appURL
        self.userDirectory = userDirectory
        self.codexDirectory = codexDirectory
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? userDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    var installerURL: URL {
        appURL.appendingPathComponent("Contents/Resources/Automation/install-native-cli.sh")
    }

    var skillURL: URL {
        appURL.appendingPathComponent("Contents/Resources/Skills/workfollow-cli/SKILL.md")
    }

    var cliDirectory: URL { userDirectory.appendingPathComponent(".local/bin", isDirectory: true) }
    var cliURL: URL { cliDirectory.appendingPathComponent("workfollowctl") }

    func skillDirectory(for agent: Agent) -> URL {
        switch agent {
        case .workbuddy: return userDirectory.appendingPathComponent(".workbuddy/skills", isDirectory: true)
        case .codex: return codexDirectory.appendingPathComponent("skills", isDirectory: true)
        }
    }

    func manualCommand(for agent: Agent) -> String {
        """
        WORKFOLLOW_CLI_BIN_DIR=\(Self.quoted(cliDirectory.path)) \\
        WORKFOLLOW_CLI_SKILL_DIR=\(Self.quoted(skillDirectory(for: agent).path)) \\
          /bin/bash \(Self.quoted(installerURL.path)) \(Self.quoted(appURL.path))
        \(Self.quoted(cliURL.path)) status --json
        """
    }

    var aiInstructions: String {
        """
        请帮我把本机 WorkFollow 接入当前 AI 助手，之后我想直接让你查询、新建和修改待办与笔记，管理清单和分组。

        WorkFollow App：\(appURL.path)
        使用说明：\(skillURL.path)
        安装脚本：\(installerURL.path)
        CLI 入口：\(cliURL.path)

        请先读取使用说明，再完成本机配置：
        1. 确认你可以在这台 Mac 上执行命令，并按当前助手实际支持的位置注册 Skill。WorkBuddy 的用户级技能目录是 \(skillDirectory(for: .workbuddy).path)，Codex 是 \(skillDirectory(for: .codex).path)；其他助手使用自身的技能配置目录。
        2. 设置 WORKFOLLOW_CLI_BIN_DIR 为 \(cliDirectory.path)，WORKFOLLOW_CLI_SKILL_DIR 为所选技能目录，用 /bin/bash 执行上面的安装脚本，并把 App 路径作为第一个参数。脚本会创建 CLI 和 Skill 的快捷入口。
        3. 使用 CLI 的 status --json 验证连接，确认 ok=true 和实际 storageDirectory；再运行 --help，按使用说明完成一次只读查询。根据助手的技能加载方式刷新技能或新建对话，确认 workfollow-cli 已可使用。
        4. 后续按 Skill 中的日期、版本和保存规则执行用户指令。当前原生 App 的数据通过这个 CLI 操作；名为 workfollow 的旧 MCP 连接的是另一套数据。

        完成后告诉我接入结果。我希望接着可以直接说：“把这段讨论保存成笔记，再建一个明天下午三点跟进的高优先级待办。”
        """
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
