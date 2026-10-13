import CryptoKit
import Foundation
import Testing
@testable import CubbyCore

@Suite("InMemoryHistoryKeyProvider 只增不改的内存密钥来源")
struct InMemoryHistoryKeyProviderTests {
    @Test("没有密钥时读取返回 nil；添加后读到同一密钥")
    func addThenLoad() throws {
        let provider = InMemoryHistoryKeyProvider()
        #expect(try provider.loadKey() == nil)

        let key = VaultFixtures.masterKey(5)
        try provider.addKey(key)

        let loaded = try #require(try provider.loadKey())
        #expect(VaultFixtures.keyBytes(loaded) == VaultFixtures.keyBytes(key))
        #expect(provider.addAttempts == 1)
    }

    @Test("已有密钥时再次添加报 duplicate，原密钥不变")
    func addIsAddOnly() throws {
        let original = VaultFixtures.masterKey(1)
        let provider = InMemoryHistoryKeyProvider(key: original)

        #expect(throws: HistoryKeyError.duplicate) {
            try provider.addKey(VaultFixtures.masterKey(2))
        }
        let stored = try #require(provider.storedKey)
        #expect(VaultFixtures.keyBytes(stored) == VaultFixtures.keyBytes(original))
    }

    @Test("锁定时读取与添加都抛 locked；解锁后恢复")
    func lockedState() throws {
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())
        provider.setLocked(true)

        #expect(throws: HistoryKeyError.locked) { try provider.loadKey() }
        #expect(throws: HistoryKeyError.locked) { try provider.addKey(VaultFixtures.masterKey(3)) }

        provider.setLocked(false)
        #expect(try provider.loadKey() != nil)
    }

    @Test("模拟另一实例抢先添加：下一次添加报 duplicate，存下的是对方的密钥")
    func rivalAdd() throws {
        let provider = InMemoryHistoryKeyProvider()
        let rival = VaultFixtures.masterKey(8)
        provider.armRivalKey(rival)

        #expect(throws: HistoryKeyError.duplicate) {
            try provider.addKey(VaultFixtures.masterKey(9))
        }
        let stored = try #require(try provider.loadKey())
        #expect(VaultFixtures.keyBytes(stored) == VaultFixtures.keyBytes(rival))
    }
}
