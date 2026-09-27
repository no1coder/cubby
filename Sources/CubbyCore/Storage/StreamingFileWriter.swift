import Darwin
import Foundation

/// 流式原子写入私有文件：内容分块写进同目录下的临时文件，写完并 fsync 后以 rename(2) 原子替换目标文件。
///
/// 与 `PrivateFiles.write`（`Data.write(options: .atomic)` 后收紧为 0600）语义一致，且更严格：
/// - 临时文件以 O_EXCL 新建，创建时即为 0600（再用 fchmod 排除 umask 的影响），任何时刻都不会以更宽的权限存在；
/// - 替换后目标路径指向这个新 inode，旧文件遗留的宽松权限（如 0644）随之消失；
/// - 任何一步失败都会删除临时文件并抛出错误，目标文件保持原样。
///
/// 目标文件只会被整体替换、从不就地改写，读取端（JSONHistoryStorage）据此可以安全地内存映射读取。
enum StreamingFileWriter {
    /// - Parameter produce: 通过传入的 write 闭包按顺序写出各块内容；抛出错误即放弃本次写入
    static func write(to url: URL, _ produce: (_ write: (Data) throws -> Void) throws -> Void) throws {
        let temporary = temporaryURL(for: url)
        let permissions = mode_t(PrivateFiles.filePermissions)
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, permissions)
        guard descriptor >= 0 else { throw lastPOSIXError() }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var isOpen = true
        do {
            guard fchmod(descriptor, permissions) == 0 else { throw lastPOSIXError() }
            try produce { try handle.write(contentsOf: $0) }
            // 先落盘再替换：避免异常断电后目标路径指向尚未写完的新文件
            try handle.synchronize()
            isOpen = false
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw lastPOSIXError() }
        } catch {
            if isOpen { try? handle.close() }
            unlink(temporary.path)
            throw error
        }
    }

    /// 同目录下的隐藏临时文件（同一卷上 rename 才是原子的），随机后缀避免并发写入互相覆盖
    static func temporaryURL(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("\(temporaryPrefix(for: url))\(UUID().uuidString)\(temporarySuffix)")
    }

    /// 写入中途进程被杀时遗留的临时文件（含完整的历史内容）没有人会再引用，这里清理掉。
    /// 只匹配本类型生成的「.<文件名>.<UUID>.tmp」，并跳过 staleAge 内修改过的文件，不会误删正在进行的写入。
    /// 尽力而为：列目录或删除失败时保持原样，不影响读取
    static func removeStaleTemporaryFiles(for url: URL, olderThan staleAge: TimeInterval = 60, now: Date = Date()) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let prefix = temporaryPrefix(for: url)
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(temporarySuffix) {
            let token = name.dropFirst(prefix.count).dropLast(temporarySuffix.count)
            let candidate = directory.appendingPathComponent(name)
            guard UUID(uuidString: String(token)) != nil,
                let modified = try? fileManager.attributesOfItem(atPath: candidate.path)[.modificationDate] as? Date,
                now.timeIntervalSince(modified) > staleAge
            else { continue }
            try? fileManager.removeItem(at: candidate)
        }
    }

    private static let temporarySuffix = ".tmp"

    private static func temporaryPrefix(for url: URL) -> String {
        ".\(url.lastPathComponent)."
    }

    private static func lastPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
