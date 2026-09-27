import Foundation
import Testing
@testable import CubbyCore

/// 各版本历史文件的冻结样本。
/// 内容按当时真实写入的格式手写（JSONEncoder 默认输出：斜杠转义、日期为参考时间秒数、nil 字段省略），
/// 不随模型代码变化，保证迁移链始终能读懂老用户磁盘上的文件。
/// 以 Swift 源码内联而非 .json 资源：测试 target 未声明 resources，放 .json 会产生未处理文件警告。
enum HistoryFixtures {
    // MARK: - v0（v0.1 写入：只有 items，没有 schemaVersion）

    static let v0JSON = #"""
        {"items":[
        {"id":"8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B","kind":"text","payload":{"text":{"_0":"你好 📋 \"引号\" \\ 反斜杠\n换行\t制表 '; DROP TABLE items; --"}},"source":{"bundleID":"com.apple.Notes","name":"备忘录"},"createdAt":715000000.123456,"isFavorite":true,"contentHash":"text:hello"},
        {"id":"1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9","kind":"link","payload":{"text":{"_0":"https:\/\/example.com\/a?b=1&c=%E4%BD%A0"}},"source":{},"createdAt":715000100,"isFavorite":false,"contentHash":"text:link"},
        {"id":"2C3D4E5F-6071-4829-93A4-B5C6D7E8F901","kind":"text","payload":{"text":{"_0":"粗体"}},"createdAt":715000200.5,"isFavorite":false,"contentHash":"text:rich","formatsName":"3f2a.formats"},
        {"id":"3D4E5F60-7182-493A-A4B5-C6D7E8F90112","kind":"image","payload":{"image":{"_0":{"name":"9c1b.png","width":1920,"height":1080}}},"source":{"bundleID":"com.apple.Preview"},"createdAt":715000300,"isFavorite":true,"contentHash":"image:9c1b"},
        {"id":"4E5F6071-8293-4A4B-B5C6-D7E8F9011223","kind":"file","payload":{"files":{"_0":["\/Users\/me\/a b.txt","\/tmp\/中文.txt"]}},"createdAt":715000400.25,"isFavorite":false,"contentHash":"files:x"},
        {"id":"5F607182-93A4-4B5C-86D7-E8F901122334","kind":"color","payload":{"text":{"_0":"#FF8800 café 😀"}},"createdAt":0,"isFavorite":false,"contentHash":"text:color"}
        ]}
        """#

    /// v0 样本中富文本 / 图片条目引用的 blob 文件名（ClipStore 集成测试需预先写入，否则会被启动修复移除）
    static let v0BlobNames = ["3f2a.formats", "9c1b.png"]

    /// v0 样本对应的期望条目（逐字段手写，与 JSON 一一对应）
    static let v0Items: [ClipItem] = [
        ClipItem(
            id: uuid("8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B"),
            kind: .text,
            payload: .text("你好 📋 \"引号\" \\ 反斜杠\n换行\t制表 '; DROP TABLE items; --"),
            source: SourceApp(bundleID: "com.apple.Notes", name: "备忘录"),
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_000.123456),
            isFavorite: true,
            contentHash: "text:hello"
        ),
        ClipItem(
            id: uuid("1B2C3D4E-5F60-4718-8293-A4B5C6D7E8F9"),
            kind: .link,
            payload: .text("https://example.com/a?b=1&c=%E4%BD%A0"),
            source: SourceApp(bundleID: nil, name: nil),
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_100),
            contentHash: "text:link"
        ),
        ClipItem(
            id: uuid("2C3D4E5F-6071-4829-93A4-B5C6D7E8F901"),
            kind: .text,
            payload: .text("粗体"),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_200.5),
            contentHash: "text:rich",
            formatsName: "3f2a.formats"
        ),
        ClipItem(
            id: uuid("3D4E5F60-7182-493A-A4B5-C6D7E8F90112"),
            kind: .image,
            payload: .image(ImageRef(name: "9c1b.png", width: 1920, height: 1080)),
            source: SourceApp(bundleID: "com.apple.Preview", name: nil),
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_300),
            isFavorite: true,
            contentHash: "image:9c1b"
        ),
        ClipItem(
            id: uuid("4E5F6071-8293-4A4B-B5C6-D7E8F9011223"),
            kind: .file,
            payload: .files(["/Users/me/a b.txt", "/tmp/中文.txt"]),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_400.25),
            contentHash: "files:x"
        ),
        ClipItem(
            id: uuid("5F607182-93A4-4B5C-86D7-E8F901122334"),
            kind: .color,
            payload: .text("#FF8800 café 😀"),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            contentHash: "text:color"
        ),
    ]

    // MARK: - v1（当前版本）

    static let v1JSON = #"""
        {"schemaVersion":1,"items":[{"id":"8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B","kind":"text","payload":{"text":{"_0":"v1 条目"}},"createdAt":715000000.5,"isFavorite":true,"contentHash":"text:v1"}]}
        """#

    static let v1Items: [ClipItem] = [
        ClipItem(
            id: uuid("8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B"),
            kind: .text,
            payload: .text("v1 条目"),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_000.5),
            isFavorite: true,
            contentHash: "text:v1"
        )
    ]

    // MARK: - v1 + recognizedText（本版本写入：图片条目带识别文字，schemaVersion 仍为 1）

    static let v1WithRecognizedTextJSON = #"""
        {"schemaVersion":1,"items":[{"id":"3D4E5F60-7182-493A-A4B5-C6D7E8F90112","kind":"image","payload":{"image":{"_0":{"name":"9c1b.png","width":1920,"height":1080}}},"createdAt":715000300,"isFavorite":false,"contentHash":"image:9c1b","recognizedText":"Invoice 2026 \u53d1\u7968\n第二行"},{"id":"4E5F6071-8293-4A4B-B5C6-D7E8F9011223","kind":"image","payload":{"image":{"_0":{"name":"7d2e.png","width":8,"height":6}}},"createdAt":715000200,"isFavorite":false,"contentHash":"image:7d2e","recognizedText":""},{"id":"8A6F2C1E-0B3D-4E5F-9A7B-1C2D3E4F5A6B","kind":"text","payload":{"text":{"_0":"v1 条目"}},"createdAt":715000000.5,"isFavorite":true,"contentHash":"text:v1"}]}
        """#

    static let v1WithRecognizedTextItems: [ClipItem] = [
        ClipItem(
            id: uuid("3D4E5F60-7182-493A-A4B5-C6D7E8F90112"),
            kind: .image,
            payload: .image(ImageRef(name: "9c1b.png", width: 1920, height: 1080)),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_300),
            contentHash: "image:9c1b",
            recognizedText: "Invoice 2026 \u{53D1}\u{7968}\n第二行"
        ),
        ClipItem(
            id: uuid("4E5F6071-8293-4A4B-B5C6-D7E8F9011223"),
            kind: .image,
            payload: .image(ImageRef(name: "7d2e.png", width: 8, height: 6)),
            source: nil,
            createdAt: Date(timeIntervalSinceReferenceDate: 715_000_200),
            contentHash: "image:7d2e",
            recognizedText: ""
        ),
        v1Items[0],
    ]

    // MARK: - v99（模拟更新版本的 Cubby 写入：条目结构当前版本无法解码）

    static let v99JSON = #"""
        {"schemaVersion":99,"items":[{"uuid":"x","blocks":[{"type":"text","value":"来自未来"}]}],"collections":[{"name":"工作"}]}
        """#

    // MARK: - 工具

    /// 把样本写入文件并返回写入的原始字节，便于之后比对“文件未被改动”
    @discardableResult
    static func write(_ json: String, to url: URL) throws -> Data {
        let data = Data(json.utf8)
        try data.write(to: url)
        return data
    }

    /// 读取历史文件顶层的 schemaVersion；字段缺失时返回 nil
    static func schemaVersion(ofFileAt url: URL) throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let top = try #require(object as? [String: Any])
        return top["schemaVersion"] as? Int
    }

    /// 以 v0.1 的方式（只有 items）编码历史，用于批量生成 v0 数据
    static func encodeAsV0(_ history: ClipHistory) throws -> Data {
        try JSONEncoder().encode(LegacyV0File(items: history.items))
    }

    private struct LegacyV0File: Encodable {
        let items: [ClipItem]
    }

    private static func uuid(_ string: String) -> UUID {
        guard let value = UUID(uuidString: string) else {
            preconditionFailure("非法的测试 UUID: \(string)")
        }
        return value
    }
}
