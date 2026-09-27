import Foundation

/// 剪贴板历史可能含敏感内容：目录仅本人可访问（0700），文件仅本人可读写（0600）
enum PrivateFiles {
    static let directoryPermissions: Int = 0o700
    static let filePermissions: Int = 0o600

    static func createDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        // 目录已存在时 createDirectory 不会修改权限，这里统一收紧
        try fileManager.setAttributes([.posixPermissions: directoryPermissions], ofItemAtPath: url.path)
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: url.path)
    }
}
