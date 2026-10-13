import CryptoKit
import Foundation
import os
import Testing
@testable import CubbyCore

/// 只在指定次数内返回 nil、之后报错等边界行为的密钥来源
private final class ScriptedKeyProvider: HistoryKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var loads: [Result<SymmetricKey?, HistoryKeyError>]
    private let addResult: HistoryKeyError?
    private(set) var addCount = 0

    init(loads: [Result<SymmetricKey?, HistoryKeyError>], addResult: HistoryKeyError?) {
        self.loads = loads
        self.addResult = addResult
    }

    func loadKey() throws(HistoryKeyError) -> SymmetricKey? {
        let next = lock.withLock { loads.isEmpty ? .success(nil) : loads.removeFirst() }
        return try next.get()
    }

    func addKey(_ key: SymmetricKey) throws(HistoryKeyError) {
        lock.withLock { addCount += 1 }
        if let addResult { throw addResult }
    }
}

@Suite("VaultKeyResolver 密钥解析：就绪、锁定、密钥丢失")
struct VaultKeyResolverTests {
    private func resolver(
        _ provider: any HistoryKeyProviding,
        vaultHasData: Bool,
        generated: SymmetricKey = VaultFixtures.masterKey(0x77)
    ) -> VaultKeyResolver {
        VaultKeyResolver(provider: provider, vaultHasData: { vaultHasData }, generateMasterKey: { generated })
    }

    @Test("钥匙串已有密钥：直接就绪，不生成、不添加", arguments: [false, true])
    func existingKey(vaultHasData: Bool) throws {
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey(1))
        let result = resolver(provider, vaultHasData: vaultHasData).resolve()

        #expect(result == .ready(try VaultFixtures.keys(1)))
        #expect(provider.addAttempts == 0)
    }

    @Test("没有密钥且 Vault 不存在：生成并添加新密钥")
    func generatesForNewVault() throws {
        let provider = InMemoryHistoryKeyProvider()
        let result = resolver(provider, vaultHasData: false, generated: VaultFixtures.masterKey(0x77)).resolve()

        #expect(result == .ready(try VaultFixtures.keys(0x77)))
        let stored = try #require(provider.storedKey)
        #expect(VaultFixtures.keyBytes(stored) == VaultFixtures.keyBytes(VaultFixtures.masterKey(0x77)))
    }

    @Test("没有密钥但 Vault 已有数据：报告密钥丢失，绝不生成新密钥")
    func missingKeyForExistingVault() {
        let provider = InMemoryHistoryKeyProvider()
        let result = resolver(provider, vaultHasData: true).resolve()

        #expect(result == .missingKeyForExistingVault)
        #expect(provider.addAttempts == 0)
        #expect(provider.storedKey == nil)
    }

    @Test("读取时锁定：报告锁定，不查 Vault、不生成", arguments: [false, true])
    func lockedOnLoad(vaultHasData: Bool) {
        let provider = InMemoryHistoryKeyProvider(key: VaultFixtures.masterKey())
        provider.setLocked(true)
        let result = resolver(provider, vaultHasData: vaultHasData).resolve()

        #expect(result == .locked)
        #expect(provider.addAttempts == 0)
    }

    @Test("添加时锁定：报告锁定")
    func lockedOnAdd() {
        let provider = ScriptedKeyProvider(loads: [.success(nil)], addResult: .locked)
        #expect(resolver(provider, vaultHasData: false).resolve() == .locked)
        #expect(provider.addCount == 1)
    }

    @Test("并发首次生成：添加报 duplicate 后重读，采用另一实例的密钥，不覆盖")
    func duplicateRereadsRivalKey() throws {
        let provider = InMemoryHistoryKeyProvider()
        let rival = VaultFixtures.masterKey(0x11)
        provider.armRivalKey(rival)

        let result = resolver(provider, vaultHasData: false, generated: VaultFixtures.masterKey(0x22)).resolve()

        #expect(result == .ready(try VaultFixtures.keys(0x11)))
        let stored = try #require(provider.storedKey)
        #expect(VaultFixtures.keyBytes(stored) == VaultFixtures.keyBytes(rival))
    }

    @Test("duplicate 后重读失败或仍为空：报告锁定，不再生成")
    func duplicateThenUnreadable() {
        let lockedReread = ScriptedKeyProvider(loads: [.success(nil), .failure(.locked)], addResult: .duplicate)
        #expect(resolver(lockedReread, vaultHasData: false).resolve() == .locked)
        #expect(lockedReread.addCount == 1)

        let emptyReread = ScriptedKeyProvider(loads: [.success(nil), .success(nil)], addResult: .duplicate)
        #expect(resolver(emptyReread, vaultHasData: false).resolve() == .locked)
        #expect(emptyReread.addCount == 1)
    }

    @Test("钥匙串里的密钥长度不对：按锁定处理，不生成、不覆盖")
    func malformedStoredKey() {
        let provider = InMemoryHistoryKeyProvider(key: SymmetricKey(data: Data(repeating: 1, count: 16)))
        #expect(resolver(provider, vaultHasData: false).resolve() == .locked)
        #expect(provider.addAttempts == 0)
    }

    @Test("多个实例同时首次生成：全部得到同一把密钥，钥匙串只被成功写入一次")
    func concurrentFirstGeneration() throws {
        let provider = InMemoryHistoryKeyProvider()
        let instanceCount = 16
        let results = OSAllocatedUnfairLock(initialState: [VaultKeyResolution]())

        DispatchQueue.concurrentPerform(iterations: instanceCount) { index in
            let own = VaultFixtures.masterKey(UInt8(index + 1))
            let resolver = VaultKeyResolver(
                provider: provider, vaultHasData: { false }, generateMasterKey: { own }
            )
            let result = resolver.resolve()
            results.withLock { $0.append(result) }
        }

        let stored = try #require(provider.storedKey)
        let expected = VaultKeyResolution.ready(try HistoryKeys(masterKey: stored))
        let all = results.withLock { $0 }
        #expect(all.count == instanceCount)
        #expect(all.allSatisfy { $0 == expected })
    }

    @Test("默认生成器产生随机 256 位密钥")
    func defaultGenerator() throws {
        let provider = InMemoryHistoryKeyProvider()
        let result = VaultKeyResolver(provider: provider, vaultHasData: { false }).resolve()
        let stored = try #require(provider.storedKey)
        #expect(stored.bitCount == 256)
        #expect(result == .ready(try HistoryKeys(masterKey: stored)))
    }
}
