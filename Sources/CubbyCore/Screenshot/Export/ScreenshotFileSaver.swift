import Darwin
import Foundation
import os

/// 截图写文件：原子写入、默认不覆盖、只在允许时创建目录，并标记为「屏幕截图」。
/// 文件名与去重由调用方决定（ScreenshotFileNaming）；保存目录与是否可创建见 ScreenshotSaveLocation.Destination
public enum ScreenshotFileSaver {
    public enum SaveError: Error, Equatable, Sendable {
        /// 目录不存在（且不允许创建）、无法创建或不是目录
        case directoryUnavailable(URL)
        /// 写入被拒绝（EACCES / EPERM，例如目录只读或被隐私权限拦截）
        case permissionDenied(URL)
        /// 目标文件已存在且未允许覆盖
        case fileExists(URL)
        /// 其他写入失败（磁盘已满等），附 errno 便于日志
        case writeFailed(URL, errno: Int32)

        /// 日志用描述：只含错误种类与 errno，不含路径（路径里有用户名与文件夹名）
        public var logDescription: String {
            switch self {
            case .directoryUnavailable: "directoryUnavailable"
            case .permissionDenied: "permissionDenied"
            case .fileExists: "fileExists"
            case .writeFailed(_, let code): "writeFailed(errno \(code))"
            }
        }

        /// 首选目录层面的问题：换一个目录就可能成功
        var allowsFallback: Bool {
            switch self {
            case .directoryUnavailable, .permissionDenied: true
            case .fileExists, .writeFailed: false
            }
        }
    }

    /// 实际写入的位置；usedFallback 表示首选目录不可用、已改存到备用目录
    public struct Outcome: Equatable, Sendable {
        public let url: URL
        public let usedFallback: Bool
    }

    /// 临时文件名前缀：崩溃留下的残留据此识别并清理
    public static let temporaryPrefix = ".Cubby-screenshot-"
    static let temporarySuffix = ".tmp"
    /// 超过这个时长的同前缀临时文件视为残留（正常写入只存在几毫秒）
    public static let staleTemporaryAge: TimeInterval = 10 * 60
    /// 截图标记：访达与聚焦据此把文件归为「屏幕截图」，与系统截图一致（mdfind kMDItemIsScreenCapture == 1）。
    /// 只写这一项：不写 kMDItemWhereFroms 等来源信息，避免在文件上留下应用或窗口痕迹
    static let screenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    private static let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "Screenshot")

    /// 保存到目标目录：目录不可用或拒绝写入时改存到 fallback（通常为桌面，不自动创建）。
    /// - Parameter fileURL: 由目录得到目标文件 URL（调用方负责命名与去重）
    public static func save(
        _ data: Data,
        to destination: ScreenshotSaveLocation.Destination,
        fallback: URL?,
        now: Date = Date(),
        fileURL: (URL) -> URL
    ) throws(SaveError) -> Outcome {
        let directory = destination.directory
        do {
            let url = try write(
                data, to: fileURL(directory), createsDirectory: destination.createsIfMissing, now: now)
            return Outcome(url: url, usedFallback: false)
        } catch let error where error.allowsFallback {
            guard let fallback, fallback.standardizedFileURL != directory.standardizedFileURL else { throw error }
            logger.error("Screenshot folder unusable (\(error.logDescription, privacy: .public)), falling back")
            return Outcome(url: try write(data, to: fileURL(fallback), now: now), usedFallback: true)
        }
    }

    /// 写入单个文件：先写同目录临时文件，再原子重命名到目标位置（读者永远看不到半个文件）。
    /// overwrite 为 false 时目标已存在（含符号链接）则抛 fileExists；用户在存储面板中确认过替换时传 true
    @discardableResult
    public static func write(
        _ data: Data,
        to fileURL: URL,
        overwrite: Bool = false,
        createsDirectory: Bool = false,
        now: Date = Date()
    ) throws(SaveError) -> URL {
        let directory = fileURL.deletingLastPathComponent()
        try prepareDirectory(directory, creating: createsDirectory)
        removeStaleTemporaryFiles(in: directory, now: now)

        let temporary = directory.appendingPathComponent("\(temporaryPrefix)\(UUID().uuidString)\(temporarySuffix)")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            // 磁盘已满等情况下可能留下半个临时文件
            try? FileManager.default.removeItem(at: temporary)
            let code = posixCode(of: error)
            let denied = isPermissionError(code) || (error as? CocoaError)?.code == .fileWriteNoPermission
            throw denied ? .permissionDenied(fileURL) : .writeFailed(fileURL, errno: code)
        }
        try moveIntoPlace(temporary, to: fileURL, overwrite: overwrite)
        markAsScreenCapture(fileURL)
        return fileURL
    }

    /// 删除目录中同前缀、修改时间早于 staleTemporaryAge 的临时文件（崩溃残留，含截图内容）
    public static func removeStaleTemporaryFiles(in directory: URL, now: Date) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [])
        else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix(temporaryPrefix), name.hasSuffix(temporarySuffix),
                let modified = try? entry.resourceValues(forKeys: Set(keys)).contentModificationDate,
                now.timeIntervalSince(modified) > staleTemporaryAge
            else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    // MARK: - 内部

    /// 目录存在且是目录即可（能否写入交给实际写入判断）；不存在时只在允许时创建
    private static func prepareDirectory(_ directory: URL, creating: Bool) throws(SaveError) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw .directoryUnavailable(directory) }
            return
        }
        guard creating else { throw .directoryUnavailable(directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw isPermissionError(posixCode(of: error))
                ? .permissionDenied(directory) : .directoryUnavailable(directory)
        }
    }

    /// RENAME_EXCL：目标存在时原子地失败，避免「先检查再写」之间被别的进程抢先创建；
    /// rename 不跟随目标处的符号链接（覆盖时替换的是链接本身）
    private static func moveIntoPlace(_ temporary: URL, to destination: URL, overwrite: Bool) throws(SaveError) {
        let result =
            overwrite
            ? rename(temporary.path, destination.path)
            : renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL))
        guard result != 0 else { return }
        let code = errno
        // FAT / exFAT、部分网络卷不支持 RENAME_EXCL：退回「先检查再重命名」（非原子，但仍不覆盖）
        if !overwrite, code == ENOTSUP || code == EINVAL {
            guard (try? FileManager.default.attributesOfItem(atPath: destination.path)) == nil else {
                try? FileManager.default.removeItem(at: temporary)
                throw .fileExists(destination)
            }
            return try moveIntoPlace(temporary, to: destination, overwrite: true)
        }
        try? FileManager.default.removeItem(at: temporary)
        if code == EEXIST { throw .fileExists(destination) }
        throw isPermissionError(code) ? .permissionDenied(destination) : .writeFailed(destination, errno: code)
    }

    /// 设置截图标记（XATTR_NOFOLLOW：路径若被换成符号链接也不会改到别的文件）；
    /// 失败不影响保存结果（只是访达不按截图归类）
    @discardableResult
    static func markAsScreenCapture(_ url: URL) -> Bool {
        guard
            let value = try? PropertyListSerialization.data(fromPropertyList: true, format: .binary, options: 0)
        else { return false }
        let result = value.withUnsafeBytes { buffer in
            setxattr(url.path, screenCaptureAttribute, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
        }
        if result != 0 {
            logger.error("Failed to mark screenshot file: errno \(errno)")
        }
        return result == 0
    }

    private static func isPermissionError(_ code: Int32) -> Bool {
        code == EACCES || code == EPERM
    }

    /// Foundation 文件错误里携带的 POSIX 错误码；取不到时为 0
    private static func posixCode(of error: any Error) -> Int32 {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain { return Int32(truncatingIfNeeded: nsError.code) }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
            underlying.domain == NSPOSIXErrorDomain
        else { return 0 }
        return Int32(truncatingIfNeeded: underlying.code)
    }
}
