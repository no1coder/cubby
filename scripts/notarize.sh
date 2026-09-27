#!/usr/bin/env bash
# 公证并 staple：.app（自动压缩为 zip 提交）、.dmg 或 .pkg
#
# 用法：./scripts/notarize.sh <Cubby.app | Cubby-x.y.z.dmg | *.pkg>
#
# 认证方式（二选一，均通过环境变量提供，脚本本身不保存任何凭据）：
#   1) 本机钥匙串配置（维护者本地）：
#        NOTARY_PROFILE   notarytool 钥匙串配置名，默认 cubby-notary
#        （由维护者本人执行一次 xcrun notarytool store-credentials cubby-notary ... 创建）
#   2) App Store Connect API Key（CI）：
#        NOTARY_KEY_PATH  AuthKey_<KEYID>.p8 文件路径
#        NOTARY_KEY_ID    Key ID
#        NOTARY_ISSUER_ID Issuer ID（团队密钥必填，个人密钥留空）
#      设置了 NOTARY_KEY_PATH 即使用此方式。
#
# 可选：NOTARY_TIMEOUT 等待公证结果的超时，默认 1h
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

[[ $# -eq 1 ]] || die "用法：$0 <Cubby.app | *.dmg | *.pkg>"
TARGET="${1%/}"
[[ -e "$TARGET" ]] || die "找不到 $TARGET"

# ---------- 认证参数 ----------

AUTH_ARGS=()
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    [[ -f "$NOTARY_KEY_PATH" ]] || die "NOTARY_KEY_PATH 指向的文件不存在"
    [[ -n "${NOTARY_KEY_ID:-}" ]] || die "使用 API Key 公证时必须设置 NOTARY_KEY_ID"
    AUTH_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID")
    # 团队密钥（Team Key）必须提供 Issuer ID；个人密钥（Individual Key）不需要
    if [[ -n "${NOTARY_ISSUER_ID:-}" ]]; then
        AUTH_ARGS+=(--issuer "$NOTARY_ISSUER_ID")
    fi
    AUTH_DESC="App Store Connect API Key（$NOTARY_KEY_ID）"
else
    NOTARY_PROFILE="${NOTARY_PROFILE:-cubby-notary}"
    AUTH_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    AUTH_DESC="钥匙串配置 $NOTARY_PROFILE"
fi

# ---------- 确定提交文件 ----------

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-notary.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

case "$TARGET" in
    *.app)
        # .app 不能直接提交，按 Apple 推荐用 ditto 压缩；公证通过后票据 staple 到 .app 本身
        SUBMIT_FILE="$WORK_DIR/$(basename "$TARGET" .app).zip"
        ditto -c -k --keepParent "$TARGET" "$SUBMIT_FILE"
        ;;
    *.dmg | *.pkg | *.zip)
        SUBMIT_FILE="$TARGET"
        ;;
    *) die "不支持的文件类型：$TARGET" ;;
esac

# ---------- 提交并等待结果 ----------

RESULT_JSON="$WORK_DIR/submit.json"
log "提交公证：$(basename "$TARGET")（$AUTH_DESC）"
set +e
xcrun notarytool submit "$SUBMIT_FILE" "${AUTH_ARGS[@]}" \
    --wait --timeout "${NOTARY_TIMEOUT:-1h}" --output-format json >"$RESULT_JSON"
SUBMIT_EXIT=$?
set -e

json_field() { plutil -extract "$1" raw -o - "$RESULT_JSON" 2>/dev/null || true; }
SUBMISSION_ID="$(json_field id)"
STATUS="$(json_field status)"
log "公证结果：${STATUS:-未知}（submission id: ${SUBMISSION_ID:-无}）"

if [[ "$STATUS" != "Accepted" ]]; then
    cat "$RESULT_JSON" >&2 || true
    if [[ -n "$SUBMISSION_ID" ]]; then
        log "公证日志（notarytool log）："
        xcrun notarytool log "$SUBMISSION_ID" "${AUTH_ARGS[@]}" >&2 || true
    fi
    die "公证未通过（notarytool 退出码 $SUBMIT_EXIT），请根据上方日志修复后重试"
fi

# 公证通过时也保留日志中的警告，便于排查
if [[ -n "$SUBMISSION_ID" ]] \
    && xcrun notarytool log "$SUBMISSION_ID" "${AUTH_ARGS[@]}" "$WORK_DIR/log.json" >/dev/null 2>&1; then
    if grep -q '"issues" *: *\[' "$WORK_DIR/log.json"; then
        warn "公证通过但日志中包含 issues："
        cat "$WORK_DIR/log.json" >&2
    fi
fi

# ---------- staple 与 Gatekeeper 校验 ----------

if [[ "$TARGET" == *.zip ]]; then
    warn "zip 无法 staple，请对其中的 .app 单独 staple"
    exit 0
fi

log "staple 票据"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

log "Gatekeeper 校验"
case "$TARGET" in
    *.app) spctl -a -vvv -t exec "$TARGET" ;;
    *.pkg) spctl -a -vvv -t install "$TARGET" ;;
    # DMG 按 Apple TN 的方式评估其自身签名（-t install 对 DMG 的结论相同，但语义不直观）
    *.dmg) spctl -a -vvv -t open --context context:primary-signature "$TARGET" ;;
esac

log "完成：$TARGET 已公证并 staple"
