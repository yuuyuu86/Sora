#!/bin/zsh
# Sora.app をビルドして build/ に作成する
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Sora.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Sora" "$APP/Contents/MacOS/Sora"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
