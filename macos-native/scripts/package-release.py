#!/usr/bin/env python3
"""Build the current workspace and create a ZIP for another Apple silicon Mac."""

import argparse
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT.parent / "安装包"
spec = importlib.util.spec_from_file_location("local_app", Path(__file__).with_name("local-app.py"))
local_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_app)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise local_app.AppError(f"{Path(command[0]).name} 执行失败：{result.stderr.strip()}")
    return result.stdout


def validate_apple_silicon(app):
    value = local_app.validate(app)
    binaries = [app / "Contents/MacOS" / value["CFBundleExecutable"]]
    cli = app / "Contents/MacOS/workfollowctl"
    if cli.exists():
        binaries.append(cli)
    widget = app / "Contents/PlugIns/WorkFollowWidgets.appex"
    if widget.exists():
        widget_info = local_app.info(widget)
        binaries.append(widget / "Contents/MacOS" / widget_info["CFBundleExecutable"])
    for binary in binaries:
        architectures = run(["/usr/bin/lipo", "-archs", str(binary)]).split()
        if not any(arch.startswith("arm64") for arch in architectures):
            raise local_app.AppError(f"{binary.name} 不包含 Apple 芯片版本。")
    return value


def readme(info):
    ai = ("AI 后端及 Python、Node、Pi 引擎随 App 安装，无需另外安装运行环境。\n"
          "模型与登录信息使用新 Mac 自己的 Pi 配置，安装包不包含模型密钥。"
          if info.get("WorkFollowAIBackendProtocol") == 1 else "AI 与会议转写使用新 Mac 已有的 Pi 和模型配置。")
    if info.get("WorkFollowAIModelConfiguration") == 1:
        ai = ("AI 后端及 Python、Node、Pi 引擎随 App 安装，无需另外安装运行环境。\n"
              "文字模型可在“设置 → AI 模型 → 直接调用”中配置协议、模型名称、API URL 和 API Key。\n"
              "语音转写继续使用新 Mac 自己的 Pi 模型与登录配置。安装包不包含个人模型密钥。")
    if info.get("WorkFollowExternalNode"):
        ai = ("AI 后端、Python 和 Pi 随 App 安装；Node 使用这台 Mac 的本机安装。\n"
              "文字模型：在“设置 → AI 模型 → 直接调用”选择协议并填写模型 ID、API URL 和 API Key，无需 Node。\n"
              "Pi 与会议转写：先安装 Apple 芯片版 Node.js 24 LTS（最低 22.19.0）。官方下载：https://nodejs.org/zh-cn/download\n"
              "已有 Homebrew 时可执行 brew install node@24。无需另外安装 Pi。\n"
              "欢迎清单的“AI 配置说明”提供安装命令、Pi 语音配置示例及设置入口。安装包不包含个人模型密钥。")
    if info.get("WorkFollowExternalPi"):
        ai = ("App 内置 Python 和 LangChain，Node 与 Pi 使用本机安装。\n"
              "文字直接调用：在“设置 → AI 模型”填写模型 ID、URL 和 Key，支持 OpenAI 兼容和 OpenAI Responses，无需 Node/Pi。\n"
              "Pi：按欢迎清单“AI 配置说明”安装 Node.js 24 LTS 和 Pi，编辑本机 ~/.pi/agent/models.json，再到设置刷新并选择文字、语音模型。\n"
              "新手引导提供安装命令、配置示例及“打开 Pi 配置”入口。安装包不包含个人模型密钥。")
    return f"""WorkFollow {info['CFBundleShortVersionString']}（{info['CFBundleVersion']}）

安装
1. 解压 ZIP，将 WorkFollow.app 拖到“应用程序”文件夹。
2. 更新已有安装时，先正常退出旧版，再选择替换。
3. 从“应用程序”打开 WorkFollow。

适用于 Apple 芯片 Mac，macOS {info.get('LSMinimumSystemVersion', '14.0')} 或更新版本。
若系统提示无法验证开发者，请在“系统设置 → 隐私与安全性”中手动允许打开。

安装包只包含程序，不包含个人任务、笔记或模型密钥。
迁移已有内容时，请在原 Mac 的应用设置中导出备份，再到新 Mac 恢复。
日历、提醒事项、通知和麦克风等权限需在新 Mac 上按需授权。
{ai}
"""


def verify_archive(archive, destination, folder_name):
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None:
            raise local_app.AppError("ZIP 完整性检查失败。")
    run(["/usr/bin/ditto", "-x", "-k", str(archive), str(destination)])
    return validate_apple_silicon(destination / folder_name / "WorkFollow.app")


def package(output_dir=DEFAULT_OUTPUT, source=None, build_number=None):
    output_dir = Path(output_dir).expanduser().absolute()
    output_dir.mkdir(parents=True, exist_ok=True)
    # The final rename stays on the output volume; failed work leaves no partial ZIP.
    with tempfile.TemporaryDirectory(prefix=".workfollow-package-", dir=output_dir) as temporary:
        work = Path(temporary)
        if source is None:
            number = build_number or local_app.next_build(local_app.DESTINATION)
            source = local_app.build(work / "built/WorkFollow.app", number, "-")
        else:
            source = Path(source).expanduser().absolute()
        validate_apple_silicon(source)
        staging = work / "staging"
        staging.mkdir()
        copied = staging / "WorkFollow.app"
        run(["/usr/bin/ditto", "--rsrc", "--extattr", str(source), str(copied)])
        info = validate_apple_silicon(copied)
        name = f"WorkFollow-{info['CFBundleShortVersionString']}-{info['CFBundleVersion']}-Mac"
        payload = work / name
        staging.rename(payload)
        (payload / "安装说明.txt").write_text(readme(info), encoding="utf-8")
        archive = work / (name + ".zip")
        run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(archive)])
        unpacked = verify_archive(archive, work / "unpacked", name)
        if unpacked != info:
            raise local_app.AppError("ZIP 解压后的应用信息不一致。")
        output = output_dir / archive.name
        archive.replace(output)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="打包指定 .app，跳过源码构建")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT, help="ZIP 输出目录，默认项目旁的“安装包”")
    parser.add_argument("--build-number", help="源码构建使用的构建号，默认沿用日用构建脚本的递增规则")
    args = parser.parse_args()
    if args.app and args.build_number:
        parser.error("--app 与 --build-number 不能同时使用")
    try:
        output = package(args.output_dir, source=args.app, build_number=args.build_number)
        print(f"安装包：{output}")
        print(f"大小：{output.stat().st_size / 1024 / 1024:.1f} MB")
        print("已验证解压后的 Apple 芯片程序与签名。")
        return 0
    except (local_app.AppError, OSError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
