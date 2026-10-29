from pathlib import Path

import pytest

from app.ai_runtime import pi_runtime
from app.ai_runtime.pi_runtime import PiRuntimeError, resolve_pi


def test_finder_launch_finds_the_user_prefix_from_onboarding(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(pi_runtime.shutil, "which", lambda _: None)
    monkeypatch.setattr(pi_runtime, "node_candidates", lambda: [])
    pi = tmp_path / ".local/bin/pi"
    pi.parent.mkdir(parents=True)
    pi.write_text("#!/bin/sh\nexit 0\n"); pi.chmod(0o755)
    assert resolve_pi("/usr/local/bin/pi", tmp_path / "node/bin/node") == pi


def test_explicit_pi_location_is_used_without_changing_global_configuration(tmp_path):
    pi = tmp_path / "Local Pi/pi"
    pi.parent.mkdir(parents=True)
    pi.write_text("#!/bin/sh\nexit 0\n"); pi.chmod(0o755)
    assert resolve_pi(str(pi)) == pi
    with pytest.raises(PiRuntimeError, match="AI 配置说明"):
        resolve_pi(str(tmp_path / "missing/pi"))
