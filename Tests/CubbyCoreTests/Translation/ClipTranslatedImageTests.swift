import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CubbyCore

/// 历史图片译后成图的输出：PNG 沿用原图 DPI；缓存 segments 按块 id 顺序
@Suite("译后图片输出")
struct ClipTranslatedImageTests {
    private func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test("有 DPI 时写入原图的 DPI，解码回来尺寸与 DPI 不变")
    func keepsDPI() throws {
        let png = try #require(ClipTranslatedImage.pngData(try image(width: 40, height: 20), dpi: 144))
        #expect(ImageFixtures.isPNG(png))
        let decoded = try #require(HistoryImageFrame.decode(png))
        #expect(decoded.image.width == 40 && decoded.image.height == 20)
        #expect(decoded.dpi == 144)
        #expect(HistoryImageFrame.scale(dpi: decoded.dpi) == 2)
    }

    @Test("原图没有 DPI（或非法）时不写 DPI")
    func omitsMissingDPI() throws {
        for dpi in [nil, 0, -72, .infinity] as [Double?] {
            let png = try #require(ClipTranslatedImage.pngData(try image(width: 8, height: 8), dpi: dpi))
            #expect(try properties(png)[kCGImagePropertyDPIWidth] == nil)
        }
    }

    @Test("缓存 segments：按块 id 排序，每块一项；未翻译、空译文为 nil，译文去掉首尾空白")
    func segments() {
        let segments = ClipTranslatedImage.segments(
            blockIDs: [2, 0, 1, 3], translations: [0: " 设置 ", 2: "保存", 3: "  ", 9: "x"])
        #expect(segments == ["设置", nil, "保存", nil])
        let entry = ClipTranslation(
            target: "zh-Hans", source: "en", engineName: "System", isOnDevice: true, createdAt: Fixtures.baseDate,
            segmentation: ClipTextSegmenter.version, segments: segments, imageName: "a.png")
        #expect(entry.plainText == "设置\n保存")
        #expect(ClipTranslatedImage.segments(blockIDs: [], translations: [0: "x"]).isEmpty)
    }

    @Test("segments 总长超过上限时，超出部分的块记为 nil，整条译文仍可缓存")
    func segmentsFitStoredLimit() {
        let segments = ClipTranslatedImage.segments(
            blockIDs: [0, 1, 2, 3], translations: [0: "aaaa", 1: "bbbb", 2: "cc", 3: "dddd"], maxLength: 10)
        #expect(segments == ["aaaa", "bbbb", "cc", nil])
        let long = String(repeating: "x", count: ClipTranslationLimits.standard.maxStoredLength)
        let capped = ClipTranslatedImage.segments(blockIDs: [0, 1], translations: [0: long, 1: "y"])
        #expect(capped == [long, nil])
        let entry = ClipTranslation(
            target: "zh-Hans", source: "en", engineName: "System", isOnDevice: true, createdAt: Fixtures.baseDate,
            segmentation: ClipTextSegmenter.version, segments: capped, imageName: "a.png")
        #expect(ClipTranslationLimits.standard.accepts(entry, for: Fixtures.image(name: "b.png")))
    }
}
