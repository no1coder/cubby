import Foundation
import Testing
@testable import CubbyCore

/// 图片文字索引的保存规则：去空白、截断、密钥过滤、超大图缩放
@Suite("ImageTextIndexPolicy 识别结果与缩放规则")
struct ImageTextIndexPolicyTests {
    // MARK: - storableText

    @Test("去掉首尾空白；没有文字时为空串（表示已识别）")
    func trimsWhitespace() {
        #expect(ImageTextIndexPolicy.storableText("  Invoice 2026\n") == "Invoice 2026")
        #expect(ImageTextIndexPolicy.storableText(" \n\t ").isEmpty)
        #expect(ImageTextIndexPolicy.storableText("").isEmpty)
    }

    @Test("中间的换行与中英文原样保留")
    func keepsInnerContent() {
        let text = "Invoice 2026\n\u{53D1}\u{7968} \u{2014} total"
        #expect(ImageTextIndexPolicy.storableText(text) == text)
    }

    @Test("截断到 10 000 个字符（按字符计，不拆分表情或汉字）")
    func truncates() {
        let long = String(repeating: "\u{53D1}", count: 6_000) + String(repeating: "📋", count: 6_000)
        let stored = ImageTextIndexPolicy.storableText(long)
        #expect(ImageTextIndexPolicy.maxTextLength == 10_000)
        #expect(stored.count == 10_000)
        #expect(stored.hasSuffix("📋"))
        #expect(ImageTextIndexPolicy.storableText(String(repeating: "a", count: 10_000)).count == 10_000)
    }

    @Test(
        "疑似密钥：不保存文字（空串），与是否截断无关",
        arguments: [
            "export TOKEN=" + FakeSecrets.github(),
            FakeSecrets.pem("RSA PRIVATE"),
            "\u{5BC6}\u{94A5} " + FakeSecrets.openAI(),
            String(repeating: "x ", count: 6_000) + FakeSecrets.aws(),
        ])
    func dropsSecrets(_ text: String) {
        #expect(ImageTextIndexPolicy.storableText(text).isEmpty)
    }

    @Test("普通文字不会被误判为密钥")
    func keepsOrdinaryText() {
        #expect(ImageTextIndexPolicy.storableText("sk-learn is a library") == "sk-learn is a library")
    }

    // MARK: - recognitionMaxPixelSize

    @Test("不超过 4K 面积的图片不缩放", arguments: [(3840, 2160), (1, 1), (300, 20_000), (2160, 3840)])
    func smallImagesAreNotScaled(_ width: Int, _ height: Int) {
        #expect(ImageTextIndexPolicy.recognitionMaxPixelSize(width: width, height: height) == nil)
    }

    @Test("超大图片按面积缩放到约 4K，返回缩放后的最长边")
    func largeImagesAreScaled() throws {
        let size = try #require(ImageTextIndexPolicy.recognitionMaxPixelSize(width: 6016, height: 3384))
        #expect((3839...3840).contains(size))
        let tall = try #require(ImageTextIndexPolicy.recognitionMaxPixelSize(width: 5000, height: 7000))
        let scale = Double(tall) / 7000
        #expect(Double(5000) * scale * Double(tall) <= Double(ImageTextIndexPolicy.maxPixelArea))
        #expect(tall > 3000)
    }

    @Test("尺寸非法（0 或负数）时不缩放", arguments: [(0, 100), (-5, 10), (100, 0)])
    func invalidSizes(_ width: Int, _ height: Int) {
        #expect(ImageTextIndexPolicy.recognitionMaxPixelSize(width: width, height: height) == nil)
    }
}
