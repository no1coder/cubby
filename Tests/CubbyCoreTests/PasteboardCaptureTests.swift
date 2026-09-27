import AppKit
import Testing
@testable import CubbyCore

/// 主线程只取原始字节：只提供 TIFF 的图片以 RawImage 交给后台，转码、尺寸解析与大小检查在 ClipStore.prepare 完成
@Suite("剪贴板采集：TIFF 转码移到后台", .serializedPasteboardAccess, .timeLimit(.minutes(1)))
struct PasteboardCaptureTests {
    /// 改动前在主线程执行的转码写法，用来确认后台转码的结果逐字节不变（去重哈希因此不变）
    private func legacyPNG(from tiff: Data) throws -> Data {
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - capture

    @Test("只有 TIFF：返回原始字节，不在读取时转码")
    func tiffIsCapturedRaw() {
        let tiff = ImageFixtures.tiff(width: 5, height: 7)
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(tiff, forType: .tiff)
            #expect(PasteboardReader.capture(from: pasteboard) == .rawImage(RawImage(data: tiff)))
        }
    }

    @Test("PNG：与此前相同，直接得到可入库的图片内容")
    func pngIsCapturedAsContent() {
        let png = ImageFixtures.png(width: 4, height: 3)
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(png, forType: .png)
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.image(png: png, width: 4, height: 3)))
        }
    }

    @Test("PNG 无法解码时回退到 TIFF 原始字节")
    func invalidPNGFallsBackToRawTIFF() {
        let tiff = ImageFixtures.tiff(width: 2, height: 2)
        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(Data("not a png".utf8), forType: .png)
            item.setData(tiff, forType: .tiff)
            pasteboard.writeObjects([item])
            #expect(PasteboardReader.capture(from: pasteboard) == .rawImage(RawImage(data: tiff)))
        }
    }

    @Test("PNG 超过 maxImageBytes：直接放弃，不再回退 TIFF（同一张图的 TIFF 更大，转码后必然同样超限）")
    func oversizedPNGDoesNotFallBackToTIFF() {
        let tiff = ImageFixtures.tiff(width: 2, height: 2)
        withTemporaryPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setData(Data(count: CaptureLimits.maxImageBytes + 1), forType: .png)
            item.setData(tiff, forType: .tiff)
            pasteboard.writeObjects([item])
            #expect(PasteboardReader.capture(from: pasteboard) == nil)
        }
    }

    @Test("TIFF 头部无法识别或超过 maxTIFFBytes：在主线程直接丢弃")
    func invalidOrOversizedTIFFIsDropped() {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(Data("garbage tiff".utf8), forType: .tiff)
            #expect(PasteboardReader.capture(from: pasteboard) == nil)

            let tiff = ImageFixtures.tiff(width: 2, height: 2)
            pasteboard.clearContents()
            pasteboard.setData(tiff + Data(count: CaptureLimits.maxTIFFBytes - tiff.count + 1), forType: .tiff)
            #expect(PasteboardReader.capture(from: pasteboard) == nil)
        }
    }

    @Test("文本与文件照常作为内容返回")
    func textAndFilesAreContent() {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setString("hello", forType: .string)
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text("hello")))
            pasteboard.clearContents()
            #expect(PasteboardReader.capture(from: pasteboard) == nil)
        }
    }

    // MARK: - 规范化

    @Test("后台转码：PNG 与此前主线程转码的结果逐字节相同，尺寸取自位图")
    func normalizationMatchesLegacyConversion() throws {
        let tiff = LargeImageFixtures.tiff(width: 300, height: 200)
        let normalized = try ImageNormalizer.normalize(RawImage(data: tiff))
        #expect(normalized == NormalizedImage(png: try legacyPNG(from: tiff), width: 300, height: 200))
        #expect(normalized.content == .image(png: normalized.png, width: 300, height: 200))
    }

    @Test("错误描述用于日志：包含原因与字节数")
    func errorDescriptions() {
        #expect(ImageCaptureError.undecodable.localizedDescription.contains("decoded"))
        #expect(ImageCaptureError.tooLarge(bytes: 42).localizedDescription.contains("42"))
    }

    @MainActor
    @Test("后台记录转码后超过上限的原始图片：跳过，不入历史")
    func oversizedRawImageIsSkipped() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let raw = RawImage(data: Data(count: CaptureLimits.maxTIFFBytes + 1))

        #expect(await store.recordInBackground(raw, source: nil).value == nil)
        #expect(store.history.items.isEmpty)
    }

    @Test("转码失败或转码后超过 maxImageBytes：抛出对应错误")
    func normalizationErrors() throws {
        #expect(throws: ImageCaptureError.undecodable) {
            try ImageNormalizer.normalize(RawImage(data: Data("garbage".utf8)))
        }
        let tiff = ImageFixtures.tiff(width: 20, height: 20)
        let png = try legacyPNG(from: tiff)
        #expect(throws: ImageCaptureError.tooLarge(bytes: png.count)) {
            try ImageNormalizer.normalize(RawImage(data: tiff), maxPNGBytes: png.count - 1)
        }
        #expect(throws: Never.self) {
            try ImageNormalizer.normalize(RawImage(data: tiff), maxPNGBytes: png.count)
        }
    }

    @Test("转码前也检查 TIFF 大小上限（不经过读取直接构造的原始图片）")
    func normalizationRejectsOversizedRawData() {
        let raw = RawImage(data: Data(count: CaptureLimits.maxTIFFBytes + 1))
        #expect(throws: ImageCaptureError.tooLarge(bytes: CaptureLimits.maxTIFFBytes + 1)) {
            try ImageNormalizer.normalize(raw)
        }
    }

    @Test("read 仍返回规范化后的内容：TIFF 读成 PNG 图片")
    func readNormalizesSynchronously() throws {
        let tiff = ImageFixtures.tiff(width: 5, height: 7)
        let expected = try legacyPNG(from: tiff)
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(tiff, forType: .tiff)
            #expect(PasteboardReader.read(from: pasteboard) == .image(png: expected, width: 5, height: 7))
        }
    }

    // MARK: - ClipStore

    @MainActor
    @Test("后台记录原始 TIFF：条目尺寸正确，去重哈希按转码后的 PNG 计算，与直接记录 PNG 合并为一条")
    func recordRawImageInBackground() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)
        let tiff = ImageFixtures.tiff(width: 6, height: 4)
        let png = try legacyPNG(from: tiff)

        let item = try #require(await store.recordInBackground(RawImage(data: tiff), source: nil).value)
        #expect(item.kind == .image)
        #expect(item.image?.width == 6 && item.image?.height == 4)
        #expect(item.contentHash == ContentHasher.hash(imageData: png))
        let blob = try #require(store.imageURL(for: item))
        #expect(try Data(contentsOf: blob) == png)
        #expect(try TempDirectory.permissions(of: blob) == 0o600)

        _ = await store.recordInBackground(.image(png: png, width: 6, height: 4), source: nil).value
        #expect(store.history.items.count == 1)
    }

    @MainActor
    @Test("后台记录无法转码的原始图片：返回 nil，历史与文件都不变")
    func undecodableRawImageIsNotRecorded() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        #expect(await store.recordInBackground(RawImage(data: Data("bad".utf8)), source: nil).value == nil)
        #expect(store.history.items.isEmpty)
        #expect(TempDirectory.fileNames(in: dir).isEmpty)
    }

    @MainActor
    @Test("原始图片与其他内容混合时仍按调用顺序入历史")
    func rawImagePreservesOrder() async throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let store = StoreFactory.make(dir: dir)

        let tiff = LargeImageFixtures.tiff(width: 2400, height: 1600)
        let image = store.recordInBackground(RawImage(data: tiff), source: nil)
        let text = store.recordInBackground(.text("after"), source: nil)
        _ = await (image.value, text.value)

        #expect(store.history.items.map(\.kind) == [.text, .image])
        // 大图同时生成了缩略图
        let recorded = try #require(store.history.items.last?.image)
        #expect(TempDirectory.exists(ImageThumbnail.name(forImage: recorded.name), in: dir))
    }
}
