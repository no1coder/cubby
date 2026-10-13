#if DEBUG
import CryptoKit
import CubbyCore
import Foundation
import os

/// 仅 DEBUG 构建存在的历史密钥来源（E3b），Release 构建中没有这个类型，也没有读取环境变量的代码
/// （scripts/check-release-test-key.sh 检查 Release 二进制中不含 CUBBY_TEST_HISTORY_KEY）。
/// - 设置了 CUBBY_TEST_HISTORY_KEY（base64 的 32 字节）：用它，行为与正式版相同（迁移、改名保留都照常）；
/// - 端到端测试、调试走查、演示历史：每次运行随机生成的临时密钥，不碰钥匙串；
/// - 其他情况（日常调试运行）：nil，照常使用登录钥匙串。
enum DebugHistoryKey {
    static let environmentVariable = "CUBBY_TEST_HISTORY_KEY"

    static func choice(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments
    ) -> HistoryKeySource.Choice? {
        if let encoded = environment[environmentVariable], !encoded.isEmpty {
            if let data = Data(base64Encoded: encoded), data.count == HistoryKeys.masterKeyByteCount {
                return HistoryKeySource.Choice(
                    provider: InMemoryHistoryKeyProvider(key: SymmetricKey(data: data)), isEphemeral: false)
            }
            Logger(subsystem: "io.github.no1coder.Cubby", category: "Vault")
                .error("\(environmentVariable, privacy: .public) is not a base64 256-bit key; using a temporary key")
            return temporary
        }
        return usesTemporaryKey(arguments) ? temporary : nil
    }

    private static var temporary: HistoryKeySource.Choice {
        HistoryKeySource.Choice(provider: InMemoryHistoryKeyProvider(), isEphemeral: true)
    }

    /// 端到端测试与走查都带这些参数之一
    private static func usesTemporaryKey(_ arguments: [String]) -> Bool {
        let flags = ["--scenario", "--e2e", "--panel-e2e", "--translate-qa", "--clip-translation-selftest"]
        return flags.contains { arguments.contains($0) } || arguments.contains(DesignDemoHistory.argument)
    }

    /// 端到端测试的独立数据目录：随机密钥的加密存储（每个世界一把，用完即弃）
    static func vaultStores(in directory: URL) -> (storage: EncryptedHistoryStorage, blobs: EncryptedBlobStore) {
        let vault = VaultDirectory(url: directory.appendingPathComponent(VaultDirectory.defaultName, isDirectory: true))
        // 随机生成的 256 位密钥长度必然正确
        guard let keys = try? HistoryKeys(masterKey: HistoryKeys.generateMasterKey()) else {
            preconditionFailure("A generated master key is always 256 bits")
        }
        return (
            EncryptedHistoryStorage(vaultDirectory: vault.url, keys: keys),
            EncryptedBlobStore(directory: vault.blobsDirectory, keys: keys)
        )
    }
}
#endif
