#if DEBUG
import CubbyCore
import Foundation

/// 演示历史（翻译演示、设计稿走查）直接写进加密 Vault：先清掉 CUBBY_DATA_DIR 里旧的 Vault、保留目录与明文
/// （只在 CUBBY_DATA_DIR，调用方已确认设置了它），再用本次运行的调试密钥（HistoryKeySource.current）建新 Vault。
/// 启动流程随后用同一个密钥来源解析出同一把密钥，读到这里写入的历史
@MainActor
enum DebugVaultSeed {
    struct Stores {
        let storage: EncryptedHistoryStorage
        let blobs: EncryptedBlobStore
        let keys: HistoryKeys
    }

    enum SeedError: Error {
        case keyUnavailable
    }

    static func prepare() throws -> Stores {
        let root = AppPaths.root
        let recovery = VaultRecovery(dataDirectory: root)
        let plain = PlaintextFiles(dataDirectory: root)
        for url in [recovery.vault.url, plain.historyURL, plain.imagesDirectory] + recovery.unreadableFolders()
        where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let launch = VaultLaunch(
            dataDirectory: root, provider: HistoryKeySource.current.provider, allowsDestructiveSteps: false)
        guard case .ready(let session) = try launch.run() else { throw SeedError.keyUnavailable }
        return Stores(
            storage: EncryptedHistoryStorage(vaultDirectory: session.vault.url, keys: session.keys),
            blobs: EncryptedBlobStore(directory: session.vault.blobsDirectory, keys: session.keys),
            keys: session.keys)
    }
}
#endif
