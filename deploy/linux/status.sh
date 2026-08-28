#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
BACKEND_OK=0
COLLABORATION_OK=0
if [ -f run/workfollow.pid ] && kill -0 "$(cat run/workfollow.pid)" 2>/dev/null; then
  BACKEND_OK=1
  echo "后端运行中，PID $(cat run/workfollow.pid)。"
fi
if [ -f run/workfollow-collaboration.pid ] && kill -0 "$(cat run/workfollow-collaboration.pid)" 2>/dev/null; then
  COLLABORATION_OK=1
  echo "协同服务运行中，PID $(cat run/workfollow-collaboration.pid)。"
fi
if [ "$BACKEND_OK" -ne 1 ] || [ "$COLLABORATION_OK" -ne 1 ]; then
  echo "未运行。"
  exit 1
fi
