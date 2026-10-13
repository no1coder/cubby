import Darwin
import Foundation

/// 匿名映射（mmap MAP_ANON）的临时缓冲区，析构时立即 munmap 归还给系统（E12）。
///
/// 为什么不用普通 Data：malloc 的大块（如 26MB 的解密后历史）释放后仍以空闲块的形式滞留在进程
/// footprint 中（见 JSONHistoryStorage 中 mappedIfSafe 的说明，实测 +26.5MB）。匿名映射在 munmap 后
/// 页面立即交还，常驻内存不留痕。不可复制，生命周期即作用域。
struct AnonymousBuffer: ~Copyable {
    let byteCount: Int
    /// 映射起始地址；长度为 0 时不映射
    private let base: UnsafeMutableRawPointer?

    init(byteCount: Int) throws(POSIXError) {
        let mapped = try Self.map(byteCount: byteCount)
        self.byteCount = byteCount
        base = mapped
    }

    /// 映射 byteCount 字节的匿名内存（初始全为 0）；长度为 0 时返回 nil
    private static func map(byteCount: Int) throws(POSIXError) -> UnsafeMutableRawPointer? {
        guard byteCount >= 0 else { throw POSIXError(.EINVAL) }
        guard byteCount > 0 else { return nil }
        let mapped = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
        guard let mapped, mapped != MAP_FAILED else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOMEM)
        }
        return mapped
    }

    deinit {
        if let base { munmap(base, byteCount) }
    }

    /// 可写视图，只在闭包内有效
    borrowing func withUnsafeMutableBytes<R, E: Error>(
        _ body: (UnsafeMutableRawBufferPointer) throws(E) -> R
    ) throws(E) -> R {
        try body(UnsafeMutableRawBufferPointer(start: base, count: byteCount))
    }

    /// 前 count 字节的零复制 Data 视图（不负责释放），只在闭包内有效，不得把它保存到闭包之外
    borrowing func withData<R, E: Error>(count: Int, _ body: (Data) throws(E) -> R) throws(E) -> R {
        precondition(count >= 0 && count <= byteCount, "View exceeds the buffer")
        guard let base, count > 0 else { return try body(Data()) }
        return try body(Data(bytesNoCopy: base, count: count, deallocator: .none))
    }
}
