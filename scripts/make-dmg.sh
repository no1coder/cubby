#!/usr/bin/env bash
# 将 build/Cubby.app 打包为 dist/Cubby-<版本>.dmg（卷标 Cubby，内含 Cubby.app 与「应用程序」快捷方式）
#
# 用法：./scripts/make-dmg.sh [App 路径]      （或 make dmg；默认 build/Cubby.app）
#
# 环境变量（可选）：
#   SIGN_IDENTITY  为 Developer ID Application 身份时对 DMG 签名（带安全时间戳）；
#                  ad-hoc / 开发证书 / 未设置时不签名 DMG（DMG 签名仅对公证分发有意义）。
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

VERSION="$(read_version)"
APP_PATH="${1:-$CUBBY_ROOT/build/$CUBBY_APP_NAME.app}"
DIST_DIR="$CUBBY_ROOT/dist"
DMG_PATH="$DIST_DIR/$CUBBY_APP_NAME-$VERSION.dmg"
VOLUME_NAME="$CUBBY_APP_NAME"

[[ -d "$APP_PATH" ]] || die "找不到 $APP_PATH，请先运行 ./scripts/build-app.sh"
command -v hdiutil >/dev/null || die "需要 macOS 自带的 hdiutil"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-dmg.XXXXXX")"
MOUNT_DIR=""
cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

log "准备 DMG 内容"
# ditto 保留扩展属性、签名与 staple 票据
ditto "$APP_PATH" "$STAGING_DIR/$CUBBY_APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

# GitHub macOS runner 上 hdiutil 偶发 "Resource busy"，失败时重试
log "生成 $DMG_PATH"
for attempt in 1 2 3; do
    if hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" \
        -fs HFS+ -format ULFO -ov "$DMG_PATH" >/dev/null; then
        break
    fi
    [[ "$attempt" -lt 3 ]] || die "hdiutil create 连续失败 3 次"
    warn "hdiutil create 失败，第 $attempt 次重试…"
    sleep $((attempt * 5))
done

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -n "$SIGN_IDENTITY" && "$(identity_kind "$SIGN_IDENTITY")" == developer-id ]]; then
    log "签名 DMG（$SIGN_IDENTITY）"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --strict --verbose=2 "$DMG_PATH"
else
    log "非 Developer ID 身份，跳过 DMG 签名"
fi

log "校验 DMG"
hdiutil verify -quiet "$DMG_PATH"

# 挂载检查内容：必须包含 Cubby.app 与指向 /Applications 的符号链接
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-mount.XXXXXX")"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" -quiet
[[ -d "$MOUNT_DIR/$CUBBY_APP_NAME.app" ]] || die "DMG 中缺少 $CUBBY_APP_NAME.app"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || die "DMG 中缺少 Applications 快捷方式"
codesign --verify --strict "$MOUNT_DIR/$CUBBY_APP_NAME.app" || die "DMG 内的 $CUBBY_APP_NAME.app 签名校验失败"
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR" 2>/dev/null || true
MOUNT_DIR=""

log "完成：$DMG_PATH（$(du -h "$DMG_PATH" | cut -f1)）"
