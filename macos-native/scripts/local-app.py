#!/usr/bin/env python3
"""Build and update the local daily app; task data is never modified here."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile


BUNDLE_ID = "com.workfollow.native.preview"
PROJECT = Path(__file__).resolve().parents[1] / "WorkFollow.xcodeproj"
DESTINATION = Path("/Applications/WorkFollow.app")
UPDATES = Path.home() / "Library/Application Support/WorkFollowNativeUpdates"
LOG = Path.home() / "Library/Logs/WorkFollowNativeUpdates/build.log"


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


def build(output, build_number, identity):
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise AppError("构建号必须是正整数。")
    if output.suffix != ".app":
        raise AppError("构建输出必须是 .app 路径。")
    if output.exists():
        require_quit(output)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="workfollow-release-") as folder, LOG.open("w") as log:
        derived = Path(folder) / "DerivedData"
        command = ["/usr/bin/xcodebuild", "-project", str(PROJECT), "-scheme", "WorkFollow",
                   "-configuration", "Release", "-destination", "platform=macOS",
                   "-derivedDataPath", str(derived), f"CODE_SIGNING_ALLOWED={'NO' if identity == '-' else 'YES'}",
                   "ENABLE_DEBUG_DYLIB=NO", f"CURRENT_PROJECT_VERSION={build_number}",
                   "WF_ACCEPTANCE_STORAGE_ROOT="]
        if identity != "-":
            # Xcode uses the configured team and profiles to authorize App Groups.
            command.append("CODE_SIGN_IDENTITY=" + identity)
        if os.environ.get("WORKFOLLOW_DISABLE_SWIFT_SANDBOX"):
            command.append("OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox")
        command.append("build")
        run_logged(command, log)
        package = derived / "Build/Products/Release/WorkFollow.app"
        plist = package / "Contents/Info.plist"
        value = info(package)
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
    return output


def status(app):
    value = info(app)
    print(f"应用：{app}")
    print(f"版本：{value.get('CFBundleShortVersionString', '?')} ({value.get('CFBundleVersion', '?')})")
    print(f"标识：{value.get('CFBundleIdentifier', '?')}")
    result = subprocess.run(["/usr/bin/codesign", "-dv", str(app)], capture_output=True, text=True)
    mode = "本机签名" if "Signature=adhoc" in result.stderr else "证书签名或未签名"
    print(f"签名：{mode}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "install", "update", "rollback", "status"])
    parser.add_argument("source", nargs="?", type=Path, help="install 使用的 .app")
    parser.add_argument("--destination", type=Path, default=DESTINATION)
    parser.add_argument("--backup-dir", type=Path, default=UPDATES / "previous")
    parser.add_argument("--output", type=Path, default=Path("/private/tmp/workfollow-local-build/WorkFollow.app"))
    parser.add_argument("--build-number", help="默认使用已安装构建号加一")
    parser.add_argument("--signing-identity", default="-", help="本机可用的签名证书名称；默认本机签名")
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
        else:
            number = args.build_number or next_build(destination)
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
