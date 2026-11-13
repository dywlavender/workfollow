#!/usr/bin/env python3
"""Build and update the local daily app; task data is never modified here."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time


BUNDLE_ID = "com.workfollow.native.preview"
PROJECT = Path(__file__).resolve().parents[1] / "WorkFollow.xcodeproj"
DESTINATION = Path("/Applications/WorkFollow.app")
UPDATES = Path.home() / "Library/Application Support/WorkFollowNativeUpdates"
LOG = Path.home() / "Library/Logs/WorkFollowNativeUpdates/build.log"
AI_BUNDLE_SCRIPT = Path(__file__).with_name("bundle-ai-backend.py")
TMP_ROOT = Path("/private/tmp")
TMP_OUTPUT = TMP_ROOT / "workfollow-local-build"
# 固定 DerivedData：Swift 未变时让 Xcode 走增量编译。名字不能以 "-build" 结尾，
# 否则会被 clean_stale_builds 当成过期构建目录清掉。
DERIVED_DATA = TMP_ROOT / "workfollow-release-derived"


class AppError(Exception):
    pass


def info(app):
    try:
        with (app / "Contents/Info.plist").open("rb") as stream:
            return plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        raise AppError(f"无法读取应用信息：{app}") from error


def run_logged(command, log):
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise AppError(f"构建或签名失败，请查看日志：{LOG}")


def configure_local_widgets(package, folder):
    """Select the extension's own container for local ad-hoc packages."""
    widget = package / "Contents/PlugIns/WorkFollowWidgets.appex"
    for bundle in [package, widget]:
        value = info(bundle)
        value["WorkFollowWidgetTransport"] = "widgetContainer"
        with (bundle / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(value, stream)
    host_entitlements = folder / "local-host.entitlements"
    widget_entitlements = folder / "local-widget.entitlements"
    host_entitlements.write_bytes(plistlib.dumps({}))
    widget_entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    return host_entitlements, widget_entitlements


def validate(app):
    value = info(app)
    if value.get("CFBundleIdentifier") != BUNDLE_ID:
        raise AppError("应用标识不符，不能作为日用版安装。")
    # Older daily packages carried an empty storage-root placeholder. It does
    # not redirect data and must remain eligible for rollback.
    if any(key.startswith("WorkFollowAcceptance") and item != "" for key, item in value.items()):
        raise AppError("应用带有验收配置，请使用 build 命令生成日用版。")
    executable = value.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or not os.access(
        app / "Contents/MacOS" / executable, os.X_OK
    ):
        raise AppError("应用可执行文件不存在。")
    if value.get("WorkFollowAIBackendProtocol"):
        spec = importlib.util.spec_from_file_location("ai_bundle", AI_BUNDLE_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        try:
            module.validate_layout(app)
            if value.get("WorkFollowAppleSiliconOnly"):
                module.validate_arm64_only(app)
        except (OSError, ValueError, RuntimeError) as error:
            raise AppError(str(error)) from error
    plugins = app / "Contents/PlugIns"
    if plugins.exists():
        for plugin in plugins.iterdir():
            if plugin.name != "WorkFollowWidgets.appex":
                raise AppError("日用版不能包含测试插件或未知扩展。")
            extension = info(plugin)
            if (extension.get("CFBundleIdentifier") != BUNDLE_ID + ".widgets"
                    or extension.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension"):
                raise AppError("桌面小组件扩展标识不符。")
            if extension.get("WorkFollowWidgetTransport", "appGroup") != value.get("WorkFollowWidgetTransport", "appGroup"):
                raise AppError("应用与桌面小组件的数据通道不一致。")
    result = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                            capture_output=True)
    if result.returncode:
        raise AppError("应用签名验证失败，请重新构建。")
    return value


def require_quit(app):
    if not app.exists():
        return
    executable = app / "Contents/MacOS" / info(app).get("CFBundleExecutable", "WorkFollow")
    processes = subprocess.run(["/bin/ps", "-axo", "comm="], capture_output=True, text=True, check=True)
    if str(executable) in {line.strip() for line in processes.stdout.splitlines()}:
        raise AppError("请先在 WorkFollow 菜单中退出应用，等待保存完成，再更新或回退。")


def widget_processes(app):
    widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
    if not widget.exists():
        return []
    value = info(widget)
    if value.get("CFBundleIdentifier") != BUNDLE_ID + ".widgets":
        raise AppError("已安装的桌面小组件标识不符。")
    executable = value.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise AppError("已安装的桌面小组件可执行文件无效。")
    expected = str(widget / "Contents/MacOS" / executable)
    processes = subprocess.run(["/bin/ps", "-axo", "pid=,comm="],
                               capture_output=True, text=True, check=True)
    rows = (line.strip().split(None, 1) for line in processes.stdout.splitlines())
    return [int(row[0]) for row in rows if len(row) == 2 and row[1] == expected]


def refresh_installed_widget(app, previous_processes):
    # Replace the package first, then end its previous stateless extension.
    # A system relaunch now loads the installed package rather than the old one.
    for pid in previous_processes:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
    if widget.exists():
        result = subprocess.run(["/usr/bin/pluginkit", "-a", str(widget)],
                                capture_output=True, text=True)
        if result.returncode:
            raise AppError("应用已更新，但桌面小组件登记失败，请重新运行安装命令。")


def install(source, destination, backup_dir):
    validate(source)
    require_quit(destination)
    previous_widget_processes = widget_processes(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    backup_dir.mkdir(parents=True, exist_ok=True)
    previous = backup_dir / "WorkFollow.app"
    # Copy and verify before touching the installed app. Staging shares its volume.
    with tempfile.TemporaryDirectory(prefix=".workfollow-update-", dir=destination.parent) as stage:
        staged = Path(stage) / "WorkFollow.app"
        shutil.copytree(source, staged, symlinks=True)
        validate(staged)
        if destination.exists():
            with tempfile.TemporaryDirectory(prefix=".previous-", dir=backup_dir) as saved:
                copy = Path(saved) / "WorkFollow.app"
                shutil.copytree(destination, copy, symlinks=True)
                if previous.exists():
                    shutil.rmtree(previous)
                copy.rename(previous)
        displaced = Path(stage) / "replaced.app"
        if destination.exists():
            destination.rename(displaced)
        try:
            staged.rename(destination)
        except OSError:
            if displaced.exists():
                displaced.rename(destination)
            raise
    refresh_installed_widget(destination, previous_widget_processes)
    return destination


def next_build(destination):
    if destination.exists():
        current = info(destination).get("CFBundleVersion", "0")
        if str(current).isdigit():
            return str(int(current) + 1)
    return "2"


def clean_stale_builds(keep=None, max_age_seconds=6 * 3600):
    """Remove build folders that interrupted runs left behind in the temp directory."""
    cutoff = time.time() - max_age_seconds
    protected = {TMP_OUTPUT, keep.expanduser().absolute() if keep else None}
    for path in TMP_ROOT.iterdir():
        if not path.is_dir() or not path.name.endswith("-build"):
            continue
        if not path.name.startswith(("wf-", "workfollow-")):
            continue
        if any(item and item.is_relative_to(path) for item in protected):
            continue
        try:
            if path.stat().st_mtime <= cutoff:
                shutil.rmtree(path, ignore_errors=True)
        except OSError:
            continue


def archive_derived_data():
    """强制全量重编译时把固定缓存改名归档；不删除，避免触发批量删除保护。"""
    if not DERIVED_DATA.exists():
        return None
    archive = DERIVED_DATA.with_name(f"{DERIVED_DATA.name}-clean-{time.strftime('%Y%m%d%H%M%S')}")
    DERIVED_DATA.rename(archive)
    return archive


def build(output, build_number, identity):
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise AppError("构建号必须是正整数。")
    if output.suffix != ".app":
        raise AppError("构建输出必须是 .app 路径。")
    if output.exists():
        require_quit(output)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="workfollow-release-") as folder, LOG.open("w") as log:
        run_logged([sys.executable, str(AI_BUNDLE_SCRIPT), "prepare"], log)
        derived = DERIVED_DATA
        derived.mkdir(parents=True, exist_ok=True)
        command = ["/usr/bin/xcodebuild", "-project", str(PROJECT), "-scheme", "WorkFollow",
                   "-configuration", "Release", "-destination", "platform=macOS",
                   "-derivedDataPath", str(derived), f"CODE_SIGNING_ALLOWED={'NO' if identity == '-' else 'YES'}",
                   "ENABLE_DEBUG_DYLIB=NO", f"CURRENT_PROJECT_VERSION={build_number}",
                   "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES",
                   "WF_ACCEPTANCE_STORAGE_ROOT="]
        if identity != "-":
            # Xcode uses the configured team and profiles to authorize App Groups.
            command.append("CODE_SIGN_IDENTITY=" + identity)
        if os.environ.get("WORKFOLLOW_DISABLE_SWIFT_SANDBOX"):
            command.append("OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox")
        command.append("build")
        run_logged(command, log)
        package = derived / "Build/Products/Release/WorkFollow.app"
        # Xcode's resource phase embeds the current sources and prepared runtimes.
        # Sign every nested native library before sealing the containing App.
        spec = importlib.util.spec_from_file_location("ai_bundle", AI_BUNDLE_SCRIPT)
        ai_bundle = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ai_bundle)
        try:
            ai_bundle.ensure_backend_sources(package, log)
        except (OSError, ValueError, RuntimeError) as error:
            raise AppError(str(error)) from error
        ai_bundle.sign(package, identity, log)
        plist = package / "Contents/Info.plist"
        value = info(package)
        # 增量构建可能不重处理 Info.plist，显式写回本次构建号。
        value["CFBundleVersion"] = build_number
        value["WorkFollowAIBackendProtocol"] = 1
        value["WorkFollowAIModelConfiguration"] = 1
        value["WorkFollowAppleSiliconOnly"] = True
        value["WorkFollowExternalNode"] = True
        value["WorkFollowExternalPi"] = True
        for key in list(value):
            if key.startswith("WorkFollowAcceptance"):
                del value[key]
        with plist.open("wb") as stream:
            plistlib.dump(value, stream)
        # Local builds use the widget's own container without an App Group;
        # the extension remains sandboxed. Certificate builds retain App Groups.
        if identity == "-":
            widget = package / "Contents/PlugIns/WorkFollowWidgets.appex"
            host_entitlements, widget_entitlements = configure_local_widgets(package, Path(folder))
            # The embedded CLI must be signed before sealing the containing app.
            cli = package / "Contents/MacOS/workfollowctl"
            run_logged(["/usr/bin/codesign", "--force", "--sign", identity, str(cli)], log)
            run_logged(["/usr/bin/codesign", "--force", "--sign", identity,
                        "--entitlements", str(widget_entitlements), str(widget)], log)
            run_logged(["/usr/bin/codesign", "--force", "--sign", identity,
                        "--entitlements", str(host_entitlements), str(package)], log)
        else:
            # Only the containing Info.plist changed above. Keep the profile and
            # entitlements generated by Xcode, including both targets' group access.
            run_logged(["/usr/bin/codesign", "--force", "--sign", identity,
                        "--preserve-metadata=entitlements,requirements,flags", str(package)], log)
        validate(package)
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            shutil.rmtree(output)
        shutil.copytree(package, output, symlinks=True)
    clean_stale_builds(output.parent)
    return output


def status(app):
    value = info(app)
    print(f"应用：{app}")
    print(f"版本：{value.get('CFBundleShortVersionString', '?')} ({value.get('CFBundleVersion', '?')})")
    print(f"标识：{value.get('CFBundleIdentifier', '?')}")
    result = subprocess.run(["/usr/bin/codesign", "-dv", str(app)], capture_output=True, text=True)
    mode = "本机签名" if "Signature=adhoc" in result.stderr else "证书签名或未签名"
    print(f"签名：{mode}")


# ---------------------------------------------------------------------------
# 发布：local-app.py release
#
# 面向「另一台 Apple Silicon Mac」的应用内自更新通道：
#   dist/manifest.json + 全量包 + 热更包（与上一版发布做文件级 diff）。
# 客户端（设置 → 软件更新）把更新目录指向这里的同步副本，读 manifest、
# 校验 sha256 后由 workfollowctl apply-update 落位。
# ---------------------------------------------------------------------------


def file_manifest(app):
    """Contents/ 下每个文件的相对路径 + SHA-256。符号链接以链接目标串参与
    哈希——diff 只关心「变没变」，客户端 zip 整包校验，不需要还原链接。"""
    root = app / "Contents"
    entries = []
    for path in sorted(root.rglob("*")):
        if path.name == ".DS_Store" or not (path.is_symlink() or path.is_file()):
            continue
        rel = "Contents/" + path.relative_to(root).as_posix()
        if path.is_symlink():
            payload = "symlink:" + os.readlink(path)
            digest = hashlib.sha256(payload.encode()).hexdigest()
        else:
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest = digest.hexdigest()
        entries.append({"path": rel, "sha256": digest})
    return entries


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def zip_full(app, output):
    subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                    str(app), str(output)], check=True)


def zip_hot(staging, output):
    # 不带 --keepParent：zip 内以 Contents/… 开头，与热更清单一致。
    subprocess.run(["/usr/bin/ditto", "-c", "-k", str(staging), str(output)], check=True)


def newest_state(history):
    """上一版发布状态（用于 diff）。没有 → 首次发布，只出全量包。"""
    best = None
    for path in history.glob("state-*.json"):
        try:
            state = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        build = state.get("build")
        if isinstance(build, int) and (best is None or build > best["build"]):
            best = state
    return best


def publish_release(dist, app, notes):
    value = info(app)
    version = value.get("CFBundleShortVersionString", "0.0.0")
    build = int(value.get("CFBundleVersion", "0"))
    dist.mkdir(parents=True, exist_ok=True)
    history = dist / "history"
    history.mkdir(exist_ok=True)
    files = file_manifest(app)
    with tempfile.TemporaryDirectory(prefix="wf-release-") as folder:
        stage = Path(folder)
        # 全量包：ditto --keepParent，zip 根是 WorkFollow.app/
        full_name = f"WorkFollow-{version}-{build}-full.zip"
        zip_full(app, stage / full_name)
        full_sha = sha256_file(stage / full_name)
        full_bytes = (stage / full_name).stat().st_size
        shutil.copy2(stage / full_name, dist / full_name)

        # 热更包：与上一版发布的文件清单 diff，只带变化的文件。
        previous = newest_state(history)
        hot = None
        if previous:
            changed = [entry for entry in files
                       if previous.get("files", {}).get(entry["path"]) != entry["sha256"]]
            if changed:
                hot_stage = stage / "hot"
                for entry in changed:
                    source = app / entry["path"]
                    destination = hot_stage / entry["path"]
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    if source.is_symlink():
                        os.symlink(os.readlink(source), destination)
                    else:
                        shutil.copy2(source, destination, follow_symlinks=False)
                hot_name = f"WorkFollow-{version}-{build}-hot.zip"
                zip_hot(hot_stage, stage / hot_name)
                hot = {"file": hot_name,
                       "bytes": (stage / hot_name).stat().st_size,
                       "sha256": sha256_file(stage / hot_name),
                       "fromBuild": previous["build"], "files": changed}
                shutil.copy2(stage / hot_name, dist / hot_name)

        manifest = {
            "format": 1,
            "app": BUNDLE_ID,
            "version": version,
            "build": build,
            "notes": notes or "常规更新。",
            "releasedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "packages": {"full": {"file": full_name, "bytes": full_bytes, "sha256": full_sha},
                         "hot": hot},
        }
        (dist / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        (history / f"state-{version}-{build}.json").write_text(json.dumps(
            {"version": version, "build": build,
             "files": {entry["path"]: entry["sha256"] for entry in files}}), encoding="utf-8")
        prune_release(dist, history, current_build=build, keep=3)
    return manifest


def release(args, destination, backup):
    """发布流程：先像 update 一样给本机装上（狗粮），再产出 dist 发布目录。"""
    number = args.build_number or next_build(destination)
    if args.clean_build:
        archived = archive_derived_data()
        if archived:
            print(f"已归档构建缓存：{archived}")
    require_quit(destination)
    dist = args.dist_dir.expanduser().absolute()
    with tempfile.TemporaryDirectory(prefix="workfollow-daily-") as folder:
        package = build(Path(folder) / "WorkFollow.app", number, args.signing_identity)
        status(install(package, destination, backup))
    manifest = publish_release(dist, destination, args.notes)
    hot = manifest["packages"]["hot"]
    print(f"发布目录：{dist}")
    print(f"全量包：{manifest['packages']['full']['file']} "
          f"({manifest['packages']['full']['bytes'] // (1024 * 1024)}M)")
    if hot:
        print(f"热更包：{hot['file']}（{hot['bytes'] // (1024 * 1024)}M，"
              f"{len(hot['files'])} 个文件，基于 build {hot['fromBuild']}）")
    else:
        print("热更包：无（首次发布或内容无差异）")
    print(f"清单：{dist / 'manifest.json'}")


def prune_release(dist, history, current_build, keep=3):
    """history 只留最近 keep 版状态；zip 按 build 号裁剪，同步目录别越攒越大。"""
    states = []
    for path in history.glob("state-*.json"):
        try:
            states.append(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError):
            continue
    states.sort(key=lambda state: state.get("build", 0), reverse=True)
    for state in states[keep:]:
        (history / f"state-{state.get('version')}-{state.get('build')}.json").unlink()
    keep_builds = {state.get("build") for state in states[:keep]} | {current_build}
    for path in list(dist.glob("WorkFollow-*-full.zip")) + list(dist.glob("WorkFollow-*-hot.zip")):
        match = re.fullmatch(r"WorkFollow-.*-(\d+)-(full|hot)\.zip", path.name)
        if match and int(match.group(1)) not in keep_builds:
            path.unlink()


def release(args, destination, backup):
    """发布流程：先像 update 一样给本机装上（狗粮），再产出 dist 发布目录。"""
    number = args.build_number or next_build(destination)
    if args.clean_build:
        archived = archive_derived_data()
        if archived:
            print(f"已归档构建缓存：{archived}")
    require_quit(destination)
    dist = args.dist_dir.expanduser().absolute()
    with tempfile.TemporaryDirectory(prefix="workfollow-daily-") as folder:
        package = build(Path(folder) / "WorkFollow.app", number, args.signing_identity)
        status(install(package, destination, backup))
    manifest = publish_release(dist, destination, args.notes)
    hot = manifest["packages"]["hot"]
    print(f"发布目录：{dist}")
    print(f"全量包：{manifest['packages']['full']['file']} "
          f"({manifest['packages']['full']['bytes'] // (1024 * 1024)}M)")
    if hot:
        print(f"热更包：{hot['file']}（{hot['bytes'] // (1024 * 1024)}M，"
              f"{len(hot['files'])} 个文件，基于 build {hot['fromBuild']}）")
    else:
        print("热更包：无（首次发布或内容无差异）")
    print(f"清单：{dist / 'manifest.json'}")


def prune_release(dist, history, current_build, keep=3):
    """history 只留最近 keep 版状态；zip 按 build 号裁剪，同步目录别越攒越大。"""
    states = []
    for path in history.glob("state-*.json"):
        try:
            states.append(json.loads(path.read_text()))
        except (OSError, json.JSONDecodeError):
            continue
    states.sort(key=lambda state: state.get("build", 0), reverse=True)
    for state in states[keep:]:
        (history / f"state-{state.get('version')}-{state.get('build')}.json").unlink()
    keep_builds = {state.get("build") for state in states[:keep]} | {current_build}
    for path in list(dist.glob("WorkFollow-*-full.zip")) + list(dist.glob("WorkFollow-*-hot.zip")):
        match = re.fullmatch(r"WorkFollow-.*-(\d+)-(full|hot)\.zip", path.name)
        if match and int(match.group(1)) not in keep_builds:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "install", "update", "release", "rollback", "status"])
    parser.add_argument("source", nargs="?", type=Path, help="install 使用的 .app")
    parser.add_argument("--destination", type=Path, default=DESTINATION)
    parser.add_argument("--backup-dir", type=Path, default=UPDATES / "previous")
    parser.add_argument("--output", type=Path, default=Path("/private/tmp/workfollow-local-build/WorkFollow.app"))
    parser.add_argument("--build-number", help="默认使用已安装构建号加一")
    parser.add_argument("--signing-identity", default="-", help="本机可用的签名证书名称；默认本机签名")
    parser.add_argument("--clean-build", action="store_true",
                        help="把固定构建缓存改名归档，强制全量重编译（旧缓存保留，不删除）")
    parser.add_argument("--dist-dir", type=Path, default=PROJECT.parent / "dist",
                        help="发布目录（放进同步盘或手动拷到另一台电脑）")
    parser.add_argument("--notes", help="本次更新的说明，会出现在另一台电脑的更新提示里")
    args = parser.parse_args()
    destination = args.destination.expanduser().absolute()
    backup = args.backup_dir.expanduser().absolute()
    try:
        if args.command == "status":
            status(destination)
        elif args.command == "rollback":
            status(install(backup / "WorkFollow.app", destination, backup))
        elif args.command == "install":
            if args.source is None:
                parser.error("install 需要指定 .app 路径")
            status(install(args.source.expanduser().absolute(), destination, backup))
        elif args.command == "release":
            release(args, destination, backup)
        else:
            number = args.build_number or next_build(destination)
            if args.clean_build:
                archived = archive_derived_data()
                if archived:
                    print(f"已归档构建缓存：{archived}")
            if args.command == "update":
                require_quit(destination)
                with tempfile.TemporaryDirectory(prefix="workfollow-daily-") as folder:
                    package = build(Path(folder) / "WorkFollow.app", number, args.signing_identity)
                    status(install(package, destination, backup))
            else:
                output = args.output.expanduser().absolute()
                if output == destination:
                    raise AppError("请使用 update 更新日用应用，build 输出应放在其他目录。")
                status(build(output, number, args.signing_identity))
        return 0
    except (AppError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
