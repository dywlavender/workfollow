#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
mkdir -p backups
STAMP="$(date +%Y%m%d-%H%M%S)"
tar -czf "backups/workfollow-data-$STAMP.tar.gz" data
echo "备份完成：backups/workfollow-data-$STAMP.tar.gz"
