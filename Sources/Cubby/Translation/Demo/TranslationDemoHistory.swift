#if DEBUG
import AppKit
import CubbyCore

/// 剪贴板翻译演示场景（`--scenario translate-demo:text|image`）的演示历史：启动时写入 CUBBY_DATA_DIR，
/// 覆盖其中的 history.json。内容全部虚构；要翻译的条目（英文邮件、旅行应用的欢迎页图片）排在最前面并被选中，
/// 其译文在 DemoTranslationTable 里。其余条目按界面语言显示中文或英文，汉字写成 Unicode 转义。
/// 不放链接条目：宣传图（例如小红书）里不能出现站外链接
enum TranslationDemoHistory {
    /// 英文邮件：两段，与 DemoTranslationTable 中的原文一致
    static let email = """
        Thanks for the great workshop last week! The team loved the prototype, and we\u{2019}d like to move ahead \
        with the redesign.

        Could you send us a revised timeline by Friday? If the first milestone lands before the holidays, we can \
        present it at our January planning meeting.
        """

    /// 写入演示历史；未设置 CUBBY_DATA_DIR 时什么都不写（绝不覆盖真实历史），返回 false
    static func seed(_ demo: PanelTranslationDemo) -> Bool {
        guard ProcessInfo.processInfo.environment["CUBBY_DATA_DIR"]?.isEmpty == false else { return false }
        do {
            let blobs = BlobStore(directory: AppPaths.imagesDirectory)
            let items = try entries(demo, blobs: blobs, now: Date())
            try JSONHistoryStorage(fileURL: AppPaths.historyFile).save(ClipHistory(items: items))
            return true
        } catch {
            FileHandle.standardError.write(Data("Seeding the translation demo failed: \(error)\n".utf8))
            return false
        }
    }

    private static func entries(_ demo: PanelTranslationDemo, blobs: BlobStore, now: Date) throws -> [ClipItem] {
        let copy = Copy.current
        let image = try imageItem(blobs: blobs, name: copy.preview)
        let makers: [(UUID, Date) -> ClipItem] = [
            { text(email, bundleID: "com.apple.mail", app: copy.mail, id: $0, date: $1) },
            { text(copy.note, bundleID: "com.apple.Notes", app: copy.notes, id: $0, date: $1) },
            { text(copy.chat, bundleID: "com.apple.MobileSMS", app: copy.messages, id: $0, date: $1) },
            { text(code, bundleID: "com.apple.dt.Xcode", app: "Xcode", id: $0, date: $1) },
            {
                text(
                    "#5F2EEA", bundleID: "com.apple.DigitalColorMeter", app: copy.colorMeter, id: $0, date: $1,
                    favorite: true)
            },
            image,
        ]
        // 图片场景：图片是最新的一条
        let ordered = demo == .image ? [image] + makers.dropLast() : makers
        let minutes: [Double] = [0.2, 2.5, 6.5, 14.5, 32.5, 47.5]
        return zip(ordered, minutes).enumerated().map { index, pair in
            let id = UUID(uuidString: String(format: "7D3A0000-0000-4000-8000-%012d", index + 1)) ?? UUID()
            return pair.0(id, now.addingTimeInterval(-pair.1 * 60))
        }
    }

    private static let code = "Text(\"Ship it!\")\n    .font(.headline)\n    .foregroundStyle(.purple)"

    private static func text(
        _ value: String, bundleID: String, app: String, id: UUID, date: Date, favorite: Bool = false
    ) -> ClipItem {
        ClipItem(
            id: id, kind: ContentClassifier.kind(forText: value), payload: .text(value),
            source: SourceApp(bundleID: bundleID, name: app), createdAt: date, isFavorite: favorite,
            contentHash: ContentHasher.hash(text: value))
    }

    /// 把演示图片写进图片目录，返回生成条目的闭包
    private static func imageItem(blobs: BlobStore, name: String) throws -> (UUID, Date) -> ClipItem {
        let png = try TranslationDemoImage.png()
        let digest = ContentHasher.sha256(png)
        let file = "\(digest).png"
        try blobs.write(png, name: file)
        let size = TranslationDemoImage.pixelSize
        return { id, date in
            ClipItem(
                id: id, kind: .image,
                payload: .image(ImageRef(name: file, width: Int(size.width), height: Int(size.height))),
                source: SourceApp(bundleID: "com.apple.Preview", name: name), createdAt: date,
                contentHash: ContentHasher.hash(imageDigest: digest), recognizedText: TranslationDemoImage.allText)
        }
    }

    /// 来源应用的显示名与备忘录、信息条目：跟随界面语言
    private struct Copy {
        let mail: String
        let notes: String
        let messages: String
        let colorMeter: String
        let preview: String
        let note: String
        let chat: String

        static var current: Copy {
            Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? chinese : english
        }

        static let english = Copy(
            mail: "Mail", notes: "Notes", messages: "Messages", colorMeter: "Digital Color Meter", preview: "Preview",
            note: "Thursday launch: record the demo GIF and update the Homebrew cask.",
            chat: "Could you send over the final icon exports? The 1024 px one looks a little soft on Retina.")

        static let chinese = Copy(
            // 邮件
            mail: "\u{90AE}\u{4EF6}",
            // 备忘录
            notes: "\u{5907}\u{5FD8}\u{5F55}",
            // 信息
            messages: "\u{4FE1}\u{606F}",
            // 数码测色计
            colorMeter: "\u{6570}\u{7801}\u{6D4B}\u{8272}\u{8BA1}",
            // 预览
            preview: "\u{9884}\u{89C8}",
            // 周四发布前：录好演示动图，更新 Homebrew cask。
            note: """
                \u{5468}\u{56DB}\u{53D1}\u{5E03}\u{524D}\u{FF1A}\u{5F55}\u{597D}\u{6F14}\u{793A}\u{52A8}\u{56FE}\
                \u{FF0C}\u{66F4}\u{65B0} Homebrew cask\u{3002}
                """,
            // 图标最终版能发我一下吗？1024 px 那张在 Retina 屏上看着有点虚。
            chat: """
                \u{56FE}\u{6807}\u{6700}\u{7EC8}\u{7248}\u{80FD}\u{53D1}\u{6211}\u{4E00}\u{4E0B}\u{5417}\u{FF1F}\
                1024 px \u{90A3}\u{5F20}\u{5728} Retina \u{5C4F}\u{4E0A}\u{770B}\u{7740}\u{6709}\u{70B9}\u{865A}\u{3002}
                """)
    }
}
#endif
