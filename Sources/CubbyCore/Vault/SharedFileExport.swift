import Foundation

/// 必须交出文件路径时的临时明文副本（E9）：`<根目录>/<随机子目录>/<可读文件名>.<扩展名>`，
/// 目录 0700、文件 0600；退出时与下次启动时整个删除（不按时间删，避免「预览」中正在编辑的文件被删）。
/// 这类副本同一用户的其他进程可见（威胁模型第 1 节已如实说明），只在用户主动拖出或「用预览打开」时产生
public struct SharedFileExport: Sendable {
    /// $TMPDIR 下的根目录名
    public static let directoryName = "Cubby-Shared"
    /// 文件名中不允许的字符（路径分隔、访达不接受的冒号、控制字符），替换为空格
    private static let disallowed = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
    private static let maximumNameLength = 120
    private static let fallbackName = "Cubby"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 默认位置：`$TMPDIR/Cubby-Shared`
    public static var temporary: SharedFileExport {
        SharedFileExport(root: FileManager.default.temporaryDirectory.appendingPathComponent(directoryName))
    }

    /// 写出一份副本并返回其地址；每次一个新的随机子目录，同名文件互不覆盖
    public func export(_ data: Data, name: String, fileExtension: String) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateFiles.createDirectory(at: root)
        try PrivateFiles.createDirectory(at: folder)
        let url = folder.appendingPathComponent(Self.fileName(name, fileExtension: fileExtension), isDirectory: false)
        try PrivateFiles.write(data, to: url)
        return url
    }

    /// 删除全部副本（退出时、启动时）；根目录不存在时什么也不做
    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    /// 可读、安全的文件名：去掉路径分隔与控制字符，不以点开头，限制长度
    public static func fileName(_ name: String, fileExtension: String) -> String {
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.map { disallowed.contains($0) ? " " : $0 }))
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let base = cleaned.isEmpty ? fallbackName : String(cleaned.prefix(maximumNameLength))
        return fileExtension.isEmpty ? base : base + "." + fileExtension
    }
}
