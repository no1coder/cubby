import Foundation
import Testing
@testable import CubbyCore

/// 后台准备、主线程入历史：摘要与 blob 写入在后台完成，语义与同步 record 一致
@Suite("ClipStore 后台记录")
@MainActor
struct ClipStoreBackgroundRecordTests {
    private func image(_ seed: String) -> ClipContent {
        .image(png: Data("png-\(seed)".utf8), width: 8, height: 6)
    }

    @Test("后台记录图片：条目、blob、权限 0600 与同步路径一致")
    func imageMatchesSynchronousPath() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let background = StoreFactory.make(dir: dir.appendingPathComponent("bg"))
        let synchronous = StoreFactory.make(dir: dir.appendingPathComponent("sync"))

        let recorded = try #require(await background.recordInBackground(image("a"), source: nil).value)
        let expected = try #require(synchronous.record(image("a"), source: nil))

        #expect(recorded.contentHash == expected.contentHash)
        #expect(recorded.image == expected.image)
        #expect(recorded.createdAt == Fixtures.baseDate)
        let blob = try #require(background.imageURL(for: recorded))
        #expect(try TempDirectory.permissions(of: blob) == 0o600)
        #expect(background.history.items.map(\.id) == [recorded.id])
    }

    @Test("相同内容去重：合并为一条并移到最前")
    func deduplicates() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        _ = await store.recordInBackground(image("a"), source: nil).value
        _ = await store.recordInBackground(image("b"), source: nil).value
        _ = await store.recordInBackground(image("a"), source: nil).value
        #expect(store.history.items.count == 2)
        #expect(store.history.items.first?.contentHash == ContentHasher.hash(imageData: Data("png-a".utf8)))
    }

    @Test("按调用顺序入历史（并发发起也不乱序）")
    func preservesOrder() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let first = store.recordInBackground(image("big"), source: nil)
        let second = store.recordInBackground(.text("after"), source: nil)
        _ = await (first.value, second.value)
        #expect(store.history.items.map(\.kind) == [.text, .image])
    }

    @Test("文本、富文本、文件也可后台记录，分类与同步路径一致")
    func otherKinds() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let color = try #require(await store.recordInBackground(.text("rgb(1, 2, 3)"), source: nil).value)
        #expect(color.kind == .color)
        let rich = try #require(
            await store.recordInBackground(
                .richText("hi", formats: ["public.rtf": Data("{\\rtf1 hi}".utf8)]), source: nil
            )
            .value)
        #expect(rich.formatsName != nil)
        let files = try #require(
            await store.recordInBackground(.files([URL(fileURLWithPath: "/tmp/x")]), source: nil).value)
        #expect(files.kind == .file)
    }

    @Test("准备后 blob 在入历史前被删掉：入历史时补写，条目不会指向缺失的文件")
    func rewritesMissingBlob() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let blobs = BlobStore(directory: dir)

        let prepared = try ClipStore.prepare(image("gone"), blobs: blobs)
        let name = try #require(prepared.blobName)
        blobs.remove([name])
        #expect(!blobs.exists(name))

        let item = try #require(store.record(prepared, source: nil))
        #expect(blobs.exists(try #require(item.image?.name)))
    }

    @Test("准备失败（blob 目录被普通文件占用）：返回 nil，历史不变")
    func failureReturnsNil() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let blocked = dir.appendingPathComponent("blocked")
        try Data().write(to: blocked)
        let store = StoreFactory.make(dir: blocked)

        #expect(await store.recordInBackground(image("x"), source: nil).value == nil)
        #expect(store.history.items.isEmpty)
    }
}
