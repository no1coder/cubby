#!/usr/bin/env bash
# CI：运行测试命令，并保证挂起时能看出挂在哪里
#
# 用法：./scripts/ci/run-tests.sh <命令> [参数…]
#   例：./scripts/ci/run-tests.sh ./scripts/check-coverage.sh
#       ./scripts/ci/run-tests.sh swift test
#
# 环境变量：
#   TEST_IDLE_TIMEOUT  连续多少秒没有新输出即判定为挂起，默认 300
#
# 1. 在伪终端里运行（script -F）：输出逐行到达 CI 日志，而不是按块缓冲——挂起时日志停在真实位置。
#    TERM=dumb 让 SwiftPM 不画进度动画，NO_COLOR 关掉颜色转义。
# 2. 看门狗：套件上的 timeLimit 靠协作线程池里的计时任务触发，线程池被卡死（例如全部线程阻塞在
#    同步 XPC 里）时它也不会触发，测试进程会一声不响地等到 job 超时。这里连续 TEST_IDLE_TIMEOUT 秒
#    没有新输出即判定为挂起：列出已开始、未结束的测试，用 sample 打印测试进程全部线程的调用栈，
#    然后结束测试并以失败退出。
set -euo pipefail

IDLE_TIMEOUT="${TEST_IDLE_TIMEOUT:-300}"
[[ "$IDLE_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || {
    echo "错误：TEST_IDLE_TIMEOUT 必须是正整数（秒）：'$IDLE_TIMEOUT'" >&2
    exit 64
}
[[ $# -gt 0 ]] || {
    echo "用法：$0 <命令> [参数…]" >&2
    exit 64
}

WORK_DIR="$(mktemp -d -t cubby-tests)"
LOG="$WORK_DIR/output.log"
# 承载本包测试的进程（Swift Testing 跑在 swiftpm-testing-helper 里，XCTest 跑在 xctest 里），
# 命令行里带着本包 .build 下的测试包路径，据此只匹配本次运行的进程
TEST_PROCESS_PATTERN="(swiftpm-testing-helper|xctest).*$(pwd -P)/[.]build/"

# 已开始、尚未结束的测试（按 Swift Testing 的控制台输出统计）
print_unfinished_tests() {
    echo "已开始、尚未结束的测试："
    perl -CSD -Mutf8 -ne '
        s/\r//g;
        if (/^◇ Test "(.*)" started\.$/) { $running{$1} = 1 }
        elsif (/^[✔✘➜] Test "(.*?)"(?: with \d+ test cases?)? (?:passed|failed|skipped)/) { delete $running{$1} }
        END { print "  - $_\n" for sort keys %running }' "$LOG" || true
}

# 打印每个测试进程全部线程的调用栈
sample_test_processes() {
    local pids pid
    pids="$(pgrep -f "$TEST_PROCESS_PATTERN" || true)"
    if [[ -z "$pids" ]]; then
        echo "没有找到测试进程"
        return
    fi
    for pid in $pids; do
        echo "::group::sample $pid $(ps -o comm= -p "$pid" || true)"
        if sample "$pid" 5 -file "$WORK_DIR/sample-$pid.txt" > /dev/null 2>&1; then
            cat "$WORK_DIR/sample-$pid.txt"
        else
            echo "（sample 失败）"
        fi
        echo "::endgroup::"
    done
}

stop_tests() {
    pkill -f "$TEST_PROCESS_PATTERN" || true
    kill "$RUNNER" 2> /dev/null || true
    wait "$RUNNER" 2> /dev/null || true
}

TERM=dumb NO_COLOR=1 script -qF "$LOG" "$@" < /dev/null &
RUNNER=$!

while kill -0 "$RUNNER" 2> /dev/null; do
    sleep 5
    [[ -f "$LOG" ]] || continue
    IDLE=$(($(date +%s) - $(stat -f %m "$LOG")))
    if ((IDLE >= IDLE_TIMEOUT)); then
        echo
        echo "::error::测试已 ${IDLE} 秒没有新输出，判定为挂起"
        print_unfinished_tests
        sample_test_processes
        stop_tests
        exit 1
    fi
done

STATUS=0
wait "$RUNNER" || STATUS=$?
exit "$STATUS"
