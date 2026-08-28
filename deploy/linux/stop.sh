#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f run/workfollow.pid ]; then
  BACKEND_PID=""
else
  BACKEND_PID="$(cat run/workfollow.pid)"
fi
COLLABORATION_PID=""
if [ -f run/workfollow-collaboration.pid ]; then
  COLLABORATION_PID="$(cat run/workfollow-collaboration.pid)"
fi

for PID in "$COLLABORATION_PID" "$BACKEND_PID"; do
  [ -n "$PID" ] || continue
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    for _ in $(seq 1 20); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.25
    done
  fi
done

rm -f run/workfollow.pid run/workfollow-collaboration.pid
if [ -z "$BACKEND_PID$COLLABORATION_PID" ]; then
  echo "WorkFollow 未运行。"
else
  echo "WorkFollow 已停止。"
fi
