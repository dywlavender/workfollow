import json
from pathlib import Path

import pytest

from app.ai_runtime import node_runtime
from app.ai_runtime.pi_engine import EngineError, PiEngine


def fake_node(folder, version, arch="arm64"):
    executable = folder / "node"
    executable.parent.mkdir(parents=True, exist_ok=True)
    value = {"version": version, "arch": arch, "executable": str(executable)}
    executable.write_text("#!/usr/bin/python3\nprint(" + repr(json.dumps(value)) + ")\n")
    executable.chmod(0o755)
    return executable


def test_finder_launch_discovers_homebrew_and_nvm_without_a_login_shell(tmp_path):
    newer = fake_node(tmp_path / ".nvm/versions/node/v24.22.1/bin", "24.22.1")
    older = fake_node(tmp_path / ".nvm/versions/node/v22.23.4/bin", "22.23.4")
    paths = node_runtime.node_candidates({"PATH": "/usr/bin:/bin"}, tmp_path)
    assert Path("/opt/homebrew/opt/node@24/bin/node") in paths
    assert Path("/usr/local/bin/node") in paths
    assert paths.index(newer) < paths.index(older)


def test_uses_compatible_install_when_terminal_path_contains_an_older_node(tmp_path, monkeypatch):
    old = fake_node(tmp_path / "old", "20.20.2")
    current = fake_node(tmp_path / "current", "22.19.0")
    monkeypatch.setattr(node_runtime, "node_candidates", lambda: [old, current])
    result = node_runtime.resolve_node()
    assert result.executable == current
    assert result.version == "22.19.0"


def test_missing_node_reports_install_instructions_instead_of_reinstalling_the_app(tmp_path, monkeypatch):
    monkeypatch.setattr(node_runtime, "node_candidates", lambda: [])
    with pytest.raises(EngineError) as error:
        PiEngine(tmp_path).command({})
    assert error.value.code == "node_unavailable"
    assert "AI 配置说明" in str(error.value)
    assert "重新安装应用" not in str(error.value)


def test_old_or_non_native_node_has_an_actionable_upgrade_message(tmp_path, monkeypatch):
    old = fake_node(tmp_path / "old", "22.18.0")
    monkeypatch.setattr(node_runtime, "node_candidates", lambda: [old])
    with pytest.raises(node_runtime.NodeRuntimeError, match="22.19.0"):
        node_runtime.resolve_node()
    wrong_arch = fake_node(tmp_path / "other", "24.22.1", "x64")
    monkeypatch.setattr(node_runtime, "node_candidates", lambda: [wrong_arch])
    with pytest.raises(node_runtime.NodeRuntimeError, match="arm64"):
        node_runtime.resolve_node()
