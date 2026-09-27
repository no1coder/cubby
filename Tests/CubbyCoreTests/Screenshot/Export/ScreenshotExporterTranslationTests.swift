import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("ScreenshotExporter · 译文层（冻结帧 → 译文 → 标注）")
struct ScreenshotExporterTranslationTests {
    private let frame = ExportFixtures.frame(ExportFixtures.retina)
    private let selection = CGRect(x: 10, y: 10, width: 60, height: 40)

    /// 盖住 (20, 20)–(40, 30) 的纯色译文块（白底、没有文字）
    private var block: TranslatedBlock {
        let erase = CGRect(x: 20, y: 20, width: 20, height: 10)
        return TranslatedBlock(
            blockID: 0, eraseFrame: erase, backdrop: .solid(.white), text: "", textFrame: erase, fontSize: 8,
            isBold: false, textColor: .black, alignment: .leading)
    }

    private func pixel(_ export: ScreenshotExport, atGlobal point: CGPoint) -> Pixel {
        let scale = ExportFixtures.retina.scale
        return TestCanvas(image: export.image).pixel(
            x: Int((point.x - selection.minX) * scale), y: Int((point.y - selection.minY) * scale))
    }

    @Test("默认不画译文：与原来的导出一致")
    func noTranslationByDefault() throws {
        let export = try ScreenshotExporter.export(
            frame: frame, selection: selection, document: .empty, pixelatedFrame: nil)
        #expect(pixel(export, atGlobal: CGPoint(x: 25, y: 25)) == Pixel(50, 50, 128))
    }

    @Test("译文画在冻结帧之上：块内是背景色，块外保持原像素")
    func translationCoversOriginal() throws {
        let export = try ScreenshotExporter.export(
            frame: frame, selection: selection, document: .empty, translation: [block], pixelatedFrame: nil)
        #expect(pixel(export, atGlobal: CGPoint(x: 25, y: 25)) == Pixel(255, 255, 255))
        #expect(pixel(export, atGlobal: CGPoint(x: 50, y: 40)) == Pixel(100, 80, 128))
    }

    @Test("标注画在译文之上")
    func annotationsAboveTranslation() throws {
        let rectangle = Annotation(
            shape: .rectangle(CGRect(x: 22, y: 22, width: 30, height: 20)),
            style: AnnotationStyle(color: .red, weight: .heavy))
        let document = AnnotationDocument.empty.adding(rectangle)
        let export = try ScreenshotExporter.export(
            frame: frame, selection: selection, document: document, translation: [block], pixelatedFrame: nil)
        let edge = pixel(export, atGlobal: CGPoint(x: 22, y: 25))
        #expect(edge.red > 200 && edge.green < 100 && edge.blue < 100)
    }
}
