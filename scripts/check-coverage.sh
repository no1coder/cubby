#!/usr/bin/env bash
# 覆盖率门槛：运行 swift test --enable-code-coverage，统计 CubbyCore 源文件的行覆盖率
#
# 用法：./scripts/check-coverage.sh [--skip-tests]      （或 make coverage）
#   --skip-tests  不重新运行测试，直接使用上一次 swift test --enable-code-coverage 的数据
#
# 环境变量：
#   COVERAGE_MIN     行覆盖率下限（百分比），默认 95
#   COVERAGE_TARGET  统计范围（相对仓库根目录），默认 Sources/CubbyCore
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

COVERAGE_MIN="${COVERAGE_MIN:-95}"
COVERAGE_TARGET="${COVERAGE_TARGET:-Sources/CubbyCore}"
[[ "$COVERAGE_MIN" =~ ^[0-9]+(\.[0-9]+)?$ ]] || {
    echo "错误：COVERAGE_MIN 必须是数字：'$COVERAGE_MIN'" >&2
    exit 64
}

case "${1:-}" in
    "") swift test --enable-code-coverage ;;
    --skip-tests) ;;
    *)
        echo "用法：$0 [--skip-tests]" >&2
        exit 64
        ;;
esac

# swift test --show-codecov-path 给出合并后的 JSON，profdata 与其位于同一目录
CODECOV_JSON="$(swift test --show-codecov-path)"
PROFDATA="$(dirname "$CODECOV_JSON")/default.profdata"
BIN_PATH="$(swift build --show-bin-path)"
TEST_BUNDLE="$(find "$BIN_PATH" -maxdepth 1 -name '*PackageTests.xctest' | head -n 1)"
TEST_BINARY="$TEST_BUNDLE/Contents/MacOS/$(basename "$TEST_BUNDLE" .xctest)"

[[ -f "$PROFDATA" ]] || {
    echo "错误：找不到 $PROFDATA，请先运行 swift test --enable-code-coverage" >&2
    exit 1
}
[[ -f "$TEST_BINARY" ]] || {
    echo "错误：找不到测试二进制 $TEST_BINARY" >&2
    exit 1
}

REPORT="$(xcrun llvm-cov report "$TEST_BINARY" -instr-profile "$PROFDATA" "$ROOT_DIR/$COVERAGE_TARGET")"
printf '%s\n' "$REPORT"

# TOTAL 行：Filename Regions Missed Cover Functions Missed Executed Lines Missed Cover …
# 用 Lines 与 Missed Lines 两列自行计算，避免依赖是否输出分支覆盖列
read -r TOTAL_LINES MISSED_LINES < <(printf '%s\n' "$REPORT" | awk '$1 == "TOTAL" { print $8, $9 }') || true
[[ -n "${TOTAL_LINES:-}" && "$TOTAL_LINES" -gt 0 ]] || {
    echo "错误：未能从 llvm-cov 报告中解析 TOTAL 行" >&2
    exit 1
}

COVERAGE="$(awk -v total="$TOTAL_LINES" -v missed="$MISSED_LINES" 'BEGIN { printf "%.2f", (total - missed) * 100 / total }')"
echo
echo "$COVERAGE_TARGET 行覆盖率：$COVERAGE%（门槛 $COVERAGE_MIN%，共 $TOTAL_LINES 行，未覆盖 $MISSED_LINES 行）"

if awk -v cov="$COVERAGE" -v min="$COVERAGE_MIN" 'BEGIN { exit !(cov + 0 < min + 0) }'; then
    echo "覆盖率低于门槛 $COVERAGE_MIN%" >&2
    exit 1
fi
echo "覆盖率达标"
