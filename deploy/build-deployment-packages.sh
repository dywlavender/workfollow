#!/usr/bin/env bash
set -Eeuo pipefail

# Build WorkFollow archives from the current source tree without modifying
# frontend/node_modules or the working tree's frontend/dist.
#
# Usage:
#   ./deploy/build-deployment-packages.sh
#   ./deploy/build-deployment-packages.sh --version 0.1.1
#   ./deploy/build-deployment-packages.sh --version 0.1.1 --require-offline
#   ./deploy/build-deployment-packages.sh --version 0.1.1 --code-only
#
# Optional offline dependencies:
#   wheelhouse/linux/*.whl     Linux x86_64 Python 3.12 wheels
#   wheelhouse/windows/*.whl   Windows x64 Python 3.12 wheels
#   .runtime-cache/node/        Download cache for bundled Node runtimes

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
VERSION="${WORKFOLLOW_VERSION:-0.1.0}"
REQUIRE_OFFLINE=0
CODE_ONLY=0
NODE_RUNTIME_VERSION="${WORKFOLLOW_NODE_RUNTIME_VERSION:-22.23.2}"
NODE_RUNTIME_CACHE_DIR="${WORKFOLLOW_NODE_RUNTIME_CACHE_DIR:-$ROOT_DIR/.runtime-cache/node}"

usage() {
  sed -n '4,16p' "$0"
}

fail() {
  echo "打包失败：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "缺少命令：$1"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || fail "--version 后必须提供版本号"
      VERSION="$2"
      shift 2
      ;;
    --require-offline)
      REQUIRE_OFFLINE=1
      shift
      ;;
    --code-only)
      CODE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "未知参数：$1"
      ;;
  esac
done

case "$VERSION" in
  *[!A-Za-z0-9._-]*|'') fail "版本号只能包含字母、数字、点、下划线和连字符" ;;
esac

if [ "$CODE_ONLY" -eq 1 ] && [ "$REQUIRE_OFFLINE" -eq 1 ]; then
  fail "--code-only 不应与 --require-offline 一起使用；代码更新包复用目标机已有 Python 环境"
fi

require_command tar
require_command zip
require_command npm
require_command node
if [ "$CODE_ONLY" -eq 0 ]; then
  require_command unzip
fi

has_wheels() {
  find "$1" -maxdepth 1 -type f -name '*.whl' -print -quit 2>/dev/null | grep -q .
}

if [ "$REQUIRE_OFFLINE" -eq 1 ]; then
  has_wheels "$ROOT_DIR/wheelhouse/linux" \
    || fail "缺少 wheelhouse/linux，不能生成完整 Linux 离线包"
  has_wheels "$ROOT_DIR/wheelhouse/windows" \
    || fail "缺少 wheelhouse/windows，不能生成完整 Windows 离线包"
fi

mkdir -p "$RELEASE_DIR"
BUILD_DIR="$(mktemp -d "$RELEASE_DIR/.package-build.XXXXXX")"

cleanup() {
  case "$BUILD_DIR" in
    "$RELEASE_DIR"/.package-build.*) rm -rf "$BUILD_DIR" ;;
    *) echo "警告：拒绝清理异常临时目录：$BUILD_DIR" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

if [ "$CODE_ONLY" -eq 1 ]; then
  echo "[1/5] 在隔离临时目录构建前端并准备代码更新包"
else
  echo "[1/5] 在隔离临时目录安装依赖并使用当前源码构建前端和协同服务"
fi
FRONTEND_BUILD_DIR="$BUILD_DIR/frontend-build"
mkdir -p "$FRONTEND_BUILD_DIR"
tar \
  --exclude='./node_modules' \
  --exclude='./dist' \
  --exclude='./.playwright-cli' \
  -C "$ROOT_DIR/frontend" -cf - . | tar -C "$FRONTEND_BUILD_DIR" -xf -
(
  cd "$FRONTEND_BUILD_DIR"
  npm ci --no-audit --no-fund
  VITE_COLLABORATION_PORT="${WORKFOLLOW_COLLABORATION_PORT:-8124}" npm run build
)
FRONTEND_DIST="$FRONTEND_BUILD_DIR/dist"

[ -f "$FRONTEND_DIST/index.html" ] || fail "前端构建产物缺少 index.html"

# The target host may be completely offline. Build the small, production-only
# collaboration dependency tree into the release staging area so the install
# scripts do not need to contact npm on the target host.
COLLABORATION_BUILD_DIR="$BUILD_DIR/collaboration-build"
mkdir -p "$COLLABORATION_BUILD_DIR"
tar \
  -C "$ROOT_DIR/collaboration" -cf - package.json package-lock.json server.mjs | tar -C "$COLLABORATION_BUILD_DIR" -xf -
if [ "$CODE_ONLY" -eq 0 ]; then
  (
    cd "$COLLABORATION_BUILD_DIR"
    npm ci --omit=dev --no-audit --no-fund
  )
  [ -f "$COLLABORATION_BUILD_DIR/node_modules/@hocuspocus/server/package.json" ] || fail "协同服务依赖安装不完整"
  [ -f "$COLLABORATION_BUILD_DIR/node_modules/@hocuspocus/transformer/package.json" ] || fail "协同服务依赖安装不完整"
  [ -f "$COLLABORATION_BUILD_DIR/node_modules/yjs/package.json" ] || fail "协同服务依赖安装不完整"
else
  echo "代码更新包复用目标机已有 collaboration/node_modules，跳过协同服务依赖安装"
fi

download_runtime() {
  local filename="$1"
  local target="$NODE_RUNTIME_CACHE_DIR/$filename"
  local temporary="$target.partial"
  if [ ! -f "$target" ]; then
    require_command curl
    mkdir -p "$NODE_RUNTIME_CACHE_DIR"
    echo "下载 Node.js $NODE_RUNTIME_VERSION 运行时：$filename" >&2
    curl -fL --retry 3 --connect-timeout 20 \
      "https://nodejs.org/dist/v$NODE_RUNTIME_VERSION/$filename" \
      -o "$temporary" \
      || fail "Node.js 运行时下载失败：$filename"
    mv "$temporary" "$target"
  fi
  printf '%s\n' "$target"
}

if [ "$CODE_ONLY" -eq 0 ]; then
  echo "[2/5] 准备发布包内置 Node.js $NODE_RUNTIME_VERSION 运行时"
  LINUX_NODE_ARCHIVE="$(download_runtime "node-v$NODE_RUNTIME_VERSION-linux-x64.tar.xz")"
  WINDOWS_NODE_ARCHIVE="$(download_runtime "node-v$NODE_RUNTIME_VERSION-win-x64.zip")"
  LINUX_NODE_EXTRACT="$BUILD_DIR/node-linux"
  WINDOWS_NODE_EXTRACT="$BUILD_DIR/node-windows"
  mkdir -p "$LINUX_NODE_EXTRACT" "$WINDOWS_NODE_EXTRACT"
  tar -xJf "$LINUX_NODE_ARCHIVE" -C "$LINUX_NODE_EXTRACT"
  unzip -q "$WINDOWS_NODE_ARCHIVE" -d "$WINDOWS_NODE_EXTRACT"
  LINUX_NODE_SOURCE="$LINUX_NODE_EXTRACT/node-v$NODE_RUNTIME_VERSION-linux-x64"
  WINDOWS_NODE_SOURCE="$WINDOWS_NODE_EXTRACT/node-v$NODE_RUNTIME_VERSION-win-x64"
  [ -x "$LINUX_NODE_SOURCE/bin/node" ] || fail "Linux Node.js 运行时内容不完整"
  [ -f "$WINDOWS_NODE_SOURCE/node.exe" ] || fail "Windows Node.js 运行时内容不完整"
  [ -f "$LINUX_NODE_SOURCE/LICENSE" ] || fail "Linux Node.js 运行时缺少 LICENSE"
  [ -f "$WINDOWS_NODE_SOURCE/LICENSE" ] || fail "Windows Node.js 运行时缺少 LICENSE"
else
  echo "[2/5] 跳过内置 Node.js 运行时和协同服务依赖"
fi

LINUX_STAGE="$BUILD_DIR/stage-linux"
WINDOWS_STAGE="$BUILD_DIR/stage-windows"

copy_app() {
  local target="$1"
  mkdir -p \
    "$target/backend" \
    "$target/frontend" \
    "$target/collaboration" \
    "$target/deploy" \
    "$target/docs"
  if [ "$CODE_ONLY" -eq 0 ]; then
    mkdir -p "$target/data/files" "$target/data/uploads"
  fi

  tar \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.venv' \
    --exclude='tests' \
    -C "$ROOT_DIR/backend" -cf - alembic app alembic.ini | tar -C "$target/backend" -xf -
  cp -R "$FRONTEND_DIST" "$target/frontend/"
  cp -R "$COLLABORATION_BUILD_DIR"/. "$target/collaboration/"
  cp "$ROOT_DIR/deploy/requirements-offline.txt" "$target/deploy/"
  cp "$ROOT_DIR/.env.example" "$target/.env.example"
  cp "$ROOT_DIR/DEPLOYMENT_MANUAL.md" "$target/"
  cp "$ROOT_DIR/docs/mcp-integration.md" "$target/docs/"
}

copy_wheelhouse() {
  local source="$1"
  local target="$2"
  if has_wheels "$source"; then
    mkdir -p "$target/wheelhouse"
    cp "$source"/*.whl "$target/wheelhouse/"
  fi
}

if [ "$CODE_ONLY" -eq 1 ]; then
  echo "[3/5] 组装 Linux 代码更新目录"
else
  echo "[3/5] 组装 Linux 安装目录"
fi
copy_app "$LINUX_STAGE"
cp -R "$ROOT_DIR/deploy/linux" "$LINUX_STAGE/deploy/"
chmod +x "$LINUX_STAGE/deploy/linux/"*.sh
if [ "$CODE_ONLY" -eq 0 ]; then
  copy_wheelhouse "$ROOT_DIR/wheelhouse/linux" "$LINUX_STAGE"
  mkdir -p "$LINUX_STAGE/runtime/node/bin"
  cp "$LINUX_NODE_SOURCE/bin/node" "$LINUX_STAGE/runtime/node/bin/node"
  cp "$LINUX_NODE_SOURCE/LICENSE" "$LINUX_STAGE/runtime/node/LICENSE"
  chmod +x "$LINUX_STAGE/runtime/node/bin/node"
fi

if [ "$CODE_ONLY" -eq 1 ]; then
  echo "[4/5] 组装 Windows 代码更新目录"
else
  echo "[4/5] 组装 Windows 安装目录"
fi
copy_app "$WINDOWS_STAGE"
cp -R "$ROOT_DIR/deploy/windows" "$WINDOWS_STAGE/deploy/"
if [ "$CODE_ONLY" -eq 0 ]; then
  copy_wheelhouse "$ROOT_DIR/wheelhouse/windows" "$WINDOWS_STAGE"
  mkdir -p "$WINDOWS_STAGE/runtime/node"
  cp "$WINDOWS_NODE_SOURCE/node.exe" "$WINDOWS_STAGE/runtime/node/node.exe"
  cp "$WINDOWS_NODE_SOURCE/LICENSE" "$WINDOWS_STAGE/runtime/node/LICENSE"
fi

if [ "$CODE_ONLY" -eq 1 ]; then
  LINUX_NAME="WorkFollow-$VERSION-linux-x86_64-update.tar.gz"
  WINDOWS_NAME="WorkFollow-$VERSION-windows-x64-update.zip"
else
  LINUX_NAME="WorkFollow-$VERSION-linux-x86_64.tar.gz"
  WINDOWS_NAME="WorkFollow-$VERSION-windows-x64.zip"
fi
LINUX_TEMP="$BUILD_DIR/$LINUX_NAME"
WINDOWS_TEMP="$BUILD_DIR/$WINDOWS_NAME"

if [ "$CODE_ONLY" -eq 1 ]; then
  echo "[5/5] 生成代码更新压缩包"
else
  echo "[5/5] 生成完整发布压缩包"
fi
tar -czf "$LINUX_TEMP" -C "$LINUX_STAGE" .
(
  cd "$WINDOWS_STAGE"
  zip -qr "$WINDOWS_TEMP" .
)

# Publish only after every build step succeeds.
mv "$LINUX_TEMP" "$RELEASE_DIR/$LINUX_NAME"
mv "$WINDOWS_TEMP" "$RELEASE_DIR/$WINDOWS_NAME"

echo
echo "打包完成："
echo "  $RELEASE_DIR/$LINUX_NAME"
echo "  $RELEASE_DIR/$WINDOWS_NAME"
