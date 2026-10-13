import Darwin
import Foundation
import Testing
@testable import CubbyCore

/// E12 验收：26MB 级加密历史加载后的常驻内存增量与解密耗时（只在设置 CUBBY_BENCH=1 时运行；建议 release：
/// `CUBBY_BENCH=1 swift test -c release -Xswiftc -enable-testing -Xswiftc -DDEBUG --filter EncryptedHistoryBenchmark`）
@Suite(
    "EncryptedHistoryBenchmark 加载内存与耗时", .enabled(if: ProcessInfo.processInfo.environment["CUBBY_BENCH"] != nil),
    .serialized)
struct EncryptedHistoryBenchmarkTests {
    /// 约 26MB 的历史：260 条 100KB 级长文本
    private func largeHistory() -> ClipHistory {
        let paragraph = String(repeating: "2026-10-13 log line with id=42 status=200\n", count: 2_400)
        return ClipHistory(items: (0..<260).map { Fixtures.text("#\($0) " + paragraph) })
    }

    private func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    @Test("解密到匿名内存：解密本身的常驻增量 < 2MB、耗时 < 30ms；整体加载残留与明文相当")
    func loadFootprintAndDecryptTime() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let keys = try VaultFixtures.keys()
        let storage = EncryptedHistoryStorage(vaultDirectory: dir, keys: keys)
        let history = largeHistory()
        try storage.save(history)
        let file = try Data(contentsOf: storage.fileURL, options: .mappedIfSafe)
        let plaintextSize = try EncryptedFileFormat.plaintextByteCount(ofFile: file)

        // 对照：同一份历史以明文 JSON（映射读取）保存。分别加载后立即释放，比较残留的常驻增量：
        // 残留来自 malloc 大块不归还的问题（E12），解码出的条目本身释放后不计入
        let plain = JSONHistoryStorage(fileURL: dir.appendingPathComponent("history.json"))
        try plain.save(history)
        #expect(try storage.load() == plain.load())
        var before = footprint()
        #expect(try plain.load().items.count == history.items.count)
        let plainDelta = footprint() - before
        before = footprint()
        #expect(try storage.load().items.count == history.items.count)
        let encryptedDelta = footprint() - before

        // 只解密不解码：本层自身留下的常驻增量
        before = footprint()
        _ = try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: "history") { $0.count }
        let decryptDelta = footprint() - before

        let clock = ContinuousClock()
        var best = Duration.seconds(1000)
        for _ in 0..<5 {
            let start = clock.now
            _ = try EncryptedFileFormat.withDecryptedContents(of: file, keys: keys, role: "history") { $0.count }
            best = min(best, clock.now - start)
        }
        print(
            "plaintext \(plaintextSize / 1_048_576)MB, load delta json \(plainDelta / 1024)KB",
            "encrypted \(encryptedDelta / 1024)KB, decrypt-only \(decryptDelta / 1024)KB, decrypt \(best)"
        )
        #expect(decryptDelta < 2 * 1_048_576)
        // 解码出的上百 KB 字符串释放后在 malloc 中的残留有几 MB 的抖动（明文与加密都有），这里只防退化
        #expect(encryptedDelta < plainDelta + 4 * 1_048_576)
        #expect(best < .milliseconds(30))
    }
}
