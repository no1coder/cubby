#if DEBUG
import AppKit
import CubbyCore

/// 设计稿走查的演示历史（`--demo-history`，与任意 `--scenario` 搭配）：启动时写入 CUBBY_DATA_DIR，覆盖其中的
/// history.json，并且不启动剪贴板监听，截图里不会出现真实剪贴板内容。条目照着 docs/design/ui-upgrade 的画板排列，
/// 全部虚构；裸可执行文件只显示英文界面，所以文案也是英文
enum DesignDemoHistory {
    static let argument = "--demo-history"

    static var isRequested: Bool {
        CommandLine.arguments.contains(argument)
    }

    /// 写入演示历史；未设置 CUBBY_DATA_DIR 时什么都不写（绝不覆盖真实历史），返回 false
    static func seed(now: Date = Date()) -> Bool {
        guard let dataDirectory = ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"], !dataDirectory.isEmpty
        else { return false }
        do {
            let blobs = BlobStore(directory: AppPaths.imagesDirectory)
            let file = try demoFile(in: URL(fileURLWithPath: dataDirectory, isDirectory: true))
            let items = try entries(blobs: blobs, file: file).enumerated().map { index, entry in
                try entry.item(id: id(index), now: now, blobs: blobs)
            }
            try JSONHistoryStorage(fileURL: AppPaths.historyFile).save(ClipHistory(items: items))
            return true
        } catch {
            FileHandle.standardError.write(Data("Seeding the design demo history failed: \(error)\n".utf8))
            return false
        }
    }

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "D35160D0-0000-4000-8000-%012d", index + 1)) ?? UUID()
    }

    /// 文件卡指向的演示文件：放在数据目录里，不涉及真实文件
    private static func demoFile(in directory: URL) throws -> String {
        let folder = directory.appendingPathComponent("Documents/Work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Quarterly Report.key")
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data().write(to: file)
        }
        return file.path
    }

    private static let day: Double = 24 * 60

    private static func entries(blobs: BlobStore, file: String) throws -> [Entry] {
        [
            .text(
                "Before Thursday's release: record the demo GIF, update the Homebrew cask, and reply to issue #42 "
                    + "about the dock position.",
                app: ("com.apple.Notes", "Notes"), minutes: 0),
            .text(
                "https://github.com/no1coder/cubby/issues/42", app: ("com.apple.Safari", "Safari"), minutes: 2,
                linkTitle: "Dock the panel to the right or bottom edge · Issue #42"),
            .text(
                "Text(\"Ship it!\")\n    .font(.headline)\n    .foregroundStyle(.purple)",
                app: ("com.apple.dt.Xcode", "Xcode"), minutes: 6),
            .text("#5F2EEA", app: ("com.apple.DigitalColorMeter", "Digital Color Meter"), minutes: 14, favorite: true),
            .image(.sunset, app: ("com.apple.iWork.Keynote", "Keynote"), minutes: 20),
            .image(.window, app: ("com.apple.screencaptureui", "Screenshot"), minutes: 45),
            .image(.chart, app: ("com.apple.iWork.Numbers", "Numbers"), minutes: 60),
            .files([file], app: ("com.apple.finder", "Finder"), minutes: day + 30),
            .text("#1F8A6A", app: ("com.figma.Desktop", "Figma"), minutes: day + 45),
            .text(
                "Video call at 8 tonight, I'll post the link in the group later.",
                app: ("com.tencent.xinWeChat", "WeChat"), minutes: day + 90),
            .image(.photo, app: ("com.apple.Photos", "Photos"), minutes: day + 120),
            .image(.terminal, app: ("com.apple.Terminal", "Terminal"), minutes: day + 180),
            .image(.design, app: ("com.figma.Desktop", "Figma"), minutes: 2 * day + 60),
        ]
    }

    /// 一条演示条目：内容 + 来源应用 + 距现在多少分钟
    private struct Entry {
        enum Content {
            case text(String)
            case image(DesignDemoImages.Scene)
            case files([String])
        }

        let content: Content
        let app: (bundleID: String, name: String)
        let minutes: Double
        var favorite = false
        /// 链接条目复制时浏览器带来的页面标题
        var linkTitle: String?

        static func text(
            _ value: String, app: (String, String), minutes: Double, favorite: Bool = false, linkTitle: String? = nil
        ) -> Entry {
            Entry(content: .text(value), app: app, minutes: minutes, favorite: favorite, linkTitle: linkTitle)
        }

        static func image(_ scene: DesignDemoImages.Scene, app: (String, String), minutes: Double) -> Entry {
            Entry(content: .image(scene), app: app, minutes: minutes)
        }

        static func files(_ paths: [String], app: (String, String), minutes: Double) -> Entry {
            Entry(content: .files(paths), app: app, minutes: minutes)
        }

        func item(id: UUID, now: Date, blobs: BlobStore) throws -> ClipItem {
            let source = SourceApp(bundleID: app.bundleID, name: app.name)
            let date = now.addingTimeInterval(-minutes * 60)
            switch content {
            case .text(let value):
                return ClipItem(
                    id: id, kind: ContentClassifier.kind(forText: value), payload: .text(value), source: source,
                    createdAt: date, isFavorite: favorite, contentHash: ContentHasher.hash(text: value),
                    linkTitle: linkTitle)
            case .files(let paths):
                return ClipItem(
                    id: id, kind: .file, payload: .files(paths), source: source, createdAt: date,
                    contentHash: ContentHasher.hash(filePaths: paths))
            case .image(let scene):
                let png = try DesignDemoImages.png(scene)
                let digest = ContentHasher.sha256(png)
                let name = "\(digest).png"
                try blobs.write(png, name: name)
                let size = DesignDemoImages.pixelSize
                return ClipItem(
                    id: id, kind: .image,
                    payload: .image(ImageRef(name: name, width: Int(size.width), height: Int(size.height))),
                    source: source, createdAt: date, contentHash: ContentHasher.hash(imageDigest: digest))
            }
        }
    }
}
#endif
