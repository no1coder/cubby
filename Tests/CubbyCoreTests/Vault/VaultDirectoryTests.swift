import Foundation
import Testing
@testable import CubbyCore

@Suite("VaultDirectory 目录布局与「是否已有加密数据」")
struct VaultDirectoryTests {
    @Test("各文件位置")
    func layout() {
        let vault = VaultDirectory(url: URL(fileURLWithPath: "/tmp/x/Vault"))
        #expect(vault.historyURL.path == "/tmp/x/Vault/history.cubby")
        #expect(vault.securityLogURL.path == "/tmp/x/Vault/security-log.cubby")
        #expect(vault.blobsDirectory.path == "/tmp/x/Vault/Blobs")
        #expect(vault.backupsDirectory.path == "/tmp/x/Vault/Backups")
        #expect(vault.lockURL.path == "/tmp/x/Vault/.lock")
        #expect(vault.vaultIDURL.path == "/tmp/x/Vault/vault-id")
        #expect(VaultLock(vaultDirectory: vault.url).url == vault.lockURL)
    }

    @Test("目录不存在、为空、只有锁文件 / vault-id / .DS_Store：视为没有加密数据")
    func emptyVault() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let vault = VaultDirectory(url: dir.appendingPathComponent("Vault"))
        #expect(!vault.containsEncryptedData())

        try VaultLock(vaultDirectory: vault.url).withLock {}
        try Data("id".utf8).write(to: vault.vaultIDURL)
        try Data().write(to: vault.url.appendingPathComponent(".DS_Store"))
        #expect(!vault.containsEncryptedData())
    }

    @Test("有历史、Blobs、Backups 或残留临时文件中的任何一项：视为已有加密数据")
    func nonEmptyVault() throws {
        for entry in ["history.cubby", "Blobs", "Backups", ".history.cubby.\(UUID().uuidString).tmp", "unknown"] {
            let dir = try TempDirectory.make()
            defer { TempDirectory.remove(dir) }
            let vault = VaultDirectory(url: dir)
            try Data().write(to: dir.appendingPathComponent(entry))
            #expect(vault.containsEncryptedData(), "\(entry)")
        }
    }

    @Test("数据目录路径被普通文件占用：保守地视为已有数据，不生成新密钥")
    func pathIsAFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let file = dir.appendingPathComponent("Vault")
        try Data().write(to: file)
        #expect(VaultDirectory(url: file).containsEncryptedData())
    }
}
