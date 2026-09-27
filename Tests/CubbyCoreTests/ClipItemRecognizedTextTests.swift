import Foundation
import Testing
@testable import CubbyCore

/// ClipItem.recognizedText：图片中识别出的文字（不可变更新、匹配、编解码兼容）
@Suite("ClipItem 图片识别文字 recognizedText")
struct ClipItemRecognizedTextTests {
    private let image = Fixtures.image(name: "a.png", favorite: true)

    // MARK: - 不可变更新

    @Test("默认为 nil")
    func defaultsToNil() {
        #expect(image.recognizedText == nil)
        #expect(Fixtures.text("x").recognizedText == nil)
    }

    @Test("withRecognizedText 返回新值，其余字段不变且不修改原值")
    func withRecognizedTextIsNonMutating() {
        let recognized = image.withRecognizedText("Invoice 2026")
        #expect(image.recognizedText == nil)
        #expect(recognized.recognizedText == "Invoice 2026")
        #expect(recognized.withRecognizedText(nil) == image)
        #expect(recognized.id == image.id && recognized.isFavorite && recognized.payload == image.payload)
    }

    @Test("收藏、刷新时间、设置格式名都保留识别文字")
    func otherUpdatesKeepRecognizedText() {
        let recognized = image.withRecognizedText("hello")
        #expect(recognized.withFavorite(false).recognizedText == "hello")
        #expect(recognized.touched(at: Fixtures.baseDate.addingTimeInterval(5)).recognizedText == "hello")
        #expect(recognized.withFormatsName("f.formats").recognizedText == "hello")
    }

    @Test("replacing：新条目没有识别文字时沿用旧条目的（同一张图片无需重新识别）")
    func replacingKeepsExistingRecognizedText() {
        let old = image.withRecognizedText("old text")
        let fresh = Fixtures.image(name: "a.png", at: Fixtures.baseDate.addingTimeInterval(60))
        #expect(fresh.replacing(old).recognizedText == "old text")
        #expect(fresh.withRecognizedText("new").replacing(old).recognizedText == "new")
        #expect(fresh.replacing(image).recognizedText == nil)
    }

    // MARK: - 匹配

    @Test("matches(keyword:) 命中识别文字，忽略大小写与变音符")
    func matchesRecognizedText() {
        let recognized = image.withRecognizedText("Invoice 2026 \u{53D1}\u{7968} Café")
        #expect(recognized.matches(keyword: "invoice"))
        #expect(recognized.matches(keyword: "\u{53D1}\u{7968}"))
        #expect(recognized.matches(keyword: "cafe"))
        #expect(!recognized.matches(keyword: "receipt"))
        #expect(!image.matches(keyword: "invoice"))
    }

    @Test("空串表示已识别但没有文字：不命中任何关键词")
    func emptyRecognizedText() {
        let processed = image.withRecognizedText("")
        #expect(!processed.matches(keyword: "x"))
        #expect(!processed.imageTextMatches("x"))
        #expect(!processed.hasImageText)
        #expect(image.withRecognizedText("a").hasImageText)
    }

    @Test("matchesExcludingImageText 不看识别文字")
    func matchesExcludingImageText() {
        let recognized = image.withRecognizedText("invoice")
        #expect(!recognized.matchesExcludingImageText("invoice"))
        #expect(recognized.matchesExcludingImageText(ClipKind.image.displayName))
    }

    // MARK: - 编解码

    @Test("旧条目 JSON（无该字段）解码为 nil")
    func decodesLegacyItemWithoutField() throws {
        let json = #"""
            {"id":"3D4E5F60-7182-493A-A4B5-C6D7E8F90112","kind":"image","payload":{"image":{"_0":{"name":"9c1b.png","width":1920,"height":1080}}},"createdAt":715000300,"isFavorite":true,"contentHash":"image:9c1b"}
            """#
        let item = try JSONDecoder().decode(ClipItem.self, from: Data(json.utf8))
        #expect(item.recognizedText == nil)
        #expect(item.image?.name == "9c1b.png")
    }

    @Test("nil 时编码不写该字段：未识别的历史写盘结果与旧版本逐字节一致")
    func encodingOmitsNil() throws {
        let data = try JSONEncoder().encode(image)
        #expect(!String(decoding: data, as: UTF8.self).contains("recognizedText"))
    }

    @Test("编码后可原样解码（含中文、换行、表情）")
    func roundTrip() throws {
        let recognized = image.withRecognizedText("第一行 Invoice\n第二行 📋 \"quoted\"")
        let decoded = try JSONDecoder().decode(ClipItem.self, from: JSONEncoder().encode(recognized))
        #expect(decoded == recognized)
    }

    @Test("旧版本的解码逻辑（不认识该字段）也能读取新写入的条目：降级运行不会失败")
    func legacyDecoderReadsNewItems() throws {
        let data = try JSONEncoder().encode(image.withRecognizedText("Invoice"))
        let legacy = try JSONDecoder().decode(LegacyClipItemV1.self, from: data)
        #expect(legacy.id == image.id)
        #expect(legacy.payload == image.payload)
        #expect(legacy.contentHash == image.contentHash)
    }
}

/// v0.1 / v1 时期 ClipItem 的字段集合（冻结，不随模型变化），模拟旧版本 Cubby 读取新文件
private struct LegacyClipItemV1: Decodable {
    let id: UUID
    let kind: ClipKind
    let payload: ClipPayload
    let source: SourceApp?
    let createdAt: Date
    let isFavorite: Bool
    let contentHash: String
    let formatsName: String?
}
