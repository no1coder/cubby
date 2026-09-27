#!/usr/bin/env bash
# 国际化守卫：Swift 源码的字符串字面量中不允许出现汉字（界面文案应走 String Catalog）
#
# 用法：./scripts/check-no-cjk.sh [目录…]      （默认 Sources）
#
# 规则（ROADMAP §二.1 的 perl 实现）：同一行内引号之后出现汉字即视为违规；
#   - 整行注释（// 或 /// 开头）不检查；
#   - 行尾注释（空白 + // 之后不再含引号的部分）先剥离再检查，避免 `foo("x")  // 中文注释` 误报。
# macOS 自带 grep 不支持 -P，因此用 perl 实现。发现违规时逐行输出并以退出码 1 结束。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -eq 0 ]]; then
    set -- Sources
fi

FINDINGS="$(find "$@" -type f -name '*.swift' -print0 \
    | xargs -0 perl -CSD -ne '
        my $code = $_;
        $code =~ s{\s//[^"]*$}{};
        print "$ARGV:$.: $_" if $code =~ /"[^"]*\p{Han}/ && !m{^\s*//};
        close ARGV if eof')"

if [[ -n "$FINDINGS" ]]; then
    printf '%s\n' "$FINDINGS"
    COUNT="$(printf '%s\n' "$FINDINGS" | wc -l | tr -d ' ')"
    echo "发现 $COUNT 处包含汉字的字符串字面量，请改为英文键并在 Resources/Localizable.xcstrings 中翻译" >&2
    exit 1
fi
echo "未发现包含汉字的字符串字面量"
