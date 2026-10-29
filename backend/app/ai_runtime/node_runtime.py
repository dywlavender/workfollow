"""Locate a user-installed Node without relying on a terminal's login shell."""
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

MIN_NODE_VERSION = (22, 19, 0)
INSTALL_HELP = "请在「👋欢迎 → AI 配置说明」安装 Node.js 24 LTS，再刷新 Pi 模型。"


class NodeRuntimeError(RuntimeError):
    pass


@dataclass(frozen=True)
class NodeRuntime:
    executable: Path
    version: str


def node_candidates(environment: dict[str, str] | None = None, home: Path | None = None) -> list[Path]:
    environment = os.environ if environment is None else environment
    home = Path.home() if home is None else home
    override = environment.get("WORKFOLLOW_NODE_PATH", "").strip()
    if override:
        return [Path(override).expanduser()]
    paths = []
    if inherited := shutil.which("node", path=environment.get("PATH", "")):
        paths.append(Path(inherited))
    # Finder launches do not inherit Homebrew/nvm's terminal PATH.
    paths += [Path(value) for value in (
        "/opt/homebrew/bin/node", "/usr/local/bin/node",
        "/opt/homebrew/opt/node@24/bin/node", "/opt/homebrew/opt/node@22/bin/node",
        "/usr/local/opt/node@24/bin/node", "/usr/local/opt/node@22/bin/node",
    )]
    paths += [home / ".volta/bin/node", home / ".local/share/mise/shims/node"]
    for pattern in (".nvm/versions/node/*/bin/node", ".local/share/fnm/node-versions/*/installation/bin/node",
                    ".local/share/mise/installs/node/*/bin/node"):
        paths += sorted(home.glob(pattern), key=lambda path: tuple(int(part) for part in re.findall(r"\d+", str(path))), reverse=True)
    return list(dict.fromkeys(paths))


def resolve_node() -> NodeRuntime:
    details = []
    for candidate in node_candidates():
        if not candidate.is_file() or not os.access(candidate, os.X_OK):
            continue
        try:
            result = subprocess.run([str(candidate), "-p",
                "JSON.stringify({version:process.versions.node,arch:process.arch,executable:process.execPath})"],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, timeout=3, check=True)
            value = json.loads(result.stdout)
            version = tuple(int(part) for part in value["version"].split(".")[:3])
            if version < MIN_NODE_VERSION:
                details.append(f"本机 Node.js {value['version']} 版本过低，Pi 需要 22.19.0 或更新版本。")
                continue
            if value["arch"] != "arm64":
                details.append("Pi 需要 Apple 芯片（arm64）版 Node.js。")
                continue
            return NodeRuntime(Path(value["executable"]), value["version"])
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            continue
    reason = details[0] if details else "未找到可用的本机 Node.js。"
    raise NodeRuntimeError(reason + INSTALL_HELP)
