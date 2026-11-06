#!/usr/bin/env bash
#
# 在「无法使用 xcodebuild test」的环境里跑真实的 XCTest。
#
# 背景：本机 `xcodebuild test` 会在 test runner 建立连接前挂住（"The test runner hung
# before establishing connection"），一个用例都不会执行。这不是代码问题——构建出来的
# 应用能正常启动并常驻。挂住的是 xcodebuild 与 testmanagerd 之间的 IPC 那一层。
#
# 绕法：用签名后的正式 App 副本加载其 .xctest 包，直接运行 XCTestSuite。
# 绕开 testmanagerd 的 runner 编排，同时让 WKWebView 保留真实 App 的宿主身份。
# 测试专用入口仅在 WORKFOLLOW_APP_TEST_HOST 编译条件下存在；数据目录隔离。
#
# 用法：
#   scripts/run-tests.sh                  # 跑全部用例
#   scripts/run-tests.sh QuickAddCompositionTests
#   scripts/run-tests.sh QuickAddCompositionTests GlobalQuickAddTests
#   scripts/run-tests.sh "QuickAddCompositionTests,GlobalQuickAddTests"   # 等价
#
# 类名必须写全；找不到类或执行零用例都返回失败。旧 xctest 入口曾有以下陷阱：
# `Meeting`、`MeetingStore` 两种写法都得到 "Executed 0 tests" 且 exit 0
# （**看起来像全绿**），只有 `MeetingStoreTests` 才真的跑起来。别用简称。
# （本文件上一版这里写的是「子串匹配」，是错的，已改。）
#
# 通知相关测试需要有效 App bundle，下面会创建临时 XCTest 宿主，
# 并将默认数据目录重定向到临时目录。构建失败和零用例均返回非零状态。
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
EXTRA_BUILD_ARGS=(OTHER_SWIFT_FLAGS='$(inherited) -D WORKFOLLOW_APP_TEST_HOST')
if [[ -n "${WORKFOLLOW_DISABLE_SWIFT_SANDBOX:-}" ]]; then
  EXTRA_BUILD_ARGS=(OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox -D WORKFOLLOW_APP_TEST_HOST')
fi
if [[ "${WORKFOLLOW_TEST_OPTIMIZE:-}" == "1" ]]; then
  # Keep Xcode's debug-dylib layout for the standalone XCTest loader while
  # the Swift compiler optimizes the same application and test source.
  if [[ -n "${WORKFOLLOW_DISABLE_SWIFT_SANDBOX:-}" ]]; then
    EXTRA_BUILD_ARGS=(OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox -D WORKFOLLOW_APP_TEST_HOST -O')
  else
    EXTRA_BUILD_ARGS=(OTHER_SWIFT_FLAGS='$(inherited) -D WORKFOLLOW_APP_TEST_HOST -O')
  fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/workfollow-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Check the producer itself, not grep's exit status; never run old build products.
# The isolated XCTest host does not use the production App Group. Build without
# provisioning so local tests continue to work without a developer certificate.
echo "==> 构建测试产物"
if xcodebuild build-for-testing \
  -project "$PROJECT" -scheme "$SCHEME" -destination "platform=macOS,arch=$(uname -m)" \
  CODE_SIGNING_ALLOWED=NO \
  "${DERIVED_DATA_ARGS[@]+"${DERIVED_DATA_ARGS[@]}"}" \
  "${EXTRA_BUILD_ARGS[@]+"${EXTRA_BUILD_ARGS[@]}"}" \
  > "$WORK/build.log" 2>&1; then
  grep -E "error:|TEST BUILD" "$WORK/build.log" || true
else
  BUILD_STATUS=$?
  cat "$WORK/build.log" >&2
  exit "$BUILD_STATUS"
fi

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
RUNNER="$WORK/WorkFollowTestsRunner.app"
# A real application executable is required by WebKit. The standalone xctest
# executable aborts when WebContent asks for its owning application's extension.
cp -cR "$APP" "$RUNNER"
mkdir -p "$WORK/storage"
plutil -replace CFBundleIdentifier -string com.workfollow.native.tests.runner "$RUNNER/Contents/Info.plist"
plutil -replace WorkFollowAcceptanceStorageRoot -string "$WORK/storage" "$RUNNER/Contents/Info.plist"
if ! /usr/bin/codesign --force --deep --sign - "$RUNNER" > "$WORK/sign.log" 2>&1; then
  cat "$WORK/sign.log" >&2
  exit 1
fi
export DYLD_FRAMEWORK_PATH="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks:$DEVELOPER_DIR_PATH/SharedFrameworks${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
export DYLD_LIBRARY_PATH="$RUNNER/Contents/MacOS:$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/usr/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
TEST_ARGS=()
if [[ $# -gt 0 ]]; then
  JOINED="$(IFS=,; echo "$*")"
  TEST_ARGS=(--wf-test-classes "$JOINED")
fi

echo "==> 执行用例（真实 App 宿主、隔离存储）"
if "$RUNNER/Contents/MacOS/WorkFollow" --automation --wf-xctest "$RUNNER/Contents/PlugIns/WorkFollowTests.xctest" "${TEST_ARGS[@]+"${TEST_ARGS[@]}"}" > "$WORK/tests.log" 2>&1; then
  cat "$WORK/tests.log"
else
  TEST_STATUS=$?
  cat "$WORK/tests.log" >&2
  exit "$TEST_STATUS"
fi
if ! awk '
  /Executed [0-9]+ tests?,/ {
    skipped = /tests? skipped/ ? $5 : 0
    if ($2 > skipped && /(^|[[:space:]])0 failures/) passed = 1
  }
  END { exit passed ? 0 : 1 }
' "$WORK/tests.log"; then
  echo "没有执行任何测试或全部跳过；检查完整的类名/方法名，不能把零用例当作通过。" >&2
  exit 1
fi
