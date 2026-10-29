#!/bin/zsh
set -e
cd -- "${0:A:h}"
exec python3 macos-native/scripts/package-release.py "$@"
