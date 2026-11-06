#!/usr/bin/env python3
"""Prepare portable runtimes, then embed the AI-only backend in WorkFollow.app.

Downloads happen on the build machine, never on an end user's first launch.
Only Python and the AI adapter ship with the App. Node and Pi are local installations.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

REPO = Path(__file__).resolve().parents[2]
CACHE = REPO / ".runtime-cache" / "ai-backend-v1"
PYTHON_VERSION = "3.12.16"
PYTHON_RELEASE = "20261026"
ARCHES = ("arm64",)
SOURCE_FILES = ("ai_entry.py", "app/__init__.py", "app/ai_runtime", "app/schemas/__init__.py",
                "app/schemas/base.py", "app/schemas/ai.py", "app/services/__init__.py",
                "app/services/ai_service.py")


def run(command, **kwargs):
    subprocess.run([str(item) for item in command], check=True, **kwargs)


def download(url, destination):
    if destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".partial")
    try:
        with urllib.request.urlopen(url, timeout=60) as source, partial.open("wb") as target:
            shutil.copyfileobj(source, target)
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)


def prepare_python(cache, arch):
    target = cache / "runtime" / arch / "python"
    marker = target / ".workfollow-ready"
    requirements = (REPO / "backend/requirements-ai-runtime.txt").read_text()
    expected = json.dumps({"python": PYTHON_VERSION, "requirements": requirements}, sort_keys=True)
    previous = marker.read_text() if marker.exists() else ""
    if previous == expected:
        return
    try:
        python_version = json.loads(previous).get("python")
    except ValueError:
        python_version = previous
    python_ready = python_version == PYTHON_VERSION and (target / "bin/python3").exists()
    cpu = "aarch64"
    name = f"cpython-{PYTHON_VERSION}+{PYTHON_RELEASE}-{cpu}-apple-darwin-install_only_stripped.tar.gz"
    archive = cache / "downloads" / name
    if not python_ready:
        download(f"https://github.com/astral-sh/python-build-standalone/releases/download/{PYTHON_RELEASE}/{name}", archive)
        with tempfile.TemporaryDirectory(dir=cache) as folder:
            with tarfile.open(archive) as stream:
                stream.extractall(folder)
            if target.exists():
                shutil.rmtree(target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(Path(folder) / "python"), target)
    site = target / "lib/python3.12/site-packages"
    marker.unlink(missing_ok=True)
    shutil.rmtree(site, ignore_errors=True)
    platforms = ["macosx_11_0_arm64", "macosx_10_9_universal2"]
    command = [sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "--no-compile", "--upgrade",
               "--target", str(site), "--implementation", "cp", "--python-version", "3.12", "--abi", "cp312", "--only-binary=:all:"]
    for value in platforms:
        command += ["--platform", value]
    command += ["-r", str(REPO / "backend/requirements-ai-runtime.txt")]
    run(command)
    # Keep licenses and the standard library. Build tools and Python's own test
    # suites are not needed for the app-owned service.
    for path in (target / "include", target / "share", target / "lib/python3.12/test",
                 target / "lib/python3.12/idlelib", target / "lib/python3.12/tkinter",
                 target / "lib/python3.12/ensurepip", target / "lib/python3.12/site-packages/pip"):
        if path.is_dir():
            shutil.rmtree(path)
    for path in target.rglob("__pycache__"):
        shutil.rmtree(path)
    shutil.rmtree(site / "bin", ignore_errors=True)
    for path in (target / "bin").iterdir():
        if path.name not in ("python", "python3", "python3.12"):
            path.unlink()
    for path in (target / "lib").rglob("*.a"):
        path.unlink()
    marker.write_text(expected)


def prepare(cache=CACHE):
    cache.mkdir(parents=True, exist_ok=True)
    for arch in ARCHES:
        print("准备 AI 运行环境：" + arch, flush=True)
        prepare_python(cache, arch)
    (cache / "runtime.json").write_text(json.dumps({"protocol": 1, "python": PYTHON_VERSION,
        "node": "external", "minimumNodeVersion": "22.19.0", "pi": "external", "architectures": list(ARCHES)}, indent=2))


def embedded_sources():
    """Every source file embed() copies into the app bundle."""
    backend = REPO / "backend"
    entries = []
    for name in SOURCE_FILES:
        path = backend / name
        if path.is_dir():
            entries += [item for item in sorted(path.rglob("*"))
                        if item.is_file() and "__pycache__" not in item.parts
                        and item.suffix != ".pyc"]
        elif path.is_file():
            entries.append(path)
    entries += sorted((REPO / "macos-native/WorkFollow/Resources").glob("wf-*.mjs"))
    skill = REPO / ".pi/skills/meeting-minutes/SKILL.md"
    if skill.is_file():
        entries.append(skill)
    return entries


def embedded_source_digest():
    digest = hashlib.sha256()
    for path in embedded_sources():
        digest.update(str(path.relative_to(REPO)).encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def ensure_backend_sources(app, log=None):
    """Re-embed when an incremental Xcode build left stale backend sources."""
    manifest_path = app / "Contents/Resources/AIBackend/runtime.json"
    if not manifest_path.exists():
        raise RuntimeError("AI 后端未打包，构建已停止。")
    expected = embedded_source_digest()
    if json.loads(manifest_path.read_text()).get("backendSourceDigest") == expected:
        return False
    print("AI 后端源码已变更，重新嵌入当前 backend/。", file=log, flush=True)
    embed(app)
    if json.loads(manifest_path.read_text()).get("backendSourceDigest") != expected:
        raise RuntimeError("AI 后端重新嵌入后源码仍不一致。")
    return True


def runtime_fingerprint(cache):
    """缓存运行时的内容指纹。只做 stat，成本远低于整棵 97M 拷贝。"""
    digest = hashlib.sha256()
    for relative in ("runtime.json", "runtime/arm64/python/.workfollow-ready"):
        path = cache / relative
        digest.update(relative.encode("utf-8"))
        digest.update(path.read_bytes() if path.is_file() else b"")
    runtime = cache / "runtime"
    for path in sorted(runtime.rglob("*")):
        relative = str(path.relative_to(cache)).encode("utf-8")
        if path.is_symlink():
            digest.update(relative)
            digest.update(str(path.readlink()).encode("utf-8"))
            continue
        if not path.is_file():
            continue
        stat = path.stat()
        digest.update(relative)
        digest.update(str(stat.st_size).encode("ascii"))
        digest.update(str(stat.st_mtime_ns).encode("ascii"))
    return digest.hexdigest()


def embed(app, cache=CACHE, if_ready=False):
    if not (cache / "runtime.json").exists():
        if if_ready:
            print("warning: AI 运行环境尚未准备；使用 local-app.py build 生成完整应用。")
            return
        raise RuntimeError("请先执行 bundle-ai-backend.py prepare")
    root = app / "Contents/Resources/AIBackend"
    root.mkdir(parents=True, exist_ok=True)
    # 旧版组件不应随增量构建残留，validate_layout 会拒绝它们。
    for stale in ("pi", "runtime/x86_64"):
        shutil.rmtree(root / stale, ignore_errors=True)
    fingerprint = runtime_fingerprint(cache)
    manifest_path = root / "runtime.json"
    previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    runtime_ready = (previous.get("runtimeFingerprint") == fingerprint
                     and all((root / "runtime" / arch / "python/bin/python3").is_file() for arch in ARCHES))
    if runtime_ready:
        print("AI 运行环境未变化，跳过 97M 运行时拷贝。", flush=True)
    else:
        shutil.rmtree(root / "runtime", ignore_errors=True)
        for arch in ARCHES:
            shutil.copytree(cache / "runtime" / arch / "python", root / "runtime" / arch / "python", symlinks=True)
        thin_native_files(root)
        # Older prepared caches can contain unused pip/console wrappers. They are
        # build tools, and their shebangs can refer to a build-machine environment.
        for arch in ARCHES:
            python = root / "runtime" / arch / "python"
            shutil.rmtree(python / "lib/python3.12/site-packages/bin", ignore_errors=True)
            for path in (python / "bin").iterdir():
                if path.name not in ("python", "python3", "python3.12"):
                    path.unlink()
    manifest = json.loads((cache / "runtime.json").read_text())
    manifest["architectures"] = list(ARCHES)
    manifest["node"] = "external"
    manifest["pi"] = "external"
    manifest["minimumNodeVersion"] = "22.19.0"
    manifest.pop("boundedText", None)
    manifest["textTransport"] = "pi-agent"
    manifest["runtimeFingerprint"] = fingerprint
    manifest["backendSourceDigest"] = embedded_source_digest()
    manifest_path.write_text(json.dumps(manifest, indent=2))
    # 源码和资源目录很小，每次全量同步，顺带清掉白名单里已移除的旧文件。
    shutil.rmtree(root / "backend", ignore_errors=True)
    for name in SOURCE_FILES:
        source, destination = REPO / "backend" / name, root / "backend" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            shutil.copytree(source, destination, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        else:
            shutil.copy2(source, destination)
    shutil.rmtree(root / "resources", ignore_errors=True)
    resources = root / "resources"
    resources.mkdir()
    for path in (REPO / "macos-native/WorkFollow/Resources").glob("wf-*.mjs"):
        shutil.copy2(path, resources / path.name)
    skill = REPO / ".pi/skills/meeting-minutes/SKILL.md"
    if skill.is_file():
        shutil.copy2(skill, resources / "SKILL.md")
    import plistlib
    plist = app / "Contents/Info.plist"
    if plist.exists():
        value = plistlib.loads(plist.read_bytes())
        value["WorkFollowAIBackendProtocol"] = 1
        value["WorkFollowAIModelConfiguration"] = 1
        value["WorkFollowAppleSiliconOnly"] = True
        value["WorkFollowExternalNode"] = True
        value["WorkFollowExternalPi"] = True
        plist.write_bytes(plistlib.dumps(value))


def validate_layout(app):
    root = app / "Contents/Resources/AIBackend"
    manifest = json.loads((root / "runtime.json").read_text()) if (root / "runtime.json").exists() else {}
    required = [root / "runtime.json", root / "backend/ai_entry.py",
                root / "resources/wf-meeting-stream.mjs", root / "resources/wf-meeting-audio.mjs"]
    if manifest.get("boundedText"):
        required.append(root / "resources/wf-text.mjs")
    if manifest.get("pi") != "external":
        required.append(root / "pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js")
    # Older installed packages remain eligible for backup and rollback.
    for arch in manifest.get("architectures", ARCHES):
        required.append(root / "runtime" / arch / "python/bin/python3")
        if manifest.get("node") != "external":
            required.append(root / "runtime" / arch / "node/bin/node")
    missing = [str(path.relative_to(root)) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError("AI 安装组件缺失：" + ", ".join(missing))
    if manifest.get("protocol") != 1:
        raise RuntimeError("AI 后端协议版本不符")
    if manifest.get("pi") == "external" and (root / "pi").exists():
        raise RuntimeError("使用本机 Pi 的安装包不应包含 Pi 安装目录")
    if manifest.get("node") == "external" and any((root / "runtime").glob("*/node")):
        raise RuntimeError("使用本机 Node 的安装包不应包含 Node 运行环境")


def thin_native_files(root):
    for path in native_files(root):
        architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(path)], text=True).split()
        if "arm64" not in architectures:
            raise RuntimeError("AI 组件没有 Apple 芯片版本：" + str(path.relative_to(root)))
        if architectures != ["arm64"]:
            temporary = path.with_name(path.name + ".arm64-build")
            try:
                run(["/usr/bin/lipo", path, "-thin", "arm64", "-output", temporary])
                temporary.chmod(path.stat().st_mode & 0o777)
                temporary.replace(path)
            finally:
                temporary.unlink(missing_ok=True)


def validate_arm64_only(app):
    root = app / "Contents/Resources/AIBackend"
    manifest = json.loads((root / "runtime.json").read_text())
    if manifest.get("architectures") != ["arm64"] or (root / "runtime/x86_64").exists():
        raise RuntimeError("Apple 芯片安装包仍包含 Intel 运行环境")
    for path in native_files(app):
        architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(path)], text=True).split()
        if architectures != ["arm64"]:
            raise RuntimeError("安装组件不是纯 arm64：" + str(path.relative_to(app)))


def validate_native_dependencies(app):
    root = app / "Contents/Resources/AIBackend"
    for path in native_files(root):
        result = subprocess.run(["/usr/bin/otool", "-L", str(path)], capture_output=True, text=True, check=True)
        for line in result.stdout.splitlines()[1:]:
            if not line.startswith("\t"):
                continue
            dependency = line.strip().split(" (", 1)[0]
            if dependency.startswith("/") and not dependency.startswith(("/usr/lib/", "/System/Library/")):
                raise RuntimeError("AI 组件依赖构建机路径：" + str(path.relative_to(root)))
        commands = subprocess.run(["/usr/bin/otool", "-l", str(path)], capture_output=True, text=True, check=True)
        rpath = False
        for line in commands.stdout.splitlines():
            value = line.strip()
            if value.startswith("cmd "):
                rpath = value == "cmd LC_RPATH"
            elif rpath and value.startswith("path "):
                location = value.removeprefix("path ").split(" (offset", 1)[0]
                if location.startswith("/") and not location.startswith(("/usr/lib/", "/System/Library/")):
                    raise RuntimeError("AI 组件包含构建机的动态库搜索路径：" + str(path.relative_to(root)))


def native_files(root):
    signatures = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca")
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                if stream.read(4) in signatures:
                    yield path


def sign(app, identity, log=None):
    validate_layout(app)
    validate_arm64_only(app)
    validate_native_dependencies(app)
    root = app / "Contents/Resources/AIBackend"
    # Sign nested libraries before executables and before sealing the outer App.
    files = sorted(native_files(root), key=lambda path: path.suffix not in (".so", ".dylib", ".node"))
    for path in files:
        command = ["/usr/bin/codesign", "--force", "--sign", identity]
        if identity != "-":
            command += ["--options", "runtime"]
        run(command + [path], stdout=log, stderr=subprocess.STDOUT if log else None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "embed", "sign"))
    parser.add_argument("--app", type=Path)
    parser.add_argument("--cache", type=Path, default=CACHE)
    parser.add_argument("--if-ready", action="store_true")
    parser.add_argument("--identity", default="-")
    args = parser.parse_args()
    if args.command == "prepare":
        prepare(args.cache)
    elif args.command == "embed":
        embed(args.app, args.cache, args.if_ready)
    else:
        sign(args.app, args.identity)


if __name__ == "__main__":
    main()
