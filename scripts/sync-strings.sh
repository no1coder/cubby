#!/usr/bin/env bash
# 同步 String Catalog：从 Swift 源码提取本地化字符串，合并进 Resources/Localizable.xcstrings
#
# 用法：
#   ./scripts/sync-strings.sh           提取并写回 catalog：新增源码中的键，源码已删除的键标记为 stale；
#                                       随后列出新增、stale 与缺少翻译的键（仅提示，退出码 0）
#   ./scripts/sync-strings.sh --check   只检查、不写回：catalog 与源码不一致（有新增或 stale 的键）
#                                       或任一语言缺少翻译时以退出码 1 结束，适合 CI
#
# 原理：swift build -emit-localized-strings 为每个编译的源文件生成 .stringsdata，
# 再由 xcrun xcstringstool sync 合并进 catalog（格式与 Xcode 一致）。
# 增量构建只会为重新编译的文件生成 .stringsdata，其余字符串会被误判为 stale，
# 因此每次都在独立的临时构建目录中完整编译一次（不影响 .build）。
#
# 新增文案的流程：源码中写英文键（SwiftUI 字面量或 String(localized:comment:)）→ 运行本脚本 →
# 在 catalog 中补齐下列语言的翻译（英文计数用 plural variations）→ --check 通过。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT_DIR/Resources/Localizable.xcstrings"
# 必须 100% 翻译的语言（源语言 en 的值默认取键本身，无需逐条填写）
REQUIRED_LANGUAGES=(zh-Hans)

MODE="sync"
case "${1:-}" in
    "") ;;
    --check) MODE="check" ;;
    -h | --help)
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "未知参数：$1（用法：$0 [--check]）" >&2
        exit 2
        ;;
esac

[[ -f "$CATALOG" ]] || {
    echo "缺少 $CATALOG" >&2
    exit 1
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cubby-strings.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> 完整编译并提取本地化字符串（临时构建目录，约需半分钟）"
swift build \
    --package-path "$ROOT_DIR" \
    --scratch-path "$WORK_DIR/build" \
    -Xswiftc -emit-localized-strings \
    -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK_DIR/strings" \
    >"$WORK_DIR/build.log" 2>&1 || {
    cat "$WORK_DIR/build.log" >&2
    echo "编译失败，无法提取字符串" >&2
    exit 1
}

shopt -s nullglob
STRINGSDATA=("$WORK_DIR"/strings/*.stringsdata)
shopt -u nullglob
[[ ${#STRINGSDATA[@]} -gt 0 ]] || {
    echo "没有生成 .stringsdata，请确认 Swift 工具链支持 -emit-localized-strings" >&2
    exit 1
}

# 保留合并前的版本，用于找出新增的键
cp "$CATALOG" "$WORK_DIR/original.xcstrings"

# sync 按文件名匹配字符串表（Localizable），因此检查模式下的副本必须保持同名
SYNCED="$CATALOG"
if [[ "$MODE" == "check" ]]; then
    SYNCED="$WORK_DIR/Localizable.xcstrings"
    cp "$CATALOG" "$SYNCED"
fi

echo "==> 合并到 $(basename "$CATALOG")（${#STRINGSDATA[@]} 个源文件）"
# 同一个键在多处使用、注释不同时 xcstringstool 会逐条提示，属正常情况，不输出
xcrun xcstringstool sync "$SYNCED" --stringsdata "${STRINGSDATA[@]}" 2>&1 \
    | grep -v 'used with multiple comments' || true

# 与原 catalog 对比并检查翻译覆盖率；有问题时退出码为 1
set +e
swift - "$SYNCED" "$WORK_DIR/original.xcstrings" "${REQUIRED_LANGUAGES[@]}" <<'SWIFT'
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let syncedURL = URL(fileURLWithPath: arguments[0])
let originalURL = URL(fileURLWithPath: arguments[1])
let languages = Array(arguments.dropFirst(2))

func strings(at url: URL) -> [String: [String: Any]] {
    guard let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = root["strings"] as? [String: [String: Any]]
    else { return [:] }
    return strings
}

let synced = strings(at: syncedURL)
let original = strings(at: originalURL)

let added = synced.keys.filter { original[$0] == nil }.sorted()
let stale = synced.filter { $0.value["extractionState"] as? String == "stale" }.map(\.key).sorted()
var missing: [String: [String]] = [:]
for (key, entry) in synced where entry["shouldTranslate"] as? Bool != false {
    let localizations = entry["localizations"] as? [String: Any] ?? [:]
    for language in languages where localizations[language] == nil {
        missing[language, default: []].append(key)
    }
}

func report(_ title: String, _ keys: [String]) {
    guard !keys.isEmpty else { return }
    print("\(title)（\(keys.count)）：")
    keys.forEach { print("  - \($0)") }
}

report("源码中新增、catalog 尚未收录的键", added)
report("源码中已不存在的键（stale，请确认后删除）", stale)
for language in languages {
    report("缺少 \(language) 翻译的键", (missing[language] ?? []).sorted())
}

let hasIssues = !added.isEmpty || !stale.isEmpty || !missing.isEmpty
if !hasIssues {
    let counts = languages.map { "\($0) 100%" }.joined(separator: "，")
    print("catalog 与源码一致：共 \(synced.count) 条，\(counts)")
}
exit(hasIssues ? 1 : 0)
SWIFT
STATUS=$?
set -e

if [[ "$MODE" == "check" ]]; then
    [[ $STATUS -eq 0 ]] || echo "String Catalog 未同步：请运行 ./scripts/sync-strings.sh 并补齐翻译" >&2
    exit "$STATUS"
fi
[[ $STATUS -eq 0 ]] || echo "已写回 catalog，请处理以上各项后再提交"
exit 0
