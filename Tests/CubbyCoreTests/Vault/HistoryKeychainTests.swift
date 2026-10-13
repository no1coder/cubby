import CryptoKit
import Foundation
import Security
import Testing
@testable import CubbyCore

@Suite("HistoryKeychain：状态码映射与 account（E3、E3a）")
struct HistoryKeychainTests {
    private let raw = Data(repeating: 0x42, count: 32)

    @Test("读取：成功且 32 字节 → 密钥；errSecItemNotFound → nil")
    func loadSuccessAndNotFound() throws {
        let key = try #require(try HistoryKeychain.loadedKey(status: errSecSuccess, data: raw))
        #expect(VaultFixtures.keyBytes(key) == raw)
        #expect(try HistoryKeychain.loadedKey(status: errSecItemNotFound, data: nil) == nil)
    }

    @Test(
        "读取：拒绝、认证失败、不允许交互、其他错误与长度不对一律 .locked",
        arguments: [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable, -1])
    func loadFailuresAreLocked(_ status: OSStatus) {
        #expect(throws: HistoryKeyError.locked) { try HistoryKeychain.loadedKey(status: status, data: nil) }
    }

    @Test("读取成功但数据缺失或长度不对：.locked（不能用也不能覆盖）")
    func malformedDataIsLocked() {
        #expect(throws: HistoryKeyError.locked) { try HistoryKeychain.loadedKey(status: errSecSuccess, data: nil) }
        #expect(throws: HistoryKeyError.locked) {
            try HistoryKeychain.loadedKey(status: errSecSuccess, data: Data(repeating: 1, count: 16))
        }
    }

    @Test("添加：成功；errSecDuplicateItem → .duplicate；其余 → .locked")
    func addMapping() {
        #expect(throws: Never.self) { try HistoryKeychain.checkAdded(status: errSecSuccess) }
        #expect(throws: HistoryKeyError.duplicate) { try HistoryKeychain.checkAdded(status: errSecDuplicateItem) }
        #expect(throws: HistoryKeyError.locked) { try HistoryKeychain.checkAdded(status: errSecUserCanceled) }
        #expect(throws: HistoryKeyError.locked) { try HistoryKeychain.checkAdded(status: errSecAuthFailed) }
    }

    @Test("service 为 <bundle id>.history；默认 account 为 default")
    func names() {
        #expect(
            HistoryKeychain.service(bundleIdentifier: "io.github.no1coder.Cubby") == "io.github.no1coder.Cubby.history")
        #expect(HistoryKeychain.defaultAccount == "default")
    }

    @Test("自定义目录：首次生成 vault-id（UUID），之后稳定；vault-id 不算加密数据")
    func customAccountIsStable() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let first = try HistoryKeychain.customAccount(vault: environment.vault)
        #expect(first.hasPrefix("vault-"))
        #expect(UUID(uuidString: String(first.dropFirst("vault-".count))) != nil)
        #expect(try HistoryKeychain.customAccount(vault: environment.vault) == first)
        #expect(!environment.vault.containsEncryptedData())
        #expect(TempDirectory.fileNames(in: environment.vault.url) == ["vault-id"])
    }

    @Test("vault-id 内容损坏：抛错，不悄悄换成新 account")
    func corruptVaultID() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        try PrivateFiles.createDirectory(at: environment.vault.url)
        try Data("garbage".utf8).write(to: environment.vault.vaultIDURL)
        #expect(throws: (any Error).self) { try HistoryKeychain.customAccount(vault: environment.vault) }
    }

    @Test("S2：改名之后、把 vault-id 放回新 Vault 之前崩溃：下次仍得到同一个 account")
    func vaultIDSurvivesCrashDuringQuarantine() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let account = try HistoryKeychain.customAccount(vault: environment.vault)
        // 模拟 quarantine 的前两步：先留一份待放回的 vault-id，再改名，然后崩溃
        try VaultRecovery.stageVaultID(of: environment.vault)
        try FileManager.default.moveItem(
            at: environment.vault.url, to: environment.root.appendingPathComponent("Vault-unreadable-x"))

        #expect(try HistoryKeychain.customAccount(vault: environment.vault) == account)
    }

    @Test("E8 ② 改名保留后，新 Vault 沿用原来的 vault-id（account 不变）")
    func quarantineKeepsVaultID() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let account = try HistoryKeychain.customAccount(vault: environment.vault)
        try environment.storage.save(.empty)
        _ = try VaultRecovery(dataDirectory: environment.root).quarantine()
        #expect(try HistoryKeychain.customAccount(vault: environment.vault) == account)
        #expect(!environment.vault.containsEncryptedData())
    }
}
