#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: prepare-replica-acceptance.sh <Debug-products-directory> <new-acceptance-directory>" >&2
  exit 1
fi

REPLICA_PRODUCTS="$1"
REPLICA_DIRECTORY="$2"
REPLICA_SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPLICA_APP="$REPLICA_DIRECTORY/WorkFollowReplicaQA.app"
REPLICA_TOOL="$REPLICA_DIRECTORY/prepare-replica-fixture"

mkdir -p "$REPLICA_DIRECTORY"
xcrun swiftc -parse-as-library \
  -module-cache-path "$REPLICA_DIRECTORY/module-cache" \
  -I "$REPLICA_PRODUCTS" \
  "$REPLICA_PRODUCTS/WorkFollow.app/Contents/MacOS/WorkFollow.debug.dylib" \
  "$REPLICA_SCRIPT_DIRECTORY/prepare-replica-fixture.swift" -o "$REPLICA_TOOL"
DYLD_LIBRARY_PATH="$REPLICA_PRODUCTS/WorkFollow.app/Contents/MacOS" \
  "$REPLICA_TOOL" "$REPLICA_DIRECTORY/storage"

ditto "$REPLICA_PRODUCTS/WorkFollow.app" "$REPLICA_APP"
REPLICA_INFO="$REPLICA_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.workfollow.native.replica.qa "$REPLICA_INFO"
plutil -replace CFBundleDisplayName -string 'WorkFollow Replica QA' "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceStorageRoot -string "$REPLICA_DIRECTORY/storage" "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceClock -string '2026-10-13T12:00:00+08:00' "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceAppearance -string light "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceWindowWidth -integer 1512 "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceWindowHeight -integer 859 "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceDestination -string allTasks "$REPLICA_INFO"
plutil -replace WorkFollowAcceptanceSelectFirst -bool YES "$REPLICA_INFO"
if plutil -extract CFBundleURLTypes raw -o - "$REPLICA_INFO" >/dev/null 2>&1; then
  plutil -remove CFBundleURLTypes "$REPLICA_INFO"
fi
codesign --force --deep --sign - "$REPLICA_APP" >/dev/null 2>&1
echo "$REPLICA_APP"
