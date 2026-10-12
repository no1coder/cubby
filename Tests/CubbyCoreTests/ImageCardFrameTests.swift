import CoreGraphics
import CubbyCore
import Testing

@Suite("ImageThumbnail 卡片图片框的宽高比")
struct ImageCardFrameTests {
    @Test("常见截图比例原样使用，整张显示")
    func commonScreenshotRatiosFit() {
        for (width, height) in [(1600, 1000), (1920, 1080), (2880, 1800), (1024, 768)] {
            let frame = ImageThumbnail.cardFrame(width: width, height: height)
            #expect(abs(frame.aspectRatio - CGFloat(width) / CGFloat(height)) < 1e-9)
            #expect(frame.showsWholeImageByFilling)
        }
    }

    @Test("竖图与过高的图：框不高于 4:3，图片整张缩进框里")
    func tallImagesAreLetterboxed() {
        let frame = ImageThumbnail.cardFrame(width: 1170, height: 2532)
        #expect(frame.aspectRatio == ImageThumbnail.cardMinAspectRatio)
        #expect(!frame.showsWholeImageByFilling)
    }

    @Test("超宽横幅：框不扁于 3.5:1，图片整张缩进框里")
    func wideBannersAreLetterboxed() {
        let frame = ImageThumbnail.cardFrame(width: 4000, height: 300)
        #expect(frame.aspectRatio == ImageThumbnail.cardMaxAspectRatio)
        #expect(!frame.showsWholeImageByFilling)
    }

    @Test("边界比例正好整张显示")
    func boundaryRatiosFit() {
        #expect(ImageThumbnail.cardFrame(width: 400, height: 300).showsWholeImageByFilling)
        #expect(ImageThumbnail.cardFrame(width: 700, height: 200).showsWholeImageByFilling)
    }

    @Test("尺寸无效时按 16:10 处理")
    func invalidSizeFallsBack() {
        let frame = ImageThumbnail.cardFrame(width: 0, height: 0)
        #expect(frame.aspectRatio == 1.6)
        #expect(!frame.showsWholeImageByFilling)
    }
}
