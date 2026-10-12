#!/bin/bash
# 由设计稿 design/cubby-logo/ 生成应用图标 Resources/AppIcon.icns，并输出 README 用的 docs/assets/icon.png（512px）
# 用法：./scripts/make-icon.sh（图标设计改动后重新运行并提交两个产物）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/design/cubby-logo"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# appiconset 的文件名与 iconutil 要求的 iconset 命名一致（icon_16x16.png … icon_512x512@2x.png），直接复制
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$SOURCE"/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"

sips -Z 512 "$SOURCE/AppIcon-1024.png" --out "$ROOT/docs/assets/icon.png" >/dev/null
echo "已生成 Resources/AppIcon.icns 与 docs/assets/icon.png"
