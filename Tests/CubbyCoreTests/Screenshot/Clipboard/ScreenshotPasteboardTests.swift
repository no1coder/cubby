import AppKit
import Testing
@testable import CubbyCore

@Suite("ScreenshotPasteboard 写剪贴板")
struct ScreenshotPasteboardTests {
    private func types(of pasteboard: NSPasteboard) -> Set<NSPasteboard.PasteboardType> {
        Set(pasteboard.types ?? [])
    }

    @Test("PNG + TIFF + 标记都在；监听应忽略；读回为同尺寸图片")
    func writesImage() throws {
        let png = ImageFixtures.png(width: 7, height: 5)
        try withTemporaryPasteboard { pasteboard in
            try ScreenshotPasteboard.write(png: png, to: pasteboard)

            #expect(pasteboard.data(forType: .png) == png)
            let tiff = try #require(pasteboard.data(forType: .tiff))
            let rep = try #require(NSBitmapImageRep(data: tiff))
            #expect(rep.pixelsWide == 7 && rep.pixelsHigh == 5)
            #expect(types(of: pasteboard).contains(PasteboardReader.markerType))
            #expect(PasteboardReader.shouldIgnore(pasteboard))
            #expect(PasteboardReader.read(from: pasteboard) == .image(png: png, width: 7, height: 5))
        }
    }

    @Test("导出结果的 PNG 可写入并读回")
    func writesExportedPNG() throws {
        let export = try ScreenshotExporter.export(
            frame: ExportFixtures.frame(ExportFixtures.retina),
            selection: CGRect(x: 0, y: 0, width: 20, height: 10),
            document: .empty,
            pixelatedFrame: nil
        )
        try withTemporaryPasteboard { pasteboard in
            try ScreenshotPasteboard.write(png: export.png, to: pasteboard)
            guard case .image(_, let width, let height) = PasteboardReader.read(from: pasteboard) else {
                Issue.record("expected image content")
                return
            }
            #expect(width == 40 && height == 20)
        }
    }

    @Test("写入替换剪贴板原有内容")
    func replacesExistingContent() throws {
        try withTemporaryPasteboard { pasteboard in
            pasteboard.setString("old", forType: .string)
            try ScreenshotPasteboard.write(png: ImageFixtures.png(width: 1, height: 1), to: pasteboard)
            #expect(pasteboard.string(forType: .string) == nil)
        }
    }

    @Test("坏 PNG 抛 imageUnavailable，且不清空剪贴板", arguments: [Data(), Data("not png".utf8)])
    func invalidPNGThrows(data: Data) {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setString("previous", forType: .string)
            #expect(throws: PasteboardWriteError.imageUnavailable) {
                try ScreenshotPasteboard.write(png: data, to: pasteboard)
            }
            #expect(pasteboard.string(forType: .string) == "previous")
        }
    }

    @Test("文本写入带标记（取色 / OCR 结果）")
    func writesText() {
        withTemporaryPasteboard { pasteboard in
            pasteboard.setData(ImageFixtures.png(width: 1, height: 1), forType: .png)
            ScreenshotPasteboard.write(text: "#FF8800", to: pasteboard)

            #expect(pasteboard.string(forType: .string) == "#FF8800")
            #expect(!types(of: pasteboard).contains(.png))
            #expect(types(of: pasteboard).contains(PasteboardReader.markerType))
            #expect(PasteboardReader.shouldIgnore(pasteboard))
            #expect(PasteboardReader.read(from: pasteboard) == .text("#FF8800"))
        }
    }

    @Test("PNG 与标记写入后立即可读；TIFF 只是承诺，读取时按需生成一次且像素一致")
    func tiffIsProvidedLazily() throws {
        let png = try #require(ScreenshotExporter.pngData(TestImage.coordinates(width: 6, height: 4), scale: 1))
        let provider = LazyTIFFProvider(png: png)
        try withTemporaryPasteboard { pasteboard in
            pasteboard.clearContents()
            pasteboard.writeObjects([ScreenshotPasteboard.imageItem(png: png, tiffProvider: provider)])
            #expect(pasteboard.data(forType: .png) == png)
            #expect(types(of: pasteboard).contains(PasteboardReader.markerType))
            #expect(types(of: pasteboard).contains(.tiff))
            #expect(provider.generatedCount == 0)

            let tiff = try #require(pasteboard.data(forType: .tiff))
            #expect(pasteboard.data(forType: .tiff) == tiff)
            #expect(provider.generatedCount == 1)
            let expected = try #require(NSBitmapImageRep(data: png))
            let actual = try #require(NSBitmapImageRep(data: tiff))
            #expect(actual.pixelsWide == 6 && actual.pixelsHigh == 4)
            for y in 0..<4 {
                for x in 0..<6 {
                    #expect(actual.colorAt(x: x, y: y) == expected.colorAt(x: x, y: y))
                }
            }
        }
    }

    @Test("剪贴板被清空后 AppKit 释放 provider（连同它持有的 PNG）")
    func providerReleasedAfterClear() {
        let png = ImageFixtures.png(width: 2, height: 2)
        weak var weakProvider: LazyTIFFProvider?
        withTemporaryPasteboard { pasteboard in
            autoreleasepool {
                let provider = LazyTIFFProvider(png: png)
                weakProvider = provider
                pasteboard.clearContents()
                _ = pasteboard.writeObjects([ScreenshotPasteboard.imageItem(png: png, tiffProvider: provider)])
            }
            #expect(weakProvider != nil)
            autoreleasepool { _ = pasteboard.clearContents() }
            #expect(weakProvider == nil)
        }
    }

    @Test("PNG 头部有效但不是 PNG（如 JPEG 数据）也被拒绝")
    func rejectsNonPNGImage() throws {
        let jpeg = try #require(
            NSBitmapImageRep(data: ImageFixtures.png(width: 2, height: 2))?
                .representation(using: .jpeg, properties: [:]))
        withTemporaryPasteboard { pasteboard in
            #expect(throws: PasteboardWriteError.imageUnavailable) {
                try ScreenshotPasteboard.write(png: jpeg, to: pasteboard)
            }
        }
    }
}
