#!/usr/bin/env bash
# E3b 构建检查：DEBUG 专用的测试密钥来源（CUBBY_TEST_HISTORY_KEY、DebugHistoryKey）不得出现在 Release 二进制中，
# 否则任何人设置一个环境变量就能让正式版改用已知密钥（后门）。
# 用法：scripts/check-release-test-key.sh [Release 可执行文件]，默认先 swift build -c release 再检查 .build/release/Cubby
set -euo pipefail

binary="${1:-}"
if [[ -z "$binary" ]]; then
    swift build -c release --product Cubby >/dev/null
    binary="$(swift build -c release --show-bin-path)/Cubby"
fi

if [[ ! -f "$binary" ]]; then
    echo "error: binary not found: $binary" >&2
    exit 1
fi

# 先取出全部字符串再匹配：直接 `strings | grep -q` 时 grep 提前退出，strings 收到 SIGPIPE，
# 在 pipefail 下整条管道算失败，检查会被悄悄跳过
contents="$(strings -a "$binary")"
for needle in CUBBY_TEST_HISTORY_KEY DebugHistoryKey DebugVaultSeed; do
    if grep -qF "$needle" <<<"$contents"; then
        echo "error: release binary contains the DEBUG-only symbol '$needle'" >&2
        exit 1
    fi
done
echo "OK: release binary has no DEBUG-only history key source"
