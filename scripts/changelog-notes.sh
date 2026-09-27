#!/usr/bin/env bash
# 从 CHANGELOG.md（Keep a Changelog 格式）中提取指定版本的段落，输出到标准输出
#
# 用法：./scripts/changelog-notes.sh <版本> [CHANGELOG 路径]
#   例：./scripts/changelog-notes.sh 0.2.0 > dist/NOTES.md
#
# 匹配标题 "## [0.2.0] - YYYY-MM-DD"，截止到下一个 "## [" 标题或文末的链接定义。
# 退出码：0 成功；2 CHANGELOG 缺失；3 找不到该版本或段落为空；64 参数错误。
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || {
    echo "用法：$0 <版本> [CHANGELOG 路径]" >&2
    exit 64
}
VERSION="$1"
CHANGELOG="${2:-$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md}"

if [[ ! -f "$CHANGELOG" ]]; then
    echo "找不到 $CHANGELOG" >&2
    exit 2
fi

NOTES="$(awk -v header="## [$VERSION]" '
    # 精确匹配版本标题（"## [0.2.0]" 不会误中 "## [0.2.0-beta.1]"）
    index($0, header) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && /^\[[^]]+\]: / { exit }
    found { print }
' "$CHANGELOG" | awk '
    # 去掉首尾空行
    NF { started = 1; for (i = 0; i < blank; i++) print ""; blank = 0; print; next }
    started { blank++ }
')"

if [[ -z "$NOTES" ]]; then
    echo "$CHANGELOG 中没有版本 [$VERSION] 的段落（或段落为空）" >&2
    exit 3
fi
printf '%s\n' "$NOTES"
