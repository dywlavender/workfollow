#!/bin/bash
# 从当前源码一条命令生成可分发的 macOS 版「打勾」。
#
#   bash tool/build_macos_app.sh                清缓存 → 构建 → 重签 → 打包
#   bash tool/build_macos_app.sh --skip-build   跳过构建，只重签打包 build/ 里现有产物
#   bash tool/build_macos_app.sh --run          完了杀掉旧实例并启动新包
#
# 三条规矩都是踩出来的：
#   1. 构建与打包必须连着做完。打包脚本只是 ditto「那一刻 build/ 里的东西」，
#      而 build/ 是多会话共用的；中间被别的会话插一次 flutter build，dist 里就是别人的包，
#      且三方哈希照样一致（都出自同一次构建），查不出来。
#   2. 重签 App.framework 前必须先 --remove-signature。Xcode 26.6 的 codesign 直接
#      --force 会把临时文件 App.cstemp 写进封装清单，临时文件一消失 verify 必挂。
#   3. 校验哈希要写 Versions/A/App。unzip -p 不跟随软链接，写 App.framework/App
#      只会吐出 20 字节的链接目标。
set -euo pipefail

log="/private/tmp/wf_build_macos.log"
app_name="${APP_NAME:-打勾}"
skip_build=0
do_run=0
do_zip=1

usage() {
  cat <<'EOS'
用法：bash tool/build_macos_app.sh [选项]

  （无选项）     清缓存 → flutter build macos --release → 重签 → 打包 dist/
  --skip-build   跳过构建，只对 build/ 里现有产物做重签与打包
  --no-zip       只出 dist/打勾.app，不生成 zip
  --run          打包完杀掉旧实例并启动新包
  -h, --help     看这段说明

产物：
  dist/打勾.app          可直接运行
  dist/打勾-macOS.zip    分发用
  dist/BUILD-INFO.txt    这包出自哪份源码（git sha + lib/macos 内容指纹 + 二进制哈希）

环境变量：
  APP_NAME=<名字>        改产物名，默认「打勾」
  FLUTTER_BIN=<sdk>/bin  flutter 不在 PATH 时指定 SDK 的 bin 目录
EOS
}

for arg in "$@"; do
  case "$arg" in
    --skip-build) skip_build=1 ;;
    --no-zip)     do_zip=0 ;;
    --run)        do_run=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "未知参数：$arg" >&2; usage >&2; exit 2 ;;
  esac
done

desktop_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$desktop_dir"

step() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }

## ---- 环境：本机代理会拖死 flutter，SDK 也不在默认 PATH 里 ----
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy
if ! command -v flutter >/dev/null 2>&1; then
  export PATH="${FLUTTER_BIN:-/Users/dongyangwei/development/flutter/bin}:$PATH"
fi
command -v flutter >/dev/null 2>&1 || {
  echo "找不到 flutter。用 FLUTTER_BIN 指定 SDK 的 bin 目录后重试。" >&2
  exit 1
}

## ---- 产物路径：xcconfig 是 PRODUCT_NAME 的唯一来源，改 app 名这里会自动跟上 ----
product="$(awk -F'= *' '/^PRODUCT_NAME/{print $2; exit}' macos/Runner/Configs/AppInfo.xcconfig 2>/dev/null | tr -d '[:space:]' || true)"
product="${product:-workfollow_personal}"
build_app="build/macos/Build/Products/Release/$product.app"
binary="$build_app/Contents/Frameworks/App.framework/Versions/A/App"

## ---- 构建 ----
if [[ $skip_build -eq 0 ]]; then
  step "构建 release（完整日志：$log）"
  rm -rf build/native_assets
  flutter config --enable-swift-package-manager >/dev/null
  if ! flutter build macos --release 2>&1 | tee "$log" | tail -25; then
    echo "构建失败，完整日志在 $log" >&2
    exit 1
  fi
else
  step "跳过构建（--skip-build）"
fi
[[ -f "$binary" ]] || { echo "没找到构建产物：$binary" >&2; exit 1; }

## 产物之后源码又动过 = 这个包不是最新代码，通常意味着有别的会话也在改
if [[ $skip_build -eq 0 ]]; then
  stale="$(find lib macos -type f ! -path '*/ephemeral/*' ! -path '*/build/*' \
             -newer "$binary" -print -quit 2>/dev/null || true)"
  if [[ -n "$stale" ]]; then
    printf '\033[33m注意：构建完成后 %s 又被改过，这个包可能不是最新源码。\033[0m\n' "$stale"
  fi
fi

## ---- 重签（必须从里往外，且先剥后签）----
step "重签"
codesign --remove-signature "$build_app/Contents/Frameworks/App.framework"
codesign --force --sign - --timestamp=none "$build_app/Contents/Frameworks/App.framework"
codesign --force --sign - --timestamp=none \
  --entitlements macos/Runner/Release.entitlements "$build_app"
codesign --verify --deep --strict "$build_app"
echo "  签名校验通过"

## ---- 打包 ----
step "打包到 dist/"
mkdir -p dist
staging="$(mktemp -d "$desktop_dir/build/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$build_app" "$staging/$app_name.app"
codesign --verify --deep --strict "$staging/$app_name.app"
if [[ $do_zip -eq 1 ]]; then
  rm -f "dist/$app_name-macOS.zip"
  ditto -c -k --sequesterRsrc --keepParent \
    "$staging/$app_name.app" "dist/$app_name-macOS.zip"
fi
# 先把旧包挪进 staging（随后被 trap 清掉），避免中途失败时 dist 里空着
if [[ -e "dist/$app_name.app" ]]; then
  mv "dist/$app_name.app" "$staging/previous.app"
fi
mv "$staging/$app_name.app" "dist/$app_name.app"

## ---- 校验：构建树 / dist / zip 三方必须同一个二进制 ----
step "校验"
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
h_build="$(sha "$binary")"
h_dist="$(sha "dist/$app_name.app/Contents/Frameworks/App.framework/Versions/A/App")"
if [[ "$h_build" != "$h_dist" ]]; then
  echo "构建树与 dist 里的二进制不一致，打包没生效" >&2
  exit 1
fi
h_zip="-"
if [[ $do_zip -eq 1 ]]; then
  h_zip="$(unzip -p "dist/$app_name-macOS.zip" \
             "$app_name.app/Contents/Frameworks/App.framework/Versions/A/App" \
           | shasum -a 256 | awk '{print $1}')"
  if [[ "$h_zip" != "$h_build" ]]; then
    echo "zip 内的二进制与构建树不一致" >&2
    exit 1
  fi
fi

## 源码指纹：让「这包出自哪份源码」可查，而不是只能靠哈希猜
fingerprint="$(find lib macos -type f ! -path '*/ephemeral/*' ! -path '*/build/*' \
  -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')"
git_sha="$(git rev-parse --short HEAD 2>/dev/null || echo '-')"
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
  git_state="${git_sha} + 未提交改动"
else
  git_state="$git_sha"
fi
{
  echo "构建时间: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "源码: $git_state"
  echo "源码指纹(lib+macos): $fingerprint"
  echo "App 二进制 sha256: $h_build"
  echo "zip 内同一文件:    $h_zip"
} > "dist/BUILD-INFO.txt"

## ---- 汇总 ----
step "完成"
printf '  %-30s %s  %s\n' "dist/$app_name.app" \
  "$(du -sh "dist/$app_name.app" | cut -f1)" "${h_build:0:16}…"
if [[ $do_zip -eq 1 ]]; then
  printf '  %-30s %s\n' "dist/$app_name-macOS.zip" "$(du -sh "dist/$app_name-macOS.zip" | cut -f1)"
fi
printf '  %-30s %s\n' "dist/BUILD-INFO.txt" "$git_state"

## 清掉打包暂存：只清超过 30 分钟没动过的（崩溃/中断留下的），
## 不碰刚创建的 —— build/ 是共用的，别的会话可能正在 mktemp 一个同名目录，
## 无差别删会让它的 mv 失败。本次自己那个由 trap 收尾。
find build -maxdepth 1 -name 'package.*' -mmin +30 -exec rm -rf {} + 2>/dev/null || true

## ---- 可选：重启到新包 ----
if [[ $do_run -eq 1 ]]; then
  step "重启到新包"
  pids="$(pgrep -f "[w]orkfollow_personal" || true)"
  if [[ -n "$pids" ]]; then
    kill $pids || true
    sleep 2
  fi
  open "dist/$app_name.app"
  sleep 3
  if pgrep -f "[w]orkfollow_personal" >/dev/null; then
    pgrep -fl "[w]orkfollow_personal" | head -2
  else
    echo "  没起来，手动打开 dist/$app_name.app 看"
  fi
fi
