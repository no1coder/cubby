import CubbyCore
import Foundation
import os

/// 应用数据目录：~/Library/Application Support/Cubby。
/// 历史、图片与安全记录都加密存放在其中的 Vault/（E5）；旧版本的明文 history.json、Images/ 启动时迁移进去（E6）
enum AppPaths {
    /// 开发调试时可用 CUBBY_DATA_DIR 指向独立目录，避免污染真实历史
    private static let customDirectory: String? = {
        guard let custom = ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"], !custom.isEmpty else { return nil }
        return custom
    }()

    static let root: URL = {
        if let customDirectory {
            return URL(fileURLWithPath: customDirectory, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cubby", isDirectory: true)
    }()

    /// 是否使用 CUBBY_DATA_DIR：钥匙串 account 据此取 default 或 vault-<UUID>（E3）
    static var usesCustomDirectory: Bool { customDirectory != nil }

    /// 加密数据目录 <数据目录>/Vault/
    static let vault = VaultDirectory(url: root.appendingPathComponent(VaultDirectory.defaultName, isDirectory: true))

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
