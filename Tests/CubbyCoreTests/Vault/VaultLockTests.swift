import Foundation
import os
import Testing
@testable import CubbyCore

@Suite("VaultLock 数据目录互斥锁")
struct VaultLockTests {
    @Test("withLock 执行闭包并返回结果；锁文件 0600、目录按需创建为 0700")
    func runsBody() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let vault = dir.appendingPathComponent("Vault")
        let lock = VaultLock(vaultDirectory: vault)

        let value = try lock.withLock { 42 }

        #expect(value == 42)
        #expect(lock.url.lastPathComponent == ".lock")
        #expect(try TempDirectory.permissions(of: lock.url) == 0o600)
        #expect(try TempDirectory.permissions(of: vault) == 0o700)
    }

    @Test("闭包抛错时透传错误并释放锁")
    func releasesOnError() throws {
        struct Marker: Error {}
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let lock = VaultLock(vaultDirectory: dir)

        #expect(throws: Marker.self) { try lock.withLock { throw Marker() } }
        #expect(try lock.withLock { true })
    }

    @Test("另一持有者释放前，withLock 阻塞等待（不同打开的文件描述之间互斥）")
    func excludesConcurrentHolders() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let lock = VaultLock(vaultDirectory: dir)
        let events = OSAllocatedUnfairLock(initialState: [String]())
        let holding = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            try? lock.withLock {
                events.withLock { $0.append("first-acquired") }
                holding.signal()
                release.wait()
                events.withLock { $0.append("first-released") }
            }
        }
        holding.wait()
        Thread.detachNewThread {
            try? lock.withLock { events.withLock { $0.append("second-acquired") } }
            finished.signal()
        }

        // 第二个持有者此时应仍在等待
        #expect(finished.wait(timeout: .now() + 0.3) == .timedOut)
        release.signal()
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(events.withLock { $0 } == ["first-acquired", "first-released", "second-acquired"])
    }

    @Test("无法创建锁文件时抛出")
    func failsWhenLockCannotBeOpened() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blocker = dir.appendingPathComponent("file")
        try Data().write(to: blocker)
        // 数据目录路径被普通文件占用
        let lock = VaultLock(vaultDirectory: blocker)

        #expect(throws: (any Error).self) { try lock.withLock {} }
        let nested = VaultLock(vaultDirectory: dir)
        try FileManager.default.createDirectory(at: nested.url, withIntermediateDirectories: true)
        #expect(throws: POSIXError.self) { try nested.withLock {} }
    }
}
