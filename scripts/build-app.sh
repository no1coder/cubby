#!/usr/bin/env bash
# 构建 Release 版本（arm64 + x86_64 通用二进制）并打包为 build/Cubby.app
#
# 用法：./scripts/build-app.sh            （或 make app）
#
# 环境变量（均可选）：
#   SIGN_IDENTITY  签名身份（证书名称或 SHA-1 指纹）。未设置时自动选用钥匙串中第一个
#                  "Apple Development" 证书，找不到则回退为 "-"（ad-hoc 临时签名）。
#                  使用 "Developer ID Application" 证书时自动启用安全时间戳（公证必需）。
#   TIMESTAMP      时间戳策略：auto（默认，按身份类型决定）| secure | none
#   BUNDLE_ID      覆盖 CFBundleIdentifier，默认 io.github.no1coder.Cubby；
#                  开发版可用 io.github.no1coder.Cubby.dev 与正式版共存（授权、偏好互不影响）。
#   BUILD_NUMBER   写入 CFBundleVersion，默认 git rev-list --count HEAD，非 git 仓库时为 1。
#
# 版本号：CFBundleShortVersionString 取自仓库根目录 VERSION 文件（单一来源）；
#         源 Resources/Info.plist 中的版本号只供开发构建显示，与 VERSION 不一致时给出警告。
# 注意：辅助功能权限与签名绑定，使用固定证书签名可避免每次重新构建后都要重新授权。
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

BUILD_DIR="$CUBBY_ROOT/build"
APP_DIR="$BUILD_DIR/$CUBBY_APP_NAME.app"
PLIST="$APP_DIR/Contents/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
# 应用内「使用说明」窗口读取的文档（界面为简体中文时读 zh-Hans 版）
USER_GUIDES=(USER-GUIDE.md USER-GUIDE.zh-Hans.md)

cd "$CUBBY_ROOT"

# ---------- 版本信息、签名身份与参数校验 ----------

VERSION="$(read_version)"
# 防呆：源 Info.plist 的版本号应与 VERSION 同步（产物以 VERSION 为准，这里只提醒）
SOURCE_VERSION="$("$PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$CUBBY_ROOT/Resources/Info.plist" 2>/dev/null || true)"
if [[ "$SOURCE_VERSION" != "${VERSION%%-*}" ]]; then
    warn "Resources/Info.plist 的版本号（${SOURCE_VERSION:-缺失}）与 VERSION（$VERSION）不一致；产物以 VERSION 为准，请同步源文件"
fi
BUNDLE_ID="${BUNDLE_ID:-$CUBBY_DEFAULT_BUNDLE_ID}"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || die "BUNDLE_ID 只能包含字母、数字、点与连字符：'$BUNDLE_ID'"

default_build_number() {
    if git -C "$CUBBY_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$CUBBY_ROOT" rev-list --count HEAD 2>/dev/null || echo 1
    else
        echo 1
    fi
}
BUILD_NUMBER="${BUILD_NUMBER:-$(default_build_number)}"
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || die "BUILD_NUMBER 必须是数字（可含最多两个点）：'$BUILD_NUMBER'"

for guide in "${USER_GUIDES[@]}"; do
    [[ -f "$CUBBY_ROOT/docs/$guide" ]] || die "缺少 docs/$guide（应用内使用说明）"
done

# 签名身份与时间戳策略（先于编译确定，参数有误时尽早失败）
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(find_identity "Apple Development")"
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi
KIND="$(identity_kind "$SIGN_IDENTITY")"

TIMESTAMP_MODE="${TIMESTAMP:-auto}"
if [[ "$TIMESTAMP_MODE" == auto ]]; then
    # Developer ID 需要 Apple 安全时间戳；开发证书与 ad-hoc 跳过，避免依赖网络
    if [[ "$KIND" == developer-id ]]; then TIMESTAMP_MODE=secure; else TIMESTAMP_MODE=none; fi
fi
case "$TIMESTAMP_MODE" in
    secure) TIMESTAMP_FLAG="--timestamp" ;;
    none) TIMESTAMP_FLAG="--timestamp=none" ;;
    *) die "TIMESTAMP 只能是 auto / secure / none：'${TIMESTAMP}'" ;;
esac

# ---------- 编译 ----------

log "编译 Release（arm64 + x86_64）"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

# ---------- 组装 .app ----------

log "组装 $CUBBY_APP_NAME.app（版本 $VERSION，构建号 $BUILD_NUMBER，$BUNDLE_ID）"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$CUBBY_APP_NAME" "$APP_DIR/Contents/MacOS/$CUBBY_APP_NAME"
cp "$CUBBY_ROOT/Resources/Info.plist" "$PLIST"

# 只修改拷贝后的 Info.plist，源文件保持不变
# CFBundleShortVersionString 只允许数字点分形式：预发布后缀（如 -beta.1）不写入
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString ${VERSION%%-*}" "$PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
"$PLIST_BUDDY" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
plutil -lint "$PLIST" >/dev/null

# 应用图标（由 scripts/make-icon.swift 生成）
ICON_FILE="$CUBBY_ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON_FILE" ]]; then
    log "生成应用图标"
    swift "$CUBBY_ROOT/scripts/make-icon.swift"
fi
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"

# 使用说明（开头已确认存在）
for guide in "${USER_GUIDES[@]}"; do
    cp "$CUBBY_ROOT/docs/$guide" "$APP_DIR/Contents/Resources/$guide"
done

# 本地化字符串：String Catalog 不作为 SPM 资源，直接编译进 .app 的 Resources（*.lproj）
# （如 Localizable.xcstrings；文件不存在时跳过。兼容 macOS 自带的 bash 3.2）
while IFS= read -r -d '' catalog; do
    log "编译本地化字符串 $(basename "$catalog")"
    xcrun xcstringstool compile "$catalog" -o "$APP_DIR/Contents/Resources"
done < <(find "$CUBBY_ROOT/Resources" -maxdepth 1 -name '*.xcstrings' -print0)

# ---------- 签名 ----------

# 统一启用 Hardened Runtime（公证必需；无需 entitlements：非沙盒、无 JIT / Apple Events）。
# 日后引入嵌套代码（如 Sparkle.framework）时须由内到外逐个签名，禁止使用 --deep 签名。
log "签名（${SIGN_IDENTITY}，${KIND}，${TIMESTAMP_FLAG}）"
codesign --force --options runtime "$TIMESTAMP_FLAG" --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

log "完成：$APP_DIR"
