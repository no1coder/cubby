# shellcheck shell=bash
# 发布脚本共用函数（由其他脚本 source，不单独执行）
#
# 提供：日志输出、版本号读取与校验、签名身份识别。

# 仓库根目录（本文件位于 scripts/lib/，按自身路径推算，与调用方位置无关）
CUBBY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CUBBY_ROOT

readonly CUBBY_APP_NAME="Cubby"
readonly CUBBY_DEFAULT_BUNDLE_ID="io.github.no1coder.Cubby"
# SemVer：X.Y.Z，可带 -beta.N 之类的预发布后缀
readonly CUBBY_SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'

log() { printf '==> %s\n' "$*"; }
warn() { printf '警告：%s\n' "$*" >&2; }
die() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

# 读取仓库根目录 VERSION 文件（版本号单一来源），校验 SemVer 格式后输出
read_version() {
    local file="$CUBBY_ROOT/VERSION"
    [[ -f "$file" ]] || die "缺少 $file"
    local version
    version="$(tr -d '[:space:]' <"$file")"
    [[ "$version" =~ $CUBBY_SEMVER_REGEX ]] || die "VERSION 内容不是合法的 SemVer：'$version'"
    # 环境变量 VERSION（如 make release VERSION=x.y.z 或 CI 从 tag 解析）只用于核对，不能覆盖文件
    if [[ -n "${VERSION:-}" && "${VERSION#v}" != "$version" ]]; then
        die "环境变量 VERSION=$VERSION 与 VERSION 文件（$version）不一致；版本号以 VERSION 文件为准"
    fi
    printf '%s\n' "$version"
}

# 判断签名身份类型：adhoc | developer-id | development
# 身份既可以是证书名称，也可以是 security find-identity 输出的 SHA-1 指纹
identity_kind() {
    local identity="$1"
    if [[ "$identity" == "-" ]]; then
        echo adhoc
        return
    fi
    if [[ "$identity" == "Developer ID Application"* ]]; then
        echo developer-id
        return
    fi
    local line
    line="$(security find-identity -v -p codesigning 2>/dev/null | grep -F -- "$identity" | head -n 1 || true)"
    if [[ "$line" == *"Developer ID Application"* ]]; then
        echo developer-id
    else
        echo development
    fi
}

# 在钥匙串搜索列表中查找第一个匹配前缀的代码签名身份（找不到输出空串）
find_identity() {
    local prefix="$1"
    security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' -v prefix="$prefix" 'index($2, prefix) == 1 { print $2; exit }'
}
