import Darwin
import Foundation
import Testing
@testable import CubbyCore

@Suite("AnonymousBuffer 匿名映射内存")
struct AnonymousBufferTests {
    @Test("新分配的内存全为 0，起始地址按页对齐", arguments: [1, 4096, 5 * 1024 * 1024 + 3])
    func zeroFilledAndAligned(byteCount: Int) throws {
        let buffer = try AnonymousBuffer(byteCount: byteCount)
        #expect(buffer.byteCount == byteCount)
        buffer.withUnsafeMutableBytes { bytes in
            #expect(bytes.count == byteCount)
            #expect(Int(bitPattern: bytes.baseAddress) % Int(getpagesize()) == 0)
            #expect(bytes.allSatisfy { $0 == 0 })
        }
    }

    @Test("写入后经 Data 视图读回（不复制）")
    func writeThenReadAsData() throws {
        let content = VaultFixtures.bytes(10_000)
        let buffer = try AnonymousBuffer(byteCount: content.count + 100)
        buffer.withUnsafeMutableBytes { bytes in
            content.withUnsafeBytes { source in bytes.copyMemory(from: source) }
        }

        let readBack = buffer.withData(count: content.count) { Data($0) }
        #expect(readBack == content)
        // 小于内联阈值的视图会被 Data 复制进内联存储，这里取足够长的视图
        let sameAddress = buffer.withData(count: content.count) { data in
            data.withUnsafeBytes { view in
                buffer.withUnsafeMutableBytes { UnsafeRawPointer($0.baseAddress) == view.baseAddress }
            }
        }
        #expect(sameAddress)
    }

    @Test("长度为 0：Data 视图为空")
    func zeroLength() throws {
        let buffer = try AnonymousBuffer(byteCount: 0)
        #expect(buffer.withData(count: 0) { $0.isEmpty })
        #expect(buffer.withUnsafeMutableBytes { $0.count } == 0)
    }

    @Test("非法长度或无法分配时抛出")
    func invalidSizes() {
        #expect(throws: POSIXError.self) { _ = try AnonymousBuffer(byteCount: -1) }
        #expect(throws: POSIXError.self) { _ = try AnonymousBuffer(byteCount: Int.max / 2) }
    }

    @Test("闭包的错误原样透传")
    func propagatesErrors() throws {
        struct Marker: Error {}
        let buffer = try AnonymousBuffer(byteCount: 8)
        #expect(throws: Marker.self) { try buffer.withData(count: 8) { _ in throw Marker() } }
        #expect(throws: Marker.self) { try buffer.withUnsafeMutableBytes { _ in throw Marker() } }
    }
}
