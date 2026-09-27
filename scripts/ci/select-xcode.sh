#!/usr/bin/env bash
# CI：选择 Xcode（需要 macOS 26 SDK，PanelChrome.swift 使用了 NSGlassEffectView）
#
# 用法：XCODE_VERSION=26 ./scripts/ci/select-xcode.sh
#   XCODE_VERSION  版本前缀，默认 26；可写精确版本（如 26.6）以固定 swift-format 行为。
#
# macos-26 镜像已预装多个 Xcode（/Applications/Xcode_26.x.app），这里选择匹配前缀的最高版本；
# 若回退到 macos-15 镜像，同样会从已安装的 Xcode 26.x 中选择。
set -euo pipefail

XCODE_VERSION="${XCODE_VERSION:-26}"
[[ "$XCODE_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
    echo "错误：XCODE_VERSION 格式不正确：'$XCODE_VERSION'" >&2
    exit 64
}

CANDIDATE="$(find /Applications -maxdepth 1 -name "Xcode_${XCODE_VERSION}*.app" -type d \
    | grep -E "/Xcode_${XCODE_VERSION//./\\.}(\.[0-9]+)*\.app$" | sort -V | tail -n 1 || true)"

if [[ -n "$CANDIDATE" ]]; then
    echo "==> 选择 $CANDIDATE"
    sudo xcode-select --switch "$CANDIDATE"
elif xcodebuild -version | head -n 1 | grep -Eq "^Xcode ${XCODE_VERSION//./\\.}([. ]|$)"; then
    echo "==> 当前默认 Xcode 已满足 $XCODE_VERSION"
else
    echo "错误：runner 上找不到 Xcode $XCODE_VERSION" >&2
    ls -d /Applications/Xcode*.app >&2 || true
    exit 1
fi

xcodebuild -version
swift --version
