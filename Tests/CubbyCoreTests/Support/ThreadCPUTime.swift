import Foundation

/// 当前线程执行 body 消耗的 CPU 时间（用户态 + 内核态），不含等待 CPU、被抢占与等待 I/O 的时间。
///
/// 「按线性时间完成」这类性能断言用它而不用墙钟：CI 上 CPU 繁忙时，同一段代码的墙钟耗时会被拉长数倍
/// （本地以后台 QoS 运行时，500 条历史的写盘从 0.3 s 拉长到 2.7 s），而线程 CPU 时间只反映这段代码自己的
/// 工作量，退化成二次方之类的算法问题照样能抓到。body 必须同步执行、不跨线程
func threadCPUTime<T>(_ body: () throws -> T) rethrows -> (result: T, duration: Duration) {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let result = try body()
    let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    return (result, .nanoseconds(Int64(end - start)))
}
