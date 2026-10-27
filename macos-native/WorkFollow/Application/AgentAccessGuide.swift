struct AgentAccessGuide {
    enum Agent: String, CaseIterable, Identifiable {
        case workbuddy, codex

        var id: String { rawValue }
        var title: String { self == .workbuddy ? "WorkBuddy" : "Codex" }
    }

    func manualCommand(for agent: Agent) -> String {
        let skillDirectory: String
        switch agent {
        case .workbuddy: skillDirectory = "${WORKFOLLOW_CLI_SKILL_DIR:-$HOME/.workbuddy/skills}"
        case .codex: skillDirectory = "${WORKFOLLOW_CLI_SKILL_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
        }
        return """
        (
          set -e
          export WORKFOLLOW_CLI_SKILL_DIR="\(skillDirectory)"
          export WORKFOLLOW_CLI_BIN_DIR="${WORKFOLLOW_CLI_BIN_DIR:-$HOME/.local/bin}"
          if [ -z "${WORKFOLLOW_APP_PATH:-}" ]; then
            for WORKFOLLOW_CANDIDATE in "/Applications/WorkFollow.app" "$HOME/Applications/WorkFollow.app"; do
              if [ -f "$WORKFOLLOW_CANDIDATE/Contents/Resources/Automation/install-native-cli.sh" ]; then
                WORKFOLLOW_APP_PATH="$WORKFOLLOW_CANDIDATE"
                break
              fi
            done
          fi
          if [ ! -f "${WORKFOLLOW_APP_PATH:-}/Contents/Resources/Automation/install-native-cli.sh" ]; then
            printf '%s\\n' '没有找到 WorkFollow。请将 App 放入应用程序文件夹，或先设置 WORKFOLLOW_APP_PATH 为实际 .app 路径。' >&2
            exit 1
          fi
          /bin/bash "$WORKFOLLOW_APP_PATH/Contents/Resources/Automation/install-native-cli.sh" "$WORKFOLLOW_APP_PATH"
          "$WORKFOLLOW_CLI_BIN_DIR/workfollowctl" status --json
        )
        """
    }

    var aiInstructions: String {
        """
        请帮我把目标 Mac 上的 WorkFollow 接入当前 AI 助手，之后我想直接让你查询、新建和修改待办与笔记，管理清单和分组。

        请在目标 Mac 上执行配置，下面的 $HOME、CODEX_HOME 和 App 位置都以目标机器的实际环境为准：
        1. 确认你可以在目标 Mac 上执行命令，定位已安装的 WorkFollow。常见位置是 /Applications/WorkFollow.app 和 $HOME/Applications/WorkFollow.app；其他位置请通过目标机器的应用信息或用户提供的位置确认。也可通过 WORKFOLLOW_APP_PATH 指定实际 .app 路径。
        2. 使用说明位于 App 内的 Contents/Resources/Skills/workfollow-cli/SKILL.md。请先读取它，再按当前助手实际支持的位置注册 Skill。WorkBuddy 默认使用 $HOME/.workbuddy/skills，Codex 使用 ${CODEX_HOME:-$HOME/.codex}/skills；其他助手按自身配置选择。
        3. 安装脚本位于 App 内的 Contents/Resources/Automation/install-native-cli.sh。设置 WORKFOLLOW_CLI_SKILL_DIR 为所选技能目录，再用 /bin/bash 执行该脚本。内置脚本可以自行定位所属 App，也可将实际 App 路径作为第一个参数。CLI 默认安装到 $HOME/.local/bin/workfollowctl，WORKFOLLOW_CLI_BIN_DIR 可指定其他目录。使用安装输出中的 CLI 路径运行 status --json，确认 ok=true 和实际 storageDirectory；再运行 --help 并完成一次只读查询。根据助手的技能加载方式刷新技能或新建对话，确认 workfollow-cli 已可使用。
        4. 后续按 Skill 中的日期、版本和保存规则执行用户指令。当前原生 App 的数据通过这个 CLI 操作；名为 workfollow 的旧 MCP 连接的是另一套数据。

        完成后告诉我接入结果。我希望接着可以直接说：“把这段讨论保存成笔记，再建一个明天下午三点跟进的高优先级待办。”
        """
    }

}
