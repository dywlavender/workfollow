#!/usr/bin/env bash
#
# 在「无法使用 xcodebuild test」的环境里跑真实的 XCTest。
#
# 背景：本机 `xcodebuild test` 会在 test runner 建立连接前挂住（"The test runner hung
# before establishing connection"），一个用例都不会执行。这不是代码问题——构建出来的
# 应用能正常启动并常驻。挂住的是 xcodebuild 与 testmanagerd 之间的 IPC 那一层。
#
# 绕法：直接拿构建产物里的 .xctest 包，用 `xcrun xctest` 进程内加载并执行。这样走的
# 是 XCTest 自己的执行路径，断言、失败信息、用例计数都是真的，只是绕开了 xcodebuild
# 的 runner 编排。
#
# 唯一需要处理的是动态库解析：测试包用 `@rpath/WorkFollow.debug.dylib` 之类的相对路径，
# 而这些库在应用包里。测试包的 LC_RPATH 里有 `@loader_path/../Frameworks`，所以把包
# 拷到临时目录、在 `Contents/Frameworks` 下放几个符号链接就满足了——不改动 DerivedData，
# 也不用 install_name_tool（它常常因 headerpad 不足而失败）。
#
# 用法：
#   scripts/run-tests.sh                  # 跑全部用例
#   scripts/run-tests.sh QuickAddCompositionTests
#   scripts/run-tests.sh QuickAddCompositionTests GlobalQuickAddTests
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$PROJECT_DIR/WorkFollow.xcodeproj"
SCHEME="WorkFollow"

# 默认 DerivedData 在 ~/Library 下。若当前环境不允许写那里（沙箱、CI 只读 HOME 等），
# xcodebuild 会在 "Build Preparation" 阶段就失败，报错是
#   Unable to write to info file '.../DerivedData/<proj>/info.plist'
# 这时把 WORKFOLLOW_DERIVED_DATA 指到一个可写目录即可，例如：
#   WORKFOLLOW_DERIVED_DATA=/tmp/wf-dd scripts/run-tests.sh
DERIVED_DATA_ARGS=()
if [[ -n "${WORKFOLLOW_DERIVED_DATA:-}" ]]; then
  mkdir -p "$WORKFOLLOW_DERIVED_DATA"
  DERIVED_DATA_ARGS=(-derivedDataPath "$WORKFOLLOW_DERIVED_DATA")
fi

# Xcode 27 起 `@State` 变成了宏，Swift 编译宏时要在一个子沙箱里跑
# swift-plugin-server。若当前进程树本身已被沙箱化（agent 沙箱、CI 容器等），
# 子沙箱会套不上，报：
#   sandbox-exec: sandbox_apply: Operation not permitted
#   error: external macro implementation type 'SwiftUIMacros.StateMacro' could
#          not be found for macro 'State()'; ... produced malformed response
# 这**不是代码问题**，而且会连带报出一堆 `cannot find '_name' in scope` /
# `cannot assign to property: 'self' is immutable` 的假错误。
# 设 WORKFOLLOW_DISABLE_SWIFT_SANDBOX=1 绕开（本地 Xcode GUI 构建不需要）。
EXTRA_BUILD_ARGS=()
if [[ -n "${WORKFOLLOW_DISABLE_SWIFT_SANDBOX:-}" ]]; then
  EXTRA_BUILD_ARGS=(OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox')
fi

echo "==> 构建测试产物"
xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
  "${DERIVED_DATA_ARGS[@]+"${DERIVED_DATA_ARGS[@]}"}" \
  "${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"}" \
  2>&1 | grep -E "error:|TEST BUILD" || true

if [[ ${#DERIVED_DATA_ARGS[@]} -gt 0 ]]; then
  BUILT_PRODUCTS="$WORKFOLLOW_DERIVED_DATA/Build/Products/Debug"
else
  BUILT_PRODUCTS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^ *BUILT_PRODUCTS_DIR = / { print $2; exit }')"
fi
if [[ -z "$BUILT_PRODUCTS" || ! -d "$BUILT_PRODUCTS" ]]; then
  echo "找不到 BUILT_PRODUCTS_DIR，构建可能没有产出。" >&2
  exit 1
fi

APP="$BUILT_PRODUCTS/WorkFollow.app"
SRC_BUNDLE="$APP/Contents/PlugIns/WorkFollowTests.xctest"
if [[ ! -d "$SRC_BUNDLE" ]]; then
  echo "找不到测试包：$SRC_BUNDLE" >&2
  exit 1
fi

DEVELOPER_DIR_PATH="$(xcode-select -p)"
XCTEST_FRAMEWORK="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework"
XCTEST_SUPPORT="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/usr/lib/libXCTestSwiftSupport.dylib"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/workfollow-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

BUNDLE="$WORK/WorkFollowTests.xctest"
cp -R "$SRC_BUNDLE" "$BUNDLE"
mkdir -p "$BUNDLE/Contents/Frameworks"
ln -s "$APP/Contents/MacOS/WorkFollow.debug.dylib" "$BUNDLE/Contents/Frameworks/WorkFollow.debug.dylib"
ln -s "$XCTEST_FRAMEWORK" "$BUNDLE/Contents/Frameworks/XCTest.framework"
ln -s "$XCTEST_SUPPORT" "$BUNDLE/Contents/Frameworks/libXCTestSwiftSupport.dylib"

echo "==> 执行用例"
# macOS 自带 bash 3.2：`set -u` 下展开空数组会报 unbound variable，所以分两支写。
if [[ $# -gt 0 ]]; then
  ARGS=()
  for filter in "$@"; do
    ARGS+=(-XCTest "$filter")
  done
  xcrun xctest "${ARGS[@]}" "$BUNDLE"
else
  xcrun xctest "$BUNDLE"
fi
