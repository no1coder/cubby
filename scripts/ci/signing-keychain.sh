#!/usr/bin/env bash
# CI：导入 / 清理 Developer ID 签名证书与公证 API Key（仅供 release.yml 使用）
#
# 用法：
#   ./scripts/ci/signing-keychain.sh import    创建临时钥匙串并导入证书，写出 AuthKey.p8
#   ./scripts/ci/signing-keychain.sh cleanup   删除临时钥匙串与所有密钥文件（应在 if: always() 中调用）
#
# import 需要的环境变量（来自 GitHub Environment "release" 的 secrets）：
#   DEVELOPER_ID_P12_BASE64    Developer ID Application 证书 + 私钥（.p12）的 base64
#   DEVELOPER_ID_P12_PASSWORD  导出 .p12 时设置的密码
#   KEYCHAIN_PASSWORD          临时钥匙串密码（留空则运行时随机生成）
#   NOTARY_KEY_P8_BASE64       App Store Connect API Key（AuthKey_<KEYID>.p8）的 base64
#
# import 会向 $GITHUB_ENV 写入 NOTARY_KEY_PATH，供后续步骤的 scripts/notarize.sh 使用。
set -euo pipefail

TEMP_DIR="${RUNNER_TEMP:?仅在 GitHub Actions 中运行（需要 RUNNER_TEMP）}"
KEYCHAIN_PATH="$TEMP_DIR/cubby-signing.keychain-db"
P12_PATH="$TEMP_DIR/cubby-developer-id.p12"
P8_PATH="$TEMP_DIR/AuthKey.p8"

require_env() {
    local name
    for name in "$@"; do
        [[ -n "${!name:-}" ]] || {
            echo "错误：缺少环境变量 $name（请在 GitHub Environment release 中配置同名 secret）" >&2
            exit 1
        }
    done
}

import_signing() {
    require_env DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD NOTARY_KEY_P8_BASE64
    umask 077

    local keychain_password="${KEYCHAIN_PASSWORD:-}"
    if [[ -z "$keychain_password" ]]; then
        keychain_password="$(openssl rand -base64 24)"
        echo "::add-mask::$keychain_password"
    fi

    printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode >"$P12_PATH"
    printf '%s' "$NOTARY_KEY_P8_BASE64" | base64 --decode >"$P8_PATH"

    echo "==> 创建临时钥匙串"
    security create-keychain -p "$keychain_password" "$KEYCHAIN_PATH"
    # 6 小时后自动锁定，足够完成公证
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$keychain_password" "$KEYCHAIN_PATH"

    echo "==> 导入 Developer ID 证书"
    security import "$P12_PATH" -k "$KEYCHAIN_PATH" -f pkcs12 \
        -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
    # 允许 codesign 无交互访问私钥
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "$keychain_password" "$KEYCHAIN_PATH" >/dev/null
    # 加入用户钥匙串搜索列表（保留原有钥匙串）
    local existing=() line
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%\"}"
        existing+=("${line#\"}")
    done < <(security list-keychains -d user)
    security list-keychains -d user -s "$KEYCHAIN_PATH" ${existing[@]+"${existing[@]}"}
    rm -f "$P12_PATH"

    security find-identity -v -p codesigning "$KEYCHAIN_PATH"
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -q "Developer ID Application" || {
        echo "错误：导入的 .p12 中没有 Developer ID Application 身份" >&2
        exit 1
    }

    echo "NOTARY_KEY_PATH=$P8_PATH" >>"${GITHUB_ENV:?}"
}

cleanup_signing() {
    if [[ -f "$KEYCHAIN_PATH" ]]; then
        security delete-keychain "$KEYCHAIN_PATH" || true
    fi
    rm -f "$P12_PATH" "$P8_PATH"
    echo "==> 已删除临时钥匙串与密钥文件"
}

case "${1:-}" in
    import) import_signing ;;
    cleanup) cleanup_signing ;;
    *)
        echo "用法：$0 import|cleanup" >&2
        exit 64
        ;;
esac
