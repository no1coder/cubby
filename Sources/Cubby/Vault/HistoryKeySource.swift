import CubbyCore
import Foundation

/// 本次运行的历史密钥来源：正式为登录钥匙串；DEBUG 构建的测试与走查用内存密钥（E3b），不碰钥匙串、不弹窗。
/// 进程内只有一个实例：演示历史的写入与启动时的解析必须拿到同一把密钥
enum HistoryKeySource {
    struct Choice: Sendable {
        let provider: any HistoryKeyProviding
        /// 密钥只存在于本进程（用完即弃）：不得改名保留旧 Vault、不得迁移明文（见 VaultLaunch）
        let isEphemeral: Bool
    }

    static let current: Choice = {
        #if DEBUG
        if let debug = DebugHistoryKey.choice() { return debug }
        #endif
        return Choice(provider: keychainProvider(), isEphemeral: false)
    }()

    private static func keychainProvider() -> KeychainHistoryKeyProvider {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.no1coder.Cubby"
        let usesCustomDirectory = AppPaths.usesCustomDirectory
        let vault = AppPaths.vault
        return KeychainHistoryKeyProvider(service: HistoryKeychain.service(bundleIdentifier: bundleID)) {
            usesCustomDirectory ? try HistoryKeychain.customAccount(vault: vault) : HistoryKeychain.defaultAccount
        }
    }
}
