#!/bin/bash
set -euo pipefail

desktop_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$desktop_dir"

if [[ "${1:-}" != "--skip-build" ]]; then
  flutter build macos --release
fi

app="build/macos/Build/Products/Release/workfollow_personal.app"
# Incremental Flutter builds can leave the outer seal referring to the old
# App.framework. Refresh local signatures from the inside out before packing.
codesign --force --sign - --timestamp=none "$app/Contents/Frameworks/App.framework"
codesign --force --sign - --timestamp=none --entitlements macos/Runner/Release.entitlements "$app"
codesign --verify --deep --strict "$app"

mkdir -p dist
staging="$(mktemp -d "$desktop_dir/build/package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/打勾.app"
codesign --verify --deep --strict "$staging/打勾.app"
ditto -c -k --sequesterRsrc --keepParent "$staging/打勾.app" dist/打勾-macOS.zip
if [[ -e dist/打勾.app ]]; then
  mv dist/打勾.app "$staging/previous.app"
fi
mv "$staging/打勾.app" dist/打勾.app
printf '%s\n' '已生成 dist/打勾.app 和 dist/打勾-macOS.zip'
