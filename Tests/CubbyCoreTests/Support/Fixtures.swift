import AppKit
import Foundation
import Testing
@testable import CubbyCore

/// 测试用的条目工厂，统一使用固定时间，避免依赖真实时钟
enum Fixtures {
    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func text(
        _ value: String,
        favorite: Bool = false,
        source: SourceApp? = nil,
        at date: Date = baseDate,
        formatsName: String? = nil
    ) -> ClipItem {
        ClipItem(
            kind: ContentClassifier.kind(forText: value),
            payload: .text(value),
            source: source,
            createdAt: date,
            isFavorite: favorite,
            contentHash: ContentHasher.hash(text: value),
            formatsName: formatsName
        )
    }

    /// 典型的富文本格式：真实 RTF（加粗）+ 简单 HTML
    static func richFormats(for text: String) -> [String: Data] {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let range = NSRange(location: 0, length: attributed.length)
        let rtf =
            (try? attributed.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )) ?? Data()
        let html = Data("<b>\(text)</b>".utf8)
        return ["public.rtf": rtf, "public.html": html]
    }

    static func image(
        name: String,
        width: Int = 10,
        height: Int = 20,
        favorite: Bool = false,
        at date: Date = baseDate
    ) -> ClipItem {
        ClipItem(
            kind: .image,
            payload: .image(ImageRef(name: name, width: width, height: height)),
            source: nil,
            createdAt: date,
            isFavorite: favorite,
            contentHash: "image:" + name
        )
    }

    static func files(
        _ paths: [String],
        favorite: Bool = false,
        at date: Date = baseDate
    ) -> ClipItem {
        ClipItem(
            kind: .file,
            payload: .files(paths),
            source: nil,
            createdAt: date,
            isFavorite: favorite,
            contentHash: ContentHasher.hash(filePaths: paths)
        )
    }
}

/// 临时目录：每个测试独立创建，由调用方在 defer 中删除
enum TempDirectory {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cubby-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 目录下的文件名（不含隐藏文件），目录不存在时返回空集合
    static func fileNames(in url: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    /// 文件或目录的 POSIX 权限位（如 0o600）
    static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = try #require(attributes[.posixPermissions] as? NSNumber)
        return value.intValue & 0o777
    }

    static func exists(_ name: String, in dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }
}

/// 统一构造 ClipStore，默认使用固定时间
@MainActor
enum StoreFactory {
    static func make(
        dir: URL,
        storage: some HistoryPersisting = InMemoryHistoryStorage(),
        limit: Int = 10,
        now: @escaping () -> Date = { Fixtures.baseDate }
    ) -> ClipStore {
        ClipStore(storage: storage, blobs: BlobStore(directory: dir), limit: limit, now: now)
    }
}

/// 生成真实可解码的位图数据
enum ImageFixtures {
    static func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else {
            preconditionFailure("无法创建测试位图")
        }
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 1), atX: x, y: y)
            }
        }
        return rep
    }

    static func png(width: Int, height: Int) -> Data {
        guard let data = bitmap(width: width, height: height).representation(using: .png, properties: [:]) else {
            preconditionFailure("无法生成 PNG")
        }
        return data
    }

    static func tiff(width: Int, height: Int) -> Data {
        guard let data = bitmap(width: width, height: height).tiffRepresentation else {
            preconditionFailure("无法生成 TIFF")
        }
        return data
    }

    /// PNG 文件签名
    static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    static func isPNG(_ data: Data) -> Bool {
        data.prefix(pngSignature.count) == pngSignature
    }
}

/// 独立命名的剪贴板，测试结束后释放，避免污染系统剪贴板
@discardableResult
func withTemporaryPasteboard<T>(_ body: (NSPasteboard) throws -> T) rethrows -> T {
    let pasteboard = NSPasteboard(name: .init("cubby-test-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    return try body(pasteboard)
}
