#!/usr/bin/env bash
# 端到端发布：构建 → Developer ID 签名 → 公证 .app 并 staple → DMG → 公证 DMG 并 staple
#            → zip → SHA256SUMS.txt → 发布说明 NOTES.md，产物全部位于 dist/
#
# 用法：./scripts/release.sh [--skip-notarize]      （或 make release）
#   --skip-notarize  跳过公证与 Gatekeeper 校验，用于无凭据的本地演练，
#                    可配合 SIGN_IDENTITY=- 使用 ad-hoc 签名（产物不可对外分发）。
#
# 环境变量：
#   SIGN_IDENTITY  签名身份，默认自动选用钥匙串中第一个 "Developer ID Application" 证书
#   NOTARY_*       公证凭据，见 scripts/notarize.sh（本地默认钥匙串配置 cubby-notary）
#   BUILD_NUMBER   透传给 build-app.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

SKIP_NOTARIZE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *) die "未知参数：$1（见 --help）" ;;
    esac
    shift
done

SCRIPTS="$CUBBY_ROOT/scripts"
VERSION="$(read_version)"
APP_PATH="$CUBBY_ROOT/build/$CUBBY_APP_NAME.app"
DIST_DIR="$CUBBY_ROOT/dist"
DMG_NAME="$CUBBY_APP_NAME-$VERSION.dmg"
ZIP_NAME="$CUBBY_APP_NAME-$VERSION.zip"

# ---------- 预检 ----------

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(find_identity "Developer ID Application")"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        [[ "$SKIP_NOTARIZE" -eq 1 ]] || die "钥匙串中没有 Developer ID Application 证书，无法发布（演练请加 --skip-notarize）"
        warn "未找到 Developer ID 证书，演练模式改用 ad-hoc 签名"
        SIGN_IDENTITY="-"
    fi
fi
export SIGN_IDENTITY
KIND="$(identity_kind "$SIGN_IDENTITY")"

if [[ "$SKIP_NOTARIZE" -eq 0 && "$KIND" != developer-id ]]; then
    die "公证要求 Developer ID Application 身份，当前为 $SIGN_IDENTITY（$KIND）"
fi

if git -C "$CUBBY_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && [[ -n "$(git -C "$CUBBY_ROOT" status --porcelain --untracked-files=no)" ]]; then
    warn "工作区有未提交的改动，产物可能与 tag 不一致"
fi

log "发布 $CUBBY_APP_NAME $VERSION（签名：$SIGN_IDENTITY；公证：$([[ $SKIP_NOTARIZE -eq 1 ]] && echo 跳过 || echo 是)）"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ---------- 1. 构建并签名 .app ----------

"$SCRIPTS/build-app.sh"

if [[ "$KIND" == developer-id ]]; then
    # 公证要求：Hardened Runtime + 安全时间戳
    SIGN_INFO="$(codesign -dvv "$APP_PATH" 2>&1)"
    grep -q 'flags=.*runtime' <<<"$SIGN_INFO" || die "签名缺少 Hardened Runtime"
    grep -q '^Timestamp=' <<<"$SIGN_INFO" || die "签名缺少安全时间戳"
    grep -E '^(Authority|TeamIdentifier|Timestamp)=' <<<"$SIGN_INFO" | head -n 5
fi

# ---------- 2. 公证 .app 并 staple（离线首启也能通过 Gatekeeper） ----------

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    "$SCRIPTS/notarize.sh" "$APP_PATH"
else
    warn "已跳过 .app 公证"
fi

# ---------- 3. DMG（放入已 staple 的 .app）→ 签名 → 公证 → staple ----------

"$SCRIPTS/make-dmg.sh" "$APP_PATH"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    "$SCRIPTS/notarize.sh" "$DIST_DIR/$DMG_NAME"
else
    warn "已跳过 DMG 公证"
fi

# ---------- 4. zip（Homebrew / 更新检查备用）与校验和 ----------

log "生成 $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"

log "生成 SHA256SUMS.txt"
(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" "$ZIP_NAME" >SHA256SUMS.txt)

# ---------- 5. 发布说明（取自 CHANGELOG.md 对应版本段落） ----------

NOTES_FILE="$DIST_DIR/NOTES.md"
if ! CHANGES="$("$SCRIPTS/changelog-notes.sh" "$VERSION" 2>/dev/null)"; then
    warn "CHANGELOG.md 中没有 [$VERSION] 段落，NOTES.md 使用占位内容，请在发布前手动补充"
    CHANGES="Release $VERSION. See [CHANGELOG.md](CHANGELOG.md) for details."
fi
{
    printf '%s\n\n' "$CHANGES"
    printf '### SHA-256\n\n```\n'
    cat "$DIST_DIR/SHA256SUMS.txt"
    printf '```\n'
} >"$NOTES_FILE"

# ---------- 汇总 ----------

log "产物："
(cd "$DIST_DIR" && ls -lh)
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    warn "本次为演练（未公证），dist/ 中的产物不可对外分发"
fi
