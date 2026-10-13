import Darwin
import Foundation

/// `<数据目录>/.vault.lock` 上的 flock(LOCK_EX) 互斥锁：首次生成密钥、迁移、合并、E8 ② 改名都在锁内进行（E3a），
/// 同一数据目录同时只有一个实例做这些事。锁随文件描述关闭自动释放，进程崩溃也不会遗留。
/// 锁文件放在 Vault 之外：改名保留 Vault 时不会把正被持有的锁一起移走（否则另一实例能锁住新的锁文件）
public struct VaultLock: Sendable {
    static let fileName = ".vault.lock"

    public let url: URL

    public init(dataDirectory: URL) {
        url = dataDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// 阻塞直到取得锁，执行 body 后释放；必要时创建 0700 的数据目录与 0600 的锁文件
    public func withLock<R>(_ body: () throws -> R) throws -> R {
        try PrivateFiles.createDirectory(at: url.deletingLastPathComponent())
        let permissions = mode_t(PrivateFiles.filePermissions)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw Self.lastPOSIXError() }
        defer { close(descriptor) }

        try Self.lockExclusively(descriptor)
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    /// flock 可能被信号打断（EINTR），此时重试
    private static func lockExclusively(_ descriptor: Int32) throws {
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw lastPOSIXError() }
        }
    }

    private static func lastPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
