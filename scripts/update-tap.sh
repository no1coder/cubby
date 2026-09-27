#!/usr/bin/env bash
# 根据 packaging/homebrew/cubby.rb 模板生成 Homebrew cask，并（可选）推送到 tap 仓库
#
# 用法：
#   ./scripts/update-tap.sh <版本> <dmg-sha256> [--output <文件>]
#       本地模式：渲染 cask 到文件（默认 dist/cubby.rb；"-" 表示标准输出）
#   ./scripts/update-tap.sh <版本> <dmg-sha256> --push
#       CI 模式：克隆 tap 仓库 → 写入 Casks/cubby.rb → brew style → 提交 "cubby <版本>" 并推送
#
# CI 模式环境变量：
#   TAP_GITHUB_TOKEN  必需。细粒度 PAT，仅授权 tap 仓库 Contents: Read and write
#   TAP_REPO          默认 no1coder/homebrew-tap
#   TAP_BRANCH        默认 main
#   TAP_DRY_RUN=1     只在本地提交、不推送（调试用）
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

TEMPLATE="$CUBBY_ROOT/packaging/homebrew/cubby.rb"
CASK_PATH_IN_TAP="Casks/cubby.rb"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------- 参数 ----------

POSITIONAL=()
MODE=local
OUTPUT="$CUBBY_ROOT/dist/cubby.rb"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --push) MODE=push ;;
        --output)
            [[ $# -ge 2 ]] || die "--output 需要文件路径"
            OUTPUT="$2"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*) die "未知参数：$1（见 --help）" ;;
        *) POSITIONAL+=("$1") ;;
    esac
    shift
done
[[ ${#POSITIONAL[@]} -eq 2 ]] || die "需要 <版本> 与 <dmg-sha256> 两个参数（见 --help）"

VERSION="${POSITIONAL[0]#v}"
SHA256="$(tr '[:upper:]' '[:lower:]' <<<"${POSITIONAL[1]}")"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "版本号必须是正式版 X.Y.Z（预发布版本不进入 tap）：'$VERSION'"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || die "sha256 必须是 64 位十六进制：'$SHA256'"
[[ -f "$TEMPLATE" ]] || die "找不到模板 $TEMPLATE"

render_cask() {
    local rendered
    rendered="$(sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{SHA256}}/$SHA256/g" "$TEMPLATE")"
    if grep -q '{{' <<<"$rendered"; then
        die "模板中仍有未替换的占位符"
    fi
    printf '%s\n' "$rendered"
}

# ---------- 本地模式 ----------

if [[ "$MODE" == local ]]; then
    if [[ "$OUTPUT" == "-" ]]; then
        render_cask
    else
        mkdir -p "$(dirname "$OUTPUT")"
        render_cask >"$OUTPUT"
        log "已生成 $OUTPUT（复制到 tap 仓库的 $CASK_PATH_IN_TAP 后提交即可）"
    fi
    exit 0
fi

# ---------- CI 模式：克隆 tap、提交并推送 ----------

[[ -n "${TAP_GITHUB_TOKEN:-}" ]] || die "--push 需要环境变量 TAP_GITHUB_TOKEN"
TAP_REPO="${TAP_REPO:-no1coder/homebrew-tap}"
TAP_BRANCH="${TAP_BRANCH:-main}"
[[ "$TAP_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "TAP_REPO 格式应为 owner/repo：'$TAP_REPO'"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-tap.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
TAP_DIR="$WORK_DIR/tap"

# 令牌通过 GIT_CONFIG_* 环境变量临时注入（git ≥ 2.31），不写入 URL、.git/config 或进程参数，
# 避免出现在日志、磁盘与 ps 输出中
AUTH_B64="$(printf 'x-access-token:%s' "$TAP_GITHUB_TOKEN" | base64 | tr -d '\n')"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::add-mask::$AUTH_B64"
fi
git_auth() {
    GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0="http.https://github.com/.extraheader" \
        GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $AUTH_B64" \
        git "$@"
}

log "克隆 $TAP_REPO（$TAP_BRANCH）"
git_auth clone --quiet --depth 1 --branch "$TAP_BRANCH" "https://github.com/$TAP_REPO.git" "$TAP_DIR"

mkdir -p "$TAP_DIR/$(dirname "$CASK_PATH_IN_TAP")"
render_cask >"$TAP_DIR/$CASK_PATH_IN_TAP"

if command -v brew >/dev/null; then
    log "brew style $CASK_PATH_IN_TAP"
    HOMEBREW_NO_AUTO_UPDATE=1 brew style "$TAP_DIR/$CASK_PATH_IN_TAP"
else
    warn "未安装 Homebrew，跳过 brew style"
fi

cd "$TAP_DIR"
git add "$CASK_PATH_IN_TAP"
if git diff --cached --quiet; then
    log "$CASK_PATH_IN_TAP 已是 $VERSION，无需更新"
    exit 0
fi

git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "cubby $VERSION"

if [[ "${TAP_DRY_RUN:-0}" == 1 ]]; then
    log "TAP_DRY_RUN=1，不推送。待提交内容："
    git show --stat HEAD
    exit 0
fi

log "推送到 $TAP_REPO"
git_auth push --quiet origin "HEAD:$TAP_BRANCH"
log "完成：$TAP_REPO 的 cubby 已更新为 $VERSION"
