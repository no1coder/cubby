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

    @Test("文件名由原图名推出：<摘要>.thumb，是合法的 blob 名")
    func nameIsDerivedFromImageName() {
        let name = ImageThumbnail.name(forImage: "abc123.png")
        #expect(name == "abc123.thumb")
        #expect(BlobStore.isValidName(name))
        #expect(ImageThumbnail.name(forImage: "noext") == "noext.thumb")
        let url = ImageThumbnail.url(forImageAt: URL(fileURLWithPath: "/tmp/Images/abc123.png"))
        #expect(url.path == "/tmp/Images/abc123.thumb")
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

    @Test("从文件生成：结果与从数据生成相同的尺寸与格式")
    func makesFromFile() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let url = dir.appendingPathComponent("a.png")
        try LargeImageFixtures.png(width: 2560, height: 1440).write(to: url)

        let data = try #require(ImageThumbnail.make(fromImageAt: url, width: 2560, height: 1440))
        #expect(data.starts(with: LargeImageFixtures.jpegSignature))
        #expect(LargeImageFixtures.info(of: data)?.width == 720)
        let missing = dir.appendingPathComponent("missing.png")
        #expect(ImageThumbnail.make(fromImageAt: missing, width: 2560, height: 1440) == nil)
    }

    // MARK: - 读取

    @Test("读取：缩略图存在且不小于请求尺寸时解码缩略图，否则返回 nil（调用方退回原图）")
    func decodeUsesThumbnailOnlyWhenLargeEnough() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let imageURL = dir.appendingPathComponent("big.png")
        let png = LargeImageFixtures.png(width: 2400, height: 1350)
        try png.write(to: imageURL)

        #expect(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 720) == nil)

        let thumbnail = try #require(ImageThumbnail.make(fromImageData: png, width: 2400, height: 1350))
        try thumbnail.write(to: ImageThumbnail.url(forImageAt: imageURL))

        let decoded = try #require(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 720))
        #expect(decoded.width == 720 && decoded.height == 405)
        let smaller = try #require(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 360))
        #expect(smaller.width == 360)
        // 预览面板请求 1600px：缩略图不够大
        #expect(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 1600) == nil)
    }

    @Test("读取：竖长图的缩略图（长边 2048）只服务卡片请求，预览面板的 1600px 请求退回原图")
    func tallThumbnailDoesNotServePreview() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let imageURL = dir.appendingPathComponent("tall.png")
        let png = LargeImageFixtures.png(width: 1000, height: 3000)
        try png.write(to: imageURL)
        let thumbnail = try #require(ImageThumbnail.make(fromImageData: png, width: 1000, height: 3000))
        try thumbnail.write(to: ImageThumbnail.url(forImageAt: imageURL))

        let card = try #require(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 2048))
        #expect(card.height == 2048)
        #expect(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 1600) == nil)
        #expect(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 720)?.height == 720)
    }

    @Test("读取：缩略图文件损坏时返回 nil")
    func decodeIgnoresCorruptThumbnail() throws {
        let dir = try TempDirectory.make()
        defer { TempDirectory.remove(dir) }
        let imageURL = dir.appendingPathComponent("big.png")
        try Data("garbage".utf8).write(to: ImageThumbnail.url(forImageAt: imageURL))
        #expect(ImageThumbnail.decode(forImageAt: imageURL, maxPixelSize: 720) == nil)
    }
}
