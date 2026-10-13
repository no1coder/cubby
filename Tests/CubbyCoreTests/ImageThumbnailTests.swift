import Foundation
import Testing
@testable import CubbyCore

/// 预生成的卡片缩略图：尺寸规则、文件名、格式选择（不透明 JPEG / 透明 PNG）与读取
@Suite("ImageThumbnail 预生成缩略图")
struct ImageThumbnailTests {
    // MARK: - 尺寸与文件名

    @Test("竖长图：高宽比严格大于 1.5（卡片据此顶部对齐）")
    func isTallUsesStrictRatio() {
        #expect(ImageThumbnail.isTall(width: 1000, height: 1501))
        #expect(!ImageThumbnail.isTall(width: 1000, height: 1500))
        #expect(!ImageThumbnail.isTall(width: 5120, height: 2880))
        #expect(!ImageThumbnail.isTall(width: 0, height: 100))
    }

    @Test(
        "目标最长边与卡片请求一致：普通图 720；竖长图（高宽比 > 1.5）按宽度放大，不超过 2048",
        arguments: [
            (5120, 2880, 720),
            (720, 1080, 720),  // 高宽比恰好 1.5，不算竖长
            (1000, 2000, 1440),
            (1000, 5000, 2048),
            (0, 100, 720),
        ])
    func pixelSizeMatchesCardRequest(width: Int, height: Int, expected: Int) {
        #expect(ImageThumbnail.pixelSize(width: width, height: height) == expected)
    }

    @Test("只为解码慢的大图生成：超过 2.5MP 且比目标尺寸大")
    func isNeededOnlyForLargeImages() {
        #expect(ImageThumbnail.isNeeded(width: 5120, height: 2880))
        #expect(ImageThumbnail.isNeeded(width: 2000, height: 1300))
        #expect(!ImageThumbnail.isNeeded(width: 2000, height: 1250))  // 恰好 2.5MP
        #expect(!ImageThumbnail.isNeeded(width: 1920, height: 1080))  // 2.07MP：原图解码已足够快
        #expect(!ImageThumbnail.isNeeded(width: 720, height: 405))
        #expect(ImageThumbnail.isNeeded(width: 1000, height: 3000))  // 竖长图目标 2048 < 3000
        #expect(!ImageThumbnail.isNeeded(width: 64, height: 64))
    }

    @Test("明文时代的文件名由原图名推出：<摘要>.thumb，是合法的 blob 名（迁移时据此找到旧缩略图）")
    func legacyNameIsDerivedFromImageName() {
        let name = ImageThumbnail.legacyName(forImage: "abc123.png")
        #expect(name == "abc123.thumb")
        #expect(BlobStore.isValidName(name))
        #expect(ImageThumbnail.legacyName(forImage: "noext") == "noext.thumb")
    }

    @Test("加密存储中的缩略图名：由原图名推出的另一个 HMAC，没有 .thumb 后缀，合法且与原图名不同")
    func encryptedNameIsDerivedFromImageName() throws {
        let blobs = EncryptedBlobStore(directory: URL(fileURLWithPath: "/unused"), keys: try VaultFixtures.keys())
        let image = blobs.name(kind: .image, contentHash: "abc123")
        let thumbnail = blobs.thumbnailName(forImage: image)
        #expect(thumbnail != image)
        #expect(!thumbnail.contains("."))
        #expect(thumbnail.count == 64)
        #expect(EncryptedBlobStore.isValidName(thumbnail))
        #expect(blobs.thumbnailName(forImage: image) == thumbnail)
    }

    // MARK: - 生成

    @Test("不透明大图：生成 JPEG，最长边等于目标尺寸，宽高比不变")
    func opaqueImageBecomesJPEG() throws {
        let png = LargeImageFixtures.png(width: 2400, height: 1350)
        let data = try #require(ImageThumbnail.make(fromImageData: png, width: 2400, height: 1350))

        #expect(data.starts(with: LargeImageFixtures.jpegSignature))
        let info = try #require(LargeImageFixtures.info(of: data))
        #expect(info.width == 720)
        #expect(info.height == 405)
        #expect(data.count < png.count)
    }

    @Test("带 alpha 通道但每个像素都不透明（常见的截图 PNG）：仍用 JPEG")
    func opaqueAlphaChannelBecomesJPEG() throws {
        let png = LargeImageFixtures.png(width: 2000, height: 1600, fill: .opaque)
        #expect(LargeImageFixtures.info(of: png)?.hasAlpha == true)
        let data = try #require(ImageThumbnail.make(fromImageData: png, width: 2000, height: 1600))
        #expect(data.starts(with: LargeImageFixtures.jpegSignature))
    }

    @Test("有透明像素：生成 PNG 并保留透明度（JPEG 没有 alpha）")
    func transparentImageStaysPNG() throws {
        let png = LargeImageFixtures.png(width: 2400, height: 1350, fill: .halfTransparent)
        let data = try #require(ImageThumbnail.make(fromImageData: png, width: 2400, height: 1350))

        #expect(ImageFixtures.isPNG(data))
        let info = try #require(LargeImageFixtures.info(of: data))
        #expect(info.width == 720 && info.height == 405)
        #expect(LargeImageFixtures.minimumAlpha(of: data) == 0)
    }

    @Test("没有 alpha 通道的图直接用 JPEG")
    func noAlphaImageBecomesJPEG() throws {
        let tiff = LargeImageFixtures.tiff(width: 1800, height: 1800, fill: .noAlpha)
        let data = try #require(ImageThumbnail.make(fromImageData: tiff, width: 1800, height: 1800))
        #expect(data.starts(with: LargeImageFixtures.jpegSignature))
        #expect(LargeImageFixtures.info(of: data)?.width == 720)
    }

    @Test("竖长图：最长边按卡片的竖长图规则（宽度仍清晰）")
    func tallImageUsesTallPixelSize() throws {
        let png = LargeImageFixtures.png(width: 1000, height: 3000)
        let data = try #require(ImageThumbnail.make(fromImageData: png, width: 1000, height: 3000))
        let info = try #require(LargeImageFixtures.info(of: data))
        #expect(info.height == 2048)
        #expect((682...683).contains(info.width))
    }

    @Test("不需要缩略图（原图不大）或数据无法解码时返回 nil")
    func returnsNilWhenNotNeededOrUndecodable() {
        let small = LargeImageFixtures.png(width: 1200, height: 820)
        #expect(ImageThumbnail.make(fromImageData: small, width: 1200, height: 820) == nil)
        #expect(ImageThumbnail.make(fromImageData: Data("not an image".utf8), width: 5000, height: 3000) == nil)
    }

    @Test("从原图数据生成：JPEG、长边 720")
    func makesFromImageData() throws {
        let png = LargeImageFixtures.png(width: 2560, height: 1440)
        let data = try #require(ImageThumbnail.make(fromImageData: png, width: 2560, height: 1440))
        #expect(data.starts(with: LargeImageFixtures.jpegSignature))
        #expect(LargeImageFixtures.info(of: data)?.width == 720)
    }

    // MARK: - 读取

    @Test("读取：缩略图存在且不小于请求尺寸时解码缩略图，否则返回 nil（调用方退回原图）")
    func decodeUsesThumbnailOnlyWhenLargeEnough() throws {
        let blobs = InMemoryClipBlobStore()
        let png = LargeImageFixtures.png(width: 2400, height: 1350)
        let name = blobs.name(kind: .image, contentHash: "big")
        try blobs.write(png, name: name)
        let source = ClipImageSource(name: name, blobs: blobs, hasThumbnail: true)

        #expect(ImageThumbnail.decode(thumbnailOf: source, maxPixelSize: 720) == nil)

        let thumbnail = try #require(ImageThumbnail.make(fromImageData: png, width: 2400, height: 1350))
        try blobs.write(thumbnail, name: blobs.thumbnailName(forImage: name))

        let decoded = try #require(ImageThumbnail.decode(thumbnailOf: source, maxPixelSize: 720))
        #expect(decoded.width == 720 && decoded.height == 405)
        let smaller = try #require(ImageThumbnail.decode(thumbnailOf: source, maxPixelSize: 360))
        #expect(smaller.width == 360)
        // 预览面板请求 1600px：缩略图不够大
        #expect(ImageThumbnail.decode(thumbnailOf: source, maxPixelSize: 1600) == nil)
        // 来源声明没有缩略图（小图、译后图）时不读缩略图
        let without = ClipImageSource(name: name, blobs: blobs, hasThumbnail: false)
        #expect(ImageThumbnail.decode(thumbnailOf: without, maxPixelSize: 720) == nil)
    }

    @Test("读取：竖长图的缩略图（长边 2048）只服务卡片请求，预览面板的 1600px 请求退回原图")
    func tallThumbnailDoesNotServePreview() throws {
        let png = LargeImageFixtures.png(width: 1000, height: 3000)
        let thumbnail = try #require(ImageThumbnail.make(fromImageData: png, width: 1000, height: 3000))

        let card = try #require(ImageThumbnail.decode(thumbnailData: thumbnail, maxPixelSize: 2048))
        #expect(card.height == 2048)
        #expect(ImageThumbnail.decode(thumbnailData: thumbnail, maxPixelSize: 1600) == nil)
        #expect(ImageThumbnail.decode(thumbnailData: thumbnail, maxPixelSize: 720)?.height == 720)
    }

    @Test("读取：缩略图数据损坏时返回 nil")
    func decodeIgnoresCorruptThumbnail() {
        #expect(ImageThumbnail.decode(thumbnailData: Data("garbage".utf8), maxPixelSize: 720) == nil)
    }

    @Test("解码任意图片数据：按最长边缩小；不是图片时为 nil")
    func decodesImageData() {
        let png = LargeImageFixtures.png(width: 2400, height: 1350)
        #expect(ImageThumbnail.decode(imageData: png, maxPixelSize: 1600)?.width == 1600)
        #expect(ImageThumbnail.decode(imageData: Data("garbage".utf8), maxPixelSize: 1600) == nil)
    }
}
