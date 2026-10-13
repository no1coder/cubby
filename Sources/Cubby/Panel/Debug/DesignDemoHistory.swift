#if DEBUG
import AppKit
import CubbyCore

/// 设计稿走查的演示历史（`--demo-history`，与任意 `--scenario` 搭配）：启动时写入 CUBBY_DATA_DIR 的加密 Vault，
/// 覆盖其中的历史（见 DebugVaultSeed），并且不启动剪贴板监听，截图里不会出现真实剪贴板内容。条目照着 docs/design/ui-upgrade 的画板排列，
/// 全部虚构；裸可执行文件只显示英文界面，所以文案也是英文
enum DesignDemoHistory {
    static let argument = "--demo-history"

    static var isRequested: Bool {
        CommandLine.arguments.contains(argument)
    }

    /// 写入演示历史；未设置 CUBBY_DATA_DIR 时什么都不写（绝不覆盖真实历史），返回 false
    @MainActor
    static func seed(now: Date = Date()) -> Bool {
        guard let dataDirectory = ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"], !dataDirectory.isEmpty
        else { return false }
        do {
            let vault = try DebugVaultSeed.prepare()
            let file = try demoFile(in: URL(fileURLWithPath: dataDirectory, isDirectory: true))
            let items = try ordered(entries(file: file)).enumerated().map { index, entry in
                try entry.item(id: id(index), now: now, blobs: vault.blobs)
            }
            try vault.storage.save(ClipHistory(items: items))
            // 地址守护的演示记录：被替换进来的那一条关联到演示历史里的红色记录
            if let tampered = items.first(where: { $0.text == SecurityDemo.replacement.value }) {
                try SecurityLogStore(dataDirectory: AppPaths.root, vault: AppPaths.vault, keys: vault.keys).save(
                    SecurityDemo.log(tamperedItemID: tampered.id, now: now))
            }
            return true
        } catch {
            FileHandle.standardError.write(Data("Seeding the design demo history failed: \(error)\n".utf8))
            return false
        }
    }

    /// README 首图（`--demo-hero`）：文件卡提到第五条（紧跟颜色卡、在图片之前，时间改到今天），
    /// 首屏就能看到文字、链接、代码、颜色、文件与图片
    static let heroArgument = "--demo-hero"
    private static let heroFilePosition = 4
    private static let heroFileMinutes: Double = 17
    private static let heroNote = "Thursday: record the demo GIF and ship 0.3."

    private static func ordered(_ entries: [Entry]) -> [Entry] {
        guard CommandLine.arguments.contains(heroArgument),
            let index = entries.firstIndex(where: { if case .files = $0.content { true } else { false } })
        else { return entries }
        var reordered = entries
        // 第一条笔记缩成一行，给图片卡留出位置
        if let first = reordered.first, case .text = first.content {
            reordered[0] = Entry(content: .text(heroNote), app: first.app, minutes: first.minutes)
        }
        let file = reordered.remove(at: index)
        let today = Entry(content: file.content, app: file.app, minutes: heroFileMinutes)
        reordered.insert(today, at: min(heroFilePosition, reordered.count))
        return reordered
    }

    private static func id(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "D35160D0-0000-4000-8000-%012d", index + 1)) ?? UUID()
    }

    /// 首图里文件卡指向的系统字体（只读、每台 Mac 都有；路径比临时目录好看）
    private static let heroFile = "/System/Library/Fonts/NewYork.ttf"

    /// 文件卡指向的演示文件：放在数据目录里，不涉及真实文件（首图用只读的系统字体文件）
    private static func demoFile(in directory: URL) throws -> String {
        if CommandLine.arguments.contains(heroArgument), FileManager.default.fileExists(atPath: heroFile) {
            return heroFile
        }
        let folder = directory.appendingPathComponent("Documents/Work", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Quarterly Report.key")
        if !FileManager.default.fileExists(atPath: file.path) {
            try Data().write(to: file)
        }
        return file.path
    }

    private static let day: Double = 24 * 60

    private static func entries(file: String) -> [Entry] {
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
            // 地址守护（PanelSecurity 设计稿）：放在最后，不影响其他画板的前几条
            .text(SecurityDemo.original.value, app: ("com.apple.Safari", "Safari"), minutes: 3 * day),
            .text(SecurityDemo.replacement.value, app: nil, minutes: 3 * day + 1),
            .text(SecurityDemo.tron.value, app: ("com.tencent.xinWeChat", "WeChat"), minutes: 3 * day + 12),
            .text(SecurityDemo.bankCard, app: ("com.apple.Notes", "Notes"), minutes: 4 * day),
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
        /// nil：来源未知（被替换进来的内容）
        let app: (bundleID: String, name: String)?
        let minutes: Double
        var favorite = false
        /// 链接条目复制时浏览器带来的页面标题
        var linkTitle: String?

        static func text(
            _ value: String, app: (String, String)?, minutes: Double, favorite: Bool = false, linkTitle: String? = nil
        ) -> Entry {
            Entry(content: .text(value), app: app, minutes: minutes, favorite: favorite, linkTitle: linkTitle)
        }

        static func image(_ scene: DesignDemoImages.Scene, app: (String, String), minutes: Double) -> Entry {
            Entry(content: .image(scene), app: app, minutes: minutes)
        }

        static func files(_ paths: [String], app: (String, String), minutes: Double) -> Entry {
            Entry(content: .files(paths), app: app, minutes: minutes)
        }

        func item(id: UUID, now: Date, blobs: any ClipBlobStoring) throws -> ClipItem {
            let source = app.map { SourceApp(bundleID: $0.bundleID, name: $0.name) }
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
                let name = blobs.name(kind: .image, contentHash: digest)
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
