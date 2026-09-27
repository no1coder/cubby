#!/usr/bin/env bash
# 将 build/Cubby.app 打包为 dist/Cubby-<版本>.dmg：卷标 Cubby，内含 Cubby.app 与「应用程序」快捷方式，
# 打开后是带背景图的安装窗口（左 Cubby → 右「应用程序」），卷图标为应用图标
#
# 用法：./scripts/make-dmg.sh [App 路径]      （或 make dmg；默认 build/Cubby.app）
#       ./scripts/make-dmg.sh --prepare       只安装 dmgbuild（CI 在导入签名凭据前调用，网络问题尽早失败）
#
# 窗口外观由 dmgbuild（版本与哈希固定在 packaging/dmg/requirements.txt）直接写入 .DS_Store，
# 不经过 Finder / AppleScript，CI 无界面环境也能运行。首次运行时在 build/dmgbuild-venv 创建
# Python 虚拟环境并从 PyPI 安装（需联网）；requirements.txt 不变时直接复用。
# 外观配置：packaging/dmg/settings.py、layout.json；背景图由 scripts/make-dmg-background.swift 生成。
#
# 环境变量（可选）：
#   SIGN_IDENTITY    为 Developer ID Application 身份时对 DMG 签名（带安全时间戳）；
#                    ad-hoc / 开发证书 / 未设置时不签名 DMG（DMG 签名仅对公证分发有意义）。
#   DMGBUILD_PYTHON  创建虚拟环境用的 Python 解释器（需 ≥ 3.10），默认 python3
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

DMG_ASSETS="$CUBBY_ROOT/packaging/dmg"
REQUIREMENTS="$DMG_ASSETS/requirements.txt"
VENV_DIR="$CUBBY_ROOT/build/dmgbuild-venv"

# 在 build/dmgbuild-venv 中安装固定版本的 dmgbuild（逐个校验哈希、只装 wheel、不解析依赖）
ensure_dmgbuild() {
    local stamp="$VENV_DIR/.requirements.sha256"
    local wanted
    wanted="$(shasum -a 256 "$REQUIREMENTS" | cut -d ' ' -f 1)"
    if [[ "$(cat "$stamp" 2>/dev/null || true)" == "$wanted" ]] \
        && "$VENV_DIR/bin/python" -c 'import dmgbuild' >/dev/null 2>&1; then
        return
    fi

    local python="${DMGBUILD_PYTHON:-python3}"
    command -v "$python" >/dev/null || die "找不到 $python；dmgbuild 需要 Python ≥ 3.10（brew install python，或设置 DMGBUILD_PYTHON）"
    "$python" -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
        || die "dmgbuild 需要 Python ≥ 3.10，当前 $python 为 $("$python" --version 2>&1)；可设置 DMGBUILD_PYTHON 指定解释器"

    log "安装 dmgbuild 到 ${VENV_DIR#"$CUBBY_ROOT"/}"
    rm -rf "$VENV_DIR"
    mkdir -p "$(dirname "$VENV_DIR")"
    "$python" -m venv "$VENV_DIR"
    "$VENV_DIR/bin/python" -m pip install --quiet --disable-pip-version-check --no-input \
        --require-hashes --only-binary :all: --no-deps -r "$REQUIREMENTS"
    printf '%s\n' "$wanted" >"$stamp"
}

if [[ "${1:-}" == "--prepare" ]]; then
    ensure_dmgbuild
    log "dmgbuild 已就绪：${VENV_DIR#"$CUBBY_ROOT"/}"
    exit 0
fi

VERSION="$(read_version)"
APP_PATH="${1:-$CUBBY_ROOT/build/$CUBBY_APP_NAME.app}"
DIST_DIR="$CUBBY_ROOT/dist"
DMG_PATH="$DIST_DIR/$CUBBY_APP_NAME-$VERSION.dmg"
VOLUME_NAME="$CUBBY_APP_NAME"

[[ -d "$APP_PATH" ]] || die "找不到 $APP_PATH，请先运行 ./scripts/build-app.sh"
APP_PATH="$(cd "$APP_PATH" && pwd)"
for tool in hdiutil iconutil; do
    command -v "$tool" >/dev/null || die "需要 macOS 自带的 $tool"
done
for asset in settings.py layout.json requirements.txt background.png background@2x.png; do
    [[ -f "$DMG_ASSETS/$asset" ]] || die "缺少 packaging/dmg/$asset"
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-dmg.XXXXXX")"
MOUNT_DIR=""
cleanup() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ensure_dmgbuild

# 卷图标：取 .app 内的图标，去掉 1024px 版本（卷图标用不到，可让 DMG 小约 0.5 MB）
log "准备卷图标"
APP_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
[[ -f "$APP_ICON" ]] || APP_ICON="$CUBBY_ROOT/Resources/AppIcon.icns"
iconutil -c iconset -o "$WORK_DIR/VolumeIcon.iconset" "$APP_ICON"
rm -f "$WORK_DIR/VolumeIcon.iconset/icon_512x512@2x.png"
iconutil -c icns -o "$WORK_DIR/VolumeIcon.icns" "$WORK_DIR/VolumeIcon.iconset"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
# 已挂载同名卷时，dmgbuild 的临时卷会挂到「/Volumes/Cubby 1」，写进 .DS_Store 的背景图别名可能解析失败
if [[ -e "/Volumes/$VOLUME_NAME" ]]; then
    warn "已挂载名为 $VOLUME_NAME 的卷，建议先推出再打包，否则安装窗口的背景图可能不显示"
fi

# dmgbuild：创建可写映像 → 拷入 .app（ditto，保留签名与 staple 票据）、快捷方式、背景与卷图标
#           → 写 .DS_Store → 转换为 ULFO（HFS+，LZFSE 压缩）
# GitHub macOS runner 上 hdiutil 偶发 "Resource busy"，失败时整体重试
log "生成 $DMG_PATH"
for attempt in 1 2 3; do
    if "$VENV_DIR/bin/dmgbuild" -s "$DMG_ASSETS/settings.py" \
        -D app="$APP_PATH" \
        -D app_name="$CUBBY_APP_NAME.app" \
        -D background="$DMG_ASSETS/background.png" \
        -D volume_icon="$WORK_DIR/VolumeIcon.icns" \
        -D layout="$DMG_ASSETS/layout.json" \
        "$VOLUME_NAME" "$DMG_PATH"; then
        break
    fi
    [[ "$attempt" -lt 3 ]] || die "dmgbuild 连续失败 3 次"
    warn "dmgbuild 失败，第 $attempt 次重试…"
    rm -f "$DMG_PATH"
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

# 挂载检查内容：Cubby.app（签名有效）、指向 /Applications 的符号链接，以及窗口外观所需的隐藏文件
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-mount.XXXXXX")"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" -quiet
[[ -d "$MOUNT_DIR/$CUBBY_APP_NAME.app" ]] || die "DMG 中缺少 $CUBBY_APP_NAME.app"
[[ "$(readlink "$MOUNT_DIR/Applications")" == "/Applications" ]] || die "DMG 中缺少 Applications 快捷方式"
for hidden in .DS_Store .background.tiff .VolumeIcon.icns; do
    [[ -f "$MOUNT_DIR/$hidden" ]] || die "DMG 中缺少 $hidden（安装窗口外观）"
done
# 卷根目录须带「自定义图标」标记（FinderInfo 第 9–10 字节 finderFlags 的 kHasCustomIcon = 0x0400），
# 否则 Finder 不显示卷图标；该标记由 dmgbuild 调用 SetFile（Xcode 命令行工具）设置
FINDER_FLAGS="$(xattr -px com.apple.FinderInfo "$MOUNT_DIR" 2>/dev/null | tr -d ' \n' | cut -c 17-20 || true)"
((16#${FINDER_FLAGS:-0} & 0x0400)) || die "卷图标未生效：卷根目录缺少自定义图标标记（SetFile 是否可用？）"
codesign --verify --strict "$MOUNT_DIR/$CUBBY_APP_NAME.app" || die "DMG 内的 $CUBBY_APP_NAME.app 签名校验失败"
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR" 2>/dev/null || true
MOUNT_DIR=""

log "完成：$DMG_PATH（$(du -h "$DMG_PATH" | cut -f1)）"
