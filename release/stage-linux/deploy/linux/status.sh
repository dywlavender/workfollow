#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
if [ -f run/workfollow.pid ] && kill -0 "$(cat run/workfollow.pid)" 2>/dev/null; then
  echo "运行中，PID $(cat run/workfollow.pid)。"
else
  echo "未运行。"
  exit 1
fi
