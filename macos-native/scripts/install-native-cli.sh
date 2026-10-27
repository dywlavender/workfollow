#!/usr/bin/env bash
set -euo pipefail
APP_PATH="${1:-/Applications/WorkFollow.app}"
CLI_BIN_DIR="${WORKFOLLOW_CLI_BIN_DIR:-$HOME/.local/bin}"
CLI_SKILL_DIR="${WORKFOLLOW_CLI_SKILL_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
if [[ ! -x "$APP_PATH/Contents/MacOS/workfollowctl" || ! -f "$APP_PATH/Contents/Resources/Skills/workfollow-cli/SKILL.md" ]]; then
  echo "请传入包含 workfollowctl 的新版 WorkFollow.app 路径。" >&2
  exit 1
fi
APP_PATH="$(cd "$APP_PATH" && pwd -P)"
for entry in "$CLI_BIN_DIR/workfollowctl" "$CLI_SKILL_DIR/workfollow-cli"; do
  if [[ -e "$entry" && ! -L "$entry" ]]; then
    echo "保留已有文件：$entry。请先选择其他安装目录。" >&2
    exit 1
  fi
done
mkdir -p "$CLI_BIN_DIR" "$CLI_SKILL_DIR"
ln -sfn "$APP_PATH/Contents/MacOS/workfollowctl" "$CLI_BIN_DIR/workfollowctl"
ln -sfn "$APP_PATH/Contents/Resources/Skills/workfollow-cli" "$CLI_SKILL_DIR/workfollow-cli"
echo "CLI 已安装：$CLI_BIN_DIR/workfollowctl"
echo "Skill 已安装：$CLI_SKILL_DIR/workfollow-cli"
echo '可在 AI 助手中刷新技能或新建对话，再使用 workfollow-cli。'
echo '若终端尚未包含 CLI 目录，可将它加入 PATH；Skill 也能使用完整路径。'
