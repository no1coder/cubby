import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipBlobStoring：内存存储与加密存储的命名和数据接口")
struct ClipBlobStoringTests {
    @Test("内存存储：mem-<种类>-<哈希> 命名，可反推种类与哈希，不能与 HMAC 名相撞")
    func inMemoryNaming() throws {
        let memory = InMemoryClipBlobStore()
        for kind in ClipBlobKind.allCases {
            let name = memory.name(kind: kind, contentHash: "abc")
            #expect(name.hasPrefix("mem-"))
            #expect(BlobStore.isValidName(name))
            let parsed = try #require(InMemoryClipBlobStore.parse(name))
            #expect(parsed.kind == kind && parsed.contentHash == "abc")
        }
        #expect(memory.name(kind: .translatedImage, contentHash: "x") == "mem-translated-image-x")
        let encrypted = EncryptedBlobStore(directory: URL(fileURLWithPath: "/unused"), keys: try VaultFixtures.keys())
        #expect(InMemoryClipBlobStore.parse(encrypted.name(kind: .image, contentHash: "abc")) == nil)
        #expect(InMemoryClipBlobStore.parse("mem-image-") == nil)
        #expect(InMemoryClipBlobStore.parse("mem-unknown-abc") == nil)
        #expect(!memory.isPersistent)
    }

    @Test("内存存储：写入（同名跳过）、读取、删除、按保留集合清理；非法名称抛错")
    func inMemoryData() throws {
        let memory = InMemoryClipBlobStore()
        try memory.write(Data("a".utf8), name: "mem-image-a")
        try memory.write(Data("changed".utf8), name: "mem-image-a")
        try memory.write(Data("b".utf8), name: "mem-image-b")
        #expect(try memory.data("mem-image-a") == Data("a".utf8))
        #expect(memory.exists("mem-image-b"))
        #expect(throws: (any Error).self) { try memory.data("mem-image-missing") }
        #expect(throws: BlobStoreError.invalidName("../x")) { try memory.write(Data(), name: "../x") }

        #expect(try memory.removeAll(except: ["mem-image-a"]) == ["mem-image-b"])
        #expect(memory.names == ["mem-image-a"])
        #expect(memory.remove(["mem-image-a", "nothing"]).isEmpty)
        #expect(memory.names.isEmpty)
    }

    @Test("加密存储：名称为 HMAC（64 位十六进制），按种类区分，写盘为密文")
    func encryptedNaming() throws {
        let environment = try VaultEnvironment()
        defer { environment.remove() }
        let blobs = environment.blobs
        let image = blobs.name(kind: .image, contentHash: "abc")
        #expect(image.count == 64 && image.allSatisfy(\.isHexDigit))
        #expect(image == environment.keys.blobName(kind: "image", contentHash: "abc"))
        #expect(blobs.name(kind: .translatedImage, contentHash: "abc") != image)
        #expect(blobs.isPersistent)

        try blobs.write(Data("secret-png".utf8), name: image)
        let raw = try Data(contentsOf: environment.vault.blobsDirectory.appendingPathComponent(image))
        #expect(raw.range(of: Data("secret-png".utf8)) == nil)
        #expect(try blobs.data(image) == Data("secret-png".utf8))
    }

    @Test("ClipImageSource：按名称相等；可在后台读取；有缩略图时读出缩略图")
    func imageSource() async throws {
        let memory = InMemoryClipBlobStore()
        let name = memory.name(kind: .image, contentHash: "p")
        try memory.write(Data("png".utf8), name: name)
        try memory.write(Data("thumb".utf8), name: memory.thumbnailName(forImage: name))

        let source = ClipImageSource(name: name, blobs: memory, hasThumbnail: true)
        #expect(source == ClipImageSource(name: name, blobs: InMemoryClipBlobStore(), hasThumbnail: false))
        #expect(Set([source, source]).count == 1)
        #expect(try await source.load() == Data("png".utf8))
        #expect(source.thumbnailData() == Data("thumb".utf8))

        let missing = ClipImageSource(
            name: memory.name(kind: .image, contentHash: "none"), blobs: memory, hasThumbnail: true)
        #expect(missing.thumbnailData() == nil)
        #expect(throws: (any Error).self) { try missing.data() }
    }
}
