#!/usr/bin/env bash
set -Eeuo pipefail

# Build WorkFollow archives without modifying frontend/node_modules.
#
# Usage:
#   ./deploy/build-deployment-packages.sh
#   ./deploy/build-deployment-packages.sh --version 0.1.1
#   ./deploy/build-deployment-packages.sh --skip-frontend-build
#
# Optional offline dependencies:
#   wheelhouse/linux/*.whl     Linux x86_64 Python 3.12 wheels
#   wheelhouse/windows/*.whl   Windows x64 Python 3.12 wheels

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
VERSION="${WORKFOLLOW_VERSION:-0.1.0}"
SKIP_FRONTEND_BUILD="${SKIP_FRONTEND_BUILD:-0}"

usage() {
  sed -n '3,12p' "$0"
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
    --skip-frontend-build)
      SKIP_FRONTEND_BUILD=1
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

require_command tar
require_command zip
if [ "$SKIP_FRONTEND_BUILD" != "1" ]; then
  require_command npm
  require_command node
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

FRONTEND_DIST="$ROOT_DIR/frontend/dist"
if [ "$SKIP_FRONTEND_BUILD" = "1" ]; then
  [ -f "$FRONTEND_DIST/index.html" ] || fail "frontend/dist 不存在，不能跳过前端构建"
  echo "[1/5] 使用现有 frontend/dist"
else
  echo "[1/5] 在隔离临时目录安装依赖并构建前端"
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
    npm run build
  )
  FRONTEND_DIST="$FRONTEND_BUILD_DIR/dist"
fi

[ -f "$FRONTEND_DIST/index.html" ] || fail "前端构建产物缺少 index.html"

LINUX_STAGE="$BUILD_DIR/stage-linux"
WINDOWS_STAGE="$BUILD_DIR/stage-windows"

copy_app() {
  local target="$1"
  mkdir -p \
    "$target/backend" \
    "$target/frontend" \
    "$target/deploy" \
    "$target/data/files" \
    "$target/data/uploads"

  tar \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.venv' \
    --exclude='tests' \
    -C "$ROOT_DIR/backend" -cf - alembic app alembic.ini | tar -C "$target/backend" -xf -
  cp -R "$FRONTEND_DIST" "$target/frontend/"
  cp "$ROOT_DIR/deploy/requirements-offline.txt" "$target/deploy/"
  cp "$ROOT_DIR/DEPLOYMENT_MANUAL.md" "$target/"
}

copy_wheelhouse() {
  local source="$1"
  local target="$2"
  if find "$source" -maxdepth 1 -type f -name '*.whl' -print -quit 2>/dev/null | grep -q .; then
    mkdir -p "$target/wheelhouse"
    cp "$source"/*.whl "$target/wheelhouse/"
  fi
}

echo "[2/5] 组装 Linux 安装目录"
copy_app "$LINUX_STAGE"
cp -R "$ROOT_DIR/deploy/linux" "$LINUX_STAGE/deploy/"
chmod +x "$LINUX_STAGE/deploy/linux/"*.sh
copy_wheelhouse "$ROOT_DIR/wheelhouse/linux" "$LINUX_STAGE"

echo "[3/5] 组装 Windows 安装目录"
copy_app "$WINDOWS_STAGE"
cp -R "$ROOT_DIR/deploy/windows" "$WINDOWS_STAGE/deploy/"
copy_wheelhouse "$ROOT_DIR/wheelhouse/windows" "$WINDOWS_STAGE"

LINUX_NAME="WorkFollow-$VERSION-linux-x86_64.tar.gz"
WINDOWS_NAME="WorkFollow-$VERSION-windows-x64.zip"
LINUX_TEMP="$BUILD_DIR/$LINUX_NAME"
WINDOWS_TEMP="$BUILD_DIR/$WINDOWS_NAME"

echo "[4/5] 生成压缩包"
tar -czf "$LINUX_TEMP" -C "$LINUX_STAGE" .
(
  cd "$WINDOWS_STAGE"
  zip -qr "$WINDOWS_TEMP" .
)

echo "[5/5] 生成 SHA-256 校验文件"
CHECKSUM_TEMP="$BUILD_DIR/SHA256SUMS.txt"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$BUILD_DIR"
    sha256sum "$LINUX_NAME" "$WINDOWS_NAME" > "$CHECKSUM_TEMP"
  )
elif command -v shasum >/dev/null 2>&1; then
  (
    cd "$BUILD_DIR"
    shasum -a 256 "$LINUX_NAME" "$WINDOWS_NAME" > "$CHECKSUM_TEMP"
  )
else
  fail "缺少 sha256sum 或 shasum"
fi

# Publish only after every build step succeeds.
mv "$LINUX_TEMP" "$RELEASE_DIR/$LINUX_NAME"
mv "$WINDOWS_TEMP" "$RELEASE_DIR/$WINDOWS_NAME"
mv "$CHECKSUM_TEMP" "$RELEASE_DIR/SHA256SUMS.txt"

echo
echo "打包完成："
echo "  $RELEASE_DIR/$LINUX_NAME"
echo "  $RELEASE_DIR/$WINDOWS_NAME"
echo "  $RELEASE_DIR/SHA256SUMS.txt"
