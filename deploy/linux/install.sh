#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

command -v python3 >/dev/null 2>&1 || {
  echo "错误：未找到 Python 3.12。请先离线安装 Python 3.12 x86_64。" >&2
  exit 1
}

PY_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
[ "$PY_VERSION" = "3.12" ] || {
  echo "错误：本安装包要求 Python 3.12，当前为 $PY_VERSION。" >&2
  exit 1
}

python3 -m venv .venv
if find wheelhouse -maxdepth 1 -type f -name '*.whl' -print -quit 2>/dev/null | grep -q .; then
  echo "检测到 wheelhouse，使用本地依赖包安装。"
  .venv/bin/python -m pip install --no-index --find-links wheelhouse -r deploy/requirements-offline.txt
else
  echo "未检测到 wheelhouse，在线下载 Python 依赖。"
  .venv/bin/python -m pip install -r deploy/requirements-offline.txt
fi
mkdir -p data/files data/uploads logs run
.venv/bin/alembic -c backend/alembic.ini upgrade head
chmod +x deploy/linux/start.sh deploy/linux/stop.sh deploy/linux/status.sh deploy/linux/backup.sh
echo "安装完成。执行 deploy/linux/start.sh 启动。"
