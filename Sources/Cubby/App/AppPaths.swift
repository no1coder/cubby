import Foundation
import os

/// 应用数据目录：~/Library/Application Support/Cubby
enum AppPaths {
    static let root: URL = {
        // 开发调试时可用 CUBBY_DATA_DIR 指向独立目录，避免污染真实历史
        if let custom = ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cubby", isDirectory: true)
    }()

    static let historyFile = root.appendingPathComponent("history.json", isDirectory: false)
    static let imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)

    /// 创建仅本人可访问的数据目录，并排除在 Time Machine 备份之外（剪贴板常含敏感内容）
    static func prepare() {
        let logger = Logger(subsystem: "io.github.no1coder.Cubby", category: "App")
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = root
            try url.setResourceValues(values)
        } catch {
            logger.error("Failed to prepare the data directory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
