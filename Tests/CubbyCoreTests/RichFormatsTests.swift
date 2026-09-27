import Foundation
import Testing
@testable import CubbyCore

@Suite("RichFormats 编解码与采集上限")
struct RichFormatsTests {
    @Test("支持的格式为 RTF 与 HTML")
    func supportedTypes() {
        #expect(RichFormats.supportedTypes == ["public.rtf", "public.html"])
    }

    @Test(
        "编码后可解码回相同字典",
        arguments: [
            [String: Data](),
            ["public.rtf": Data("{\\rtf1 hi}".utf8)],
            ["public.rtf": Data([0, 1, 2, 255]), "public.html": Data("<b>粗体 📋</b>".utf8)],
            ["public.html": Data()],
        ])
    func roundTrip(_ formats: [String: Data]) throws {
        let encoded = try RichFormats.encode(formats)
        #expect(try RichFormats.decode(encoded) == formats)
    }

    @Test("使用二进制 plist 格式")
    func encodesBinaryPlist() throws {
        let encoded = try RichFormats.encode(["public.rtf": Data([1])])
        #expect(encoded.prefix(8) == Data("bplist00".utf8))
    }

    @Test("真实 RTF 数据往返后仍可解析为富文本")
    func realRTFRoundTrip() throws {
        let formats = Fixtures.richFormats(for: "加粗文本")
        let rtf = try #require(try RichFormats.decode(RichFormats.encode(formats))["public.rtf"])
        let attributed = try NSAttributedString(
            data: rtf,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        #expect(attributed.string == "加粗文本")
    }

    @Test("大体积格式数据（4MB）可往返")
    func largeRoundTrip() throws {
        let big = Data(repeating: 0xAB, count: CaptureLimits.maxFormatBytes)
        let decoded = try RichFormats.decode(RichFormats.encode(["public.rtf": big]))
        #expect(decoded["public.rtf"] == big)
    }

    @Test(
        "解码非法数据抛错",
        arguments: [
            Data(),
            Data("garbage".utf8),
            Data("bplist00".utf8),
        ])
    func decodeGarbageThrows(_ data: Data) {
        #expect(throws: (any Error).self) {
            try RichFormats.decode(data)
        }
    }

    @Test("解码类型不符的 plist 抛错")
    func decodeWrongTypeThrows() throws {
        let array = try PropertyListEncoder().encode(["a", "b"])
        let stringValues = try PropertyListEncoder().encode(["public.rtf": "not data"])
        #expect(throws: (any Error).self) { try RichFormats.decode(array) }
        #expect(throws: (any Error).self) { try RichFormats.decode(stringValues) }
    }

    // MARK: - CaptureLimits

    @Test("采集上限的取值与相对大小")
    func captureLimits() {
        #expect(CaptureLimits.maxTextBytes == 2 * 1024 * 1024)
        #expect(CaptureLimits.maxImageBytes == 30 * 1024 * 1024)
        #expect(CaptureLimits.maxTIFFBytes == 150 * 1024 * 1024)
        #expect(CaptureLimits.maxFormatBytes == 4 * 1024 * 1024)
        #expect(CaptureLimits.maxTIFFBytes > CaptureLimits.maxImageBytes)
    }

    // MARK: - ClipContent

    @Test("richText 的相等性同时比较文本与格式")
    func richTextEquality() {
        let formats = ["public.rtf": Data([1])]
        #expect(ClipContent.richText("a", formats: formats) == .richText("a", formats: formats))
        #expect(ClipContent.richText("a", formats: formats) != .richText("b", formats: formats))
        #expect(ClipContent.richText("a", formats: formats) != .richText("a", formats: ["public.rtf": Data([2])]))
        #expect(ClipContent.richText("a", formats: [:]) != .text("a"))
    }
}
