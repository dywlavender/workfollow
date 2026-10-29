"""Find a local Pi CLI, including installations made by the onboarding command."""
import os
from pathlib import Path
import shutil

from app.ai_runtime.node_runtime import node_candidates


class PiRuntimeError(RuntimeError):
    pass


def resolve_pi(override="", node=None):
    override = override.strip()
    if override and override not in ("/opt/homebrew/bin/pi", "/usr/local/bin/pi"):
        path = Path(override).expanduser() if "/" in override else Path(shutil.which(override) or override)
        candidates = [path]
    else:
        candidates = []
        inherited = shutil.which("pi")
        if inherited:
            candidates.append(Path(inherited))
        if node:
            candidates.append(node.parent / "pi")
        candidates += [Path.home() / ".local/bin/pi", Path("/opt/homebrew/bin/pi"), Path("/usr/local/bin/pi"),
                       Path.home() / ".npm-global/bin/pi", Path.home() / ".volta/bin/pi"]
        candidates += [path.parent / "pi" for path in node_candidates()]
    for candidate in dict.fromkeys(candidates):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.absolute()
    raise PiRuntimeError("未找到本机 Pi。请按「👋欢迎 → AI 配置说明」安装 Pi，再刷新模型列表；高级选项也可指定 Pi 程序路径。")
