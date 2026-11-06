#!/usr/bin/env python3
"""Build the offline editor and package only its runtime assets."""
import argparse
import io
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "WorkFollow/Resources/milkdown-web"
OUTPUT = ROOT / "WorkFollow/Resources/MilkdownRuntime.zip"


def build(app=None):
    node = shutil.which("node") or next((str(p) for p in [Path("/opt/homebrew/bin/node"), Path("/usr/local/bin/node")] if p.exists()), None)
    if not node:
        raise RuntimeError("构建 Milkdown 编辑器需要本机 Node。")
    if not (WEB / "node_modules/@milkdown/core/package.json").is_file():
        npm = shutil.which("npm") or str(Path(node).parent / "npm")
        environment = dict(os.environ, PATH=str(Path(node).parent) + os.pathsep + os.environ.get("PATH", ""))
        subprocess.run([npm, "ci", "--no-audit", "--no-fund", "--ignore-scripts", "--cache", str(WEB / ".npm-cache")],
                       cwd=WEB, env=environment, check=True)
    subprocess.run([node, str(WEB / "build.mjs")], cwd=WEB, check=True)
    files = [WEB / "dist/index.html", WEB / "dist/milkdown.js", WEB / "dist/milkdown.css", WEB / "dist/THIRD_PARTY_NOTICES.txt"]
    files.extend(sorted((WEB / "dist/fonts").glob("*")))
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file in files:
            info = zipfile.ZipInfo(str(file.relative_to(WEB / "dist")), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED; info.external_attr = 0o644 << 16
            archive.writestr(info, file.read_bytes())
    data = buffer.getvalue()
    if not OUTPUT.exists() or OUTPUT.read_bytes() != data:
        OUTPUT.write_bytes(data)
    if app:
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        shutil.copy2(OUTPUT, resources / OUTPUT.name)
    print("Milkdown 离线资源已打包。")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    build(parser.parse_args().app)
