#if DEBUG
import AppKit
import CubbyCore
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// 面板 E2E 与翻译走查的演示条目（全部虚构，与原型 docs/prototypes/clipboard-translate.html 一致）。
/// 文本用受限 Markdown 书写：「# 」标题、「- 」列表项、**粗体**、[文字](链接)、`代码`；段落以空行分隔。
/// 中日文用 Unicode 转义书写（源码字符串字面量不得含汉字，见 scripts/check-no-cjk.sh），内容即原型里的演示文字
enum PanelE2EFixtures {
    struct Entry {
        let key: String
        let text: String?
        let isImage: Bool
        let bundleID: String
        let appName: String
        let minutesAgo: Double
        var isFavorite = false
        /// 富文本条目：译文按结构粘贴（RTF / HTML）
        var isRich = false
        /// 源语言（BCP-47）；nil 表示不适用（代码、链接、颜色）
        var source: String?
        /// 各目标语言的逐段译文（与段落一一对应）
        var translations: [String: [String]] = [:]
        /// 预先缓存在条目上的目标语言（「译」角标）
        var cachedTargets: [String] = []
    }

    /// 与原型一致的「软件更新」对话框截图（1600 × 1000 像素，144 DPI = 800 × 500 点）
    static let imagePixelSize = CGSize(width: 1600, height: 1000)
    static let imageScale: CGFloat = 2
    static let imageTexts = [
        "Software Update",
        "Version 2.4 is ready to install. It includes important security fixes and takes about five minutes. Your Mac will restart when the update is complete.",
        "Automatically keep my Mac up to date", "Later", "Update Now",
    ]
    static let imageTranslations = [
        "zh-Hans": [
            "\u{8F6F}\u{4EF6}\u{66F4}\u{65B0}",
            """
            2.4 \u{7248}\u{5DF2}\u{53EF}\u{5B89}\u{88C5}\u{3002}\u{6B64}\u{66F4}\u{65B0}\u{5305}\u{542B}\u{91CD}\
            \u{8981}\u{7684}\u{5B89}\u{5168}\u{4FEE}\u{590D}\u{FF0C}\u{5927}\u{7EA6}\u{9700}\u{8981} 5 \u{5206}\
            \u{949F}\u{3002}\u{66F4}\u{65B0}\u{5B8C}\u{6210}\u{540E}\u{FF0C}Mac \u{5C06}\u{91CD}\u{65B0}\u{542F}\
            \u{52A8}\u{3002}
            """,
            """
            \u{81EA}\u{52A8}\u{4FDD}\u{6301} Mac \u{4E3A}\u{6700}\u{65B0}\u{7248}\u{672C}
            """, "\u{7A0D}\u{540E}", "\u{7ACB}\u{5373}\u{66F4}\u{65B0}",
        ],
        "ja": [
            """
            \u{30BD}\u{30D5}\u{30C8}\u{30A6}\u{30A7}\u{30A2}\u{30FB}\u{30A2}\u{30C3}\u{30D7}\u{30C7}\u{30FC}\
            \u{30C8}
            """,
            """
            \u{30D0}\u{30FC}\u{30B8}\u{30E7}\u{30F3} 2.4 \u{3092}\u{30A4}\u{30F3}\u{30B9}\u{30C8}\u{30FC}\
            \u{30EB}\u{3067}\u{304D}\u{307E}\u{3059}\u{3002}\u{91CD}\u{8981}\u{306A}\u{30BB}\u{30AD}\u{30E5}\
            \u{30EA}\u{30C6}\u{30A3}\u{4FEE}\u{6B63}\u{304C}\u{542B}\u{307E}\u{308C}\u{3066}\u{304A}\u{308A}\
            \u{3001}\u{6240}\u{8981}\u{6642}\u{9593}\u{306F}\u{7D04} 5 \u{5206}\u{3067}\u{3059}\u{3002}\u{30A2}\
            \u{30C3}\u{30D7}\u{30C7}\u{30FC}\u{30C8}\u{304C}\u{5B8C}\u{4E86}\u{3059}\u{308B}\u{3068} Mac \u{304C}\
            \u{518D}\u{8D77}\u{52D5}\u{3057}\u{307E}\u{3059}\u{3002}
            """,
            """
            Mac \u{3092}\u{81EA}\u{52D5}\u{7684}\u{306B}\u{6700}\u{65B0}\u{306E}\u{72B6}\u{614B}\u{306B}\u{4FDD}\
            \u{3064}
            """, "\u{3042}\u{3068}\u{3067}",
            """
            \u{4ECA}\u{3059}\u{3050}\u{30A2}\u{30C3}\u{30D7}\u{30C7}\u{30FC}\u{30C8}
            """,
        ],
    ]

    static let entries: [Entry] = [
        Entry(
            key: "mail",
            text:
                "Quick update on the 2.4 launch: we’re moving the release from Tuesday to Thursday. Notarization flagged two helper binaries, and we need a clean build before we ship.\n\nUntil then, please hold all non-critical merges to main. Fixes for the release branch are still welcome — just tag them “2.4-blocker” so we can review them first.",
            isImage: false, bundleID: "com.apple.mail", appName: "Mail", minutesAgo: 0, source: "en",
            translations: [
                "zh-Hans": [
                    """
                    2.4 \u{7248}\u{672C}\u{53D1}\u{5E03}\u{7684}\u{6700}\u{65B0}\u{8FDB}\u{5C55}\u{FF1A}\u{53D1}\
                    \u{5E03}\u{65E5}\u{671F}\u{4ECE}\u{5468}\u{4E8C}\u{63A8}\u{8FDF}\u{5230}\u{5468}\u{56DB}\
                    \u{3002}\u{516C}\u{8BC1}\u{68C0}\u{67E5}\u{6807}\u{8BB0}\u{4E86}\u{4E24}\u{4E2A}\u{8F85}\
                    \u{52A9}\u{4E8C}\u{8FDB}\u{5236}\u{6587}\u{4EF6}\u{FF0C}\u{6211}\u{4EEC}\u{9700}\u{8981}\
                    \u{5148}\u{62FF}\u{5230}\u{4E00}\u{4E2A}\u{5E72}\u{51C0}\u{7684}\u{6784}\u{5EFA}\u{518D}\
                    \u{53D1}\u{5E03}\u{3002}
                    """,
                    """
                    \u{5728}\u{6B64}\u{4E4B}\u{524D}\u{FF0C}\u{8BF7}\u{6682}\u{505C}\u{5411} main \u{5408}\
                    \u{5E76}\u{6240}\u{6709}\u{975E}\u{5173}\u{952E}\u{6539}\u{52A8}\u{3002}\u{53D1}\u{5E03}\
                    \u{5206}\u{652F}\u{7684}\u{4FEE}\u{590D}\u{4ECD}\u{7136}\u{6B22}\u{8FCE}——\u{53EA}\u{9700}\
                    \u{52A0}\u{4E0A}“2.4-blocker”\u{6807}\u{7B7E}\u{FF0C}\u{65B9}\u{4FBF}\u{6211}\u{4EEC}\
                    \u{4F18}\u{5148}\u{5BA1}\u{6838}\u{3002}
                    """,
                ],
                "ja": [
                    """
                    2.4 \u{306E}\u{30EA}\u{30EA}\u{30FC}\u{30B9}\u{306B}\u{3064}\u{3044}\u{3066}\u{304A}\u{77E5}\
                    \u{3089}\u{305B}\u{3067}\u{3059}\u{3002}\u{30EA}\u{30EA}\u{30FC}\u{30B9}\u{65E5}\u{3092}\
                    \u{706B}\u{66DC}\u{65E5}\u{304B}\u{3089}\u{6728}\u{66DC}\u{65E5}\u{306B}\u{5909}\u{66F4}\
                    \u{3057}\u{307E}\u{3059}\u{3002}\u{516C}\u{8A3C}\u{3067} 2 \u{3064}\u{306E}\u{30D8}\u{30EB}\
                    \u{30D1}\u{30FC}\u{30D0}\u{30A4}\u{30CA}\u{30EA}\u{304C}\u{6307}\u{6458}\u{3055}\u{308C}\
                    \u{305F}\u{305F}\u{3081}\u{3001}\u{51FA}\u{8377}\u{524D}\u{306B}\u{30AF}\u{30EA}\u{30FC}\
                    \u{30F3}\u{306A}\u{30D3}\u{30EB}\u{30C9}\u{3092}\u{7528}\u{610F}\u{3059}\u{308B}\u{5FC5}\
                    \u{8981}\u{304C}\u{3042}\u{308A}\u{307E}\u{3059}\u{3002}
                    """,
                    """
                    \u{305D}\u{308C}\u{307E}\u{3067}\u{306F}\u{3001}main \u{3078}\u{306E}\u{91CD}\u{8981}\
                    \u{5EA6}\u{306E}\u{4F4E}\u{3044}\u{30DE}\u{30FC}\u{30B8}\u{306F}\u{3059}\u{3079}\u{3066}\
                    \u{4FDD}\u{7559}\u{3057}\u{3066}\u{304F}\u{3060}\u{3055}\u{3044}\u{3002}\u{30EA}\u{30EA}\
                    \u{30FC}\u{30B9}\u{30D6}\u{30E9}\u{30F3}\u{30C1}\u{5411}\u{3051}\u{306E}\u{4FEE}\u{6B63}\
                    \u{306F}\u{5F15}\u{304D}\u{7D9A}\u{304D}\u{6B53}\u{8FCE}\u{3057}\u{307E}\u{3059}\u{3002}\
                    \u{5148}\u{306B}\u{30EC}\u{30D3}\u{30E5}\u{30FC}\u{3067}\u{304D}\u{308B}\u{3088}\u{3046}\
                    \u{300C}2.4-blocker\u{300D}\u{30BF}\u{30B0}\u{3092}\u{4ED8}\u{3051}\u{3066}\u{304F}\u{3060}\
                    \u{3055}\u{3044}\u{3002}
                    """,
                ],
            ]),
        Entry(
            key: "notes",
            text: """
                \u{5468}\u{56DB}\u{53D1}\u{5E03}\u{524D}\u{FF1A}\u{5F55}\u{597D}\u{6F14}\u{793A}\u{52A8}\u{56FE}\
                \u{FF0C}\u{66F4}\u{65B0} README \u{622A}\u{56FE}\u{FF0C}\u{5E76}\u{786E}\u{8BA4}\u{516C}\u{8BC1}\
                \u{901A}\u{8FC7}\u{3002}
                """, isImage: false,
            bundleID: "com.apple.Notes", appName: "Notes", minutesAgo: 3, source: "zh-Hans",
            translations: [
                "en": [
                    "Before Thursday’s release: record the demo GIFs, update the README screenshots, and confirm notarization has passed."
                ]
            ]),
        Entry(
            key: "article",
            text:
                "# Why local-first apps feel instant\n\nWhen your data lives on the device, every interaction skips the **network round trip**. Search results appear as you type, and nothing waits on a spinner.\n\nSync still matters, but it moves to the background. [Read the full guide](https://example.com/local-first) for the details.\n\n- Reads and writes hit local storage first, usually `SQLite` in WAL mode\n\n- Conflicts are resolved with **clear, predictable** rules\n\n- The cloud becomes a backup, not a dependency",
            isImage: false, bundleID: "com.apple.Safari", appName: "Safari", minutesAgo: 8, isRich: true, source: "en",
            translations: [
                "zh-Hans": [
                    """
                    # \u{4E3A}\u{4EC0}\u{4E48}\u{672C}\u{5730}\u{4F18}\u{5148}\u{7684}\u{5E94}\u{7528}\u{7528}\
                    \u{8D77}\u{6765}\u{6BEB}\u{65E0}\u{5EF6}\u{8FDF}
                    """,
                    """
                    \u{5F53}\u{6570}\u{636E}\u{4FDD}\u{5B58}\u{5728}\u{8BBE}\u{5907}\u{4E0A}\u{65F6}\u{FF0C}\
                    \u{6BCF}\u{4E00}\u{6B21}\u{64CD}\u{4F5C}\u{90FD}\u{7701}\u{53BB}\u{4E86}**\u{7F51}\u{7EDC}\
                    \u{5F80}\u{8FD4}**\u{3002}\u{641C}\u{7D22}\u{7ED3}\u{679C}\u{968F}\u{8F93}\u{5165}\u{5373}\
                    \u{65F6}\u{51FA}\u{73B0}\u{FF0C}\u{4E0D}\u{5FC5}\u{76EF}\u{7740}\u{52A0}\u{8F7D}\u{52A8}\
                    \u{753B}\u{7B49}\u{5F85}\u{3002}
                    """,
                    """
                    \u{540C}\u{6B65}\u{4F9D}\u{7136}\u{91CD}\u{8981}\u{FF0C}\u{53EA}\u{662F}\u{9000}\u{5230}\
                    \u{4E86}\u{540E}\u{53F0}\u{3002}\u{8BE6}\u{60C5}\u{8BF7}[\u{9605}\u{8BFB}\u{5B8C}\u{6574}\
                    \u{6307}\u{5357}](https://example.com/local-first)\u{3002}
                    """,
                    """
                    - \u{8BFB}\u{5199}\u{64CD}\u{4F5C}\u{4F18}\u{5148}\u{843D}\u{5230}\u{672C}\u{5730}\u{5B58}\
                    \u{50A8}\u{FF0C}\u{901A}\u{5E38}\u{662F} WAL \u{6A21}\u{5F0F}\u{4E0B}\u{7684} `SQLite`
                    """,
                    """
                    - \u{51B2}\u{7A81}\u{6309}**\u{6E05}\u{6670}\u{3001}\u{53EF}\u{9884}\u{671F}**\u{7684}\
                    \u{89C4}\u{5219}\u{89E3}\u{51B3}
                    """,
                    """
                    - \u{4E91}\u{7AEF}\u{6210}\u{4E3A}\u{5907}\u{4EFD}\u{FF0C}\u{800C}\u{4E0D}\u{662F}\u{4F9D}\
                    \u{8D56}
                    """,
                ]
            ]),
        Entry(
            key: "line",
            text: """
                \u{660E}\u{65E5}\u{306E}\u{4F1A}\u{8B70}\u{306F}\u{5348}\u{5F8C}3\u{6642}\u{306B}\u{5909}\u{66F4}\
                \u{306B}\u{306A}\u{308A}\u{307E}\u{3057}\u{305F}\u{3002}\u{8CC7}\u{6599}\u{306F}\u{4E8B}\u{524D}\
                \u{306B}\u{5171}\u{6709}\u{3057}\u{307E}\u{3059}\u{3002}
                """, isImage: false,
            bundleID: "jp.naver.line.mac", appName: "LINE", minutesAgo: 12, source: "ja",
            translations: [
                "zh-Hans": [
                    """
                    \u{660E}\u{5929}\u{7684}\u{4F1A}\u{8BAE}\u{6539}\u{5230}\u{4E0B}\u{5348} 3 \u{70B9}\u{4E86}\
                    \u{3002}\u{8D44}\u{6599}\u{4F1A}\u{63D0}\u{524D}\u{5171}\u{4EAB}\u{3002}
                    """
                ],
                "en": ["Tomorrow’s meeting has been moved to 3 p.m. I’ll share the materials in advance."],
            ],
            cachedTargets: ["zh-Hans"]),
        Entry(
            key: "code", text: "Text(\"Ship it!\")\n    .font(.headline)\n    .foregroundStyle(.purple)",
            isImage: false, bundleID: "com.apple.dt.Xcode", appName: "Xcode", minutesAgo: 18),
        Entry(
            key: "link", text: "https://github.com/no1coder/cubby", isImage: false, bundleID: "com.apple.Safari",
            appName: "Safari", minutesAgo: 25),
        Entry(
            key: "image", text: nil, isImage: true, bundleID: "com.apple.Preview", appName: "Preview", minutesAgo: 32,
            source: "en"),
        Entry(
            key: "color", text: "#5F2EEA", isImage: false, bundleID: "com.apple.DigitalColorMeter",
            appName: "Digital Color Meter", minutesAgo: 41, isFavorite: true),
        Entry(
            key: "terminal",
            text:
                "Deploy failed: the API key sk_live_51HqDEMO7fX2kP9rT0nL was rejected because it has expired. Rotate the key in the dashboard, then run the deploy again.",
            isImage: false, bundleID: "com.apple.Terminal", appName: "Terminal", minutesAgo: 63, source: "en",
            translations: [
                "zh-Hans": [
                    """
                    \u{90E8}\u{7F72}\u{5931}\u{8D25}\u{FF1A}API \u{5BC6}\u{94A5} sk_live_51HqDEMO7fX2kP9rT0nL \u{5DF2}\
                    \u{8FC7}\u{671F}\u{FF0C}\u{56E0}\u{800C}\u{88AB}\u{62D2}\u{7EDD}\u{3002}\u{8BF7}\u{5728}\u{63A7}\
                    \u{5236}\u{53F0}\u{4E2D}\u{8F6E}\u{6362}\u{5BC6}\u{94A5}\u{FF0C}\u{7136}\u{540E}\u{91CD}\u{65B0}\
                    \u{8FD0}\u{884C}\u{90E8}\u{7F72}\u{3002}
                    """
                ]
            ]),
    ]

    /// 只在 LINE 条目的中文译文里出现的词（「资料」），用于「只因译文命中搜索」
    static let translationOnlyKeyword = "\u{8D44}\u{6599}"

    /// 某条在某目标语言下完整译文的纯文本（与桩翻译的拼接规则一致）
    static func plainTranslation(_ key: String, _ target: String) -> String? {
        entries.first { $0.key == key }?.translations[target]
            .map { $0.map(plainText(markdown:)).joined(separator: "\n\n") }
    }

    /// 固定的条目 id（脚本按 key 取条目）
    static func id(_ key: String) -> UUID {
        let index = entries.firstIndex { $0.key == key } ?? 0
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1)) ?? UUID()
    }

    static func key(for id: UUID) -> String? {
        entry(for: id)?.key
    }

    static func entry(for id: UUID) -> Entry? {
        entries.first { self.id($0.key) == id }
    }

    /// 按空行分段（与桩翻译一致）
    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
    }

    /// 写入演示历史：文本条目直接构造，图片写入 blob；预先缓存的译文放进 ClipItem.translations
    static func history(blobs: BlobStore, now: Date) throws -> ClipHistory {
        let items = try entries.map { entry in try item(for: entry, blobs: blobs, now: now) }
        return ClipHistory(items: items)
    }

    private static func item(for entry: Entry, blobs: BlobStore, now: Date) throws -> ClipItem {
        let created = now.addingTimeInterval(-entry.minutesAgo * 60)
        let source = SourceApp(bundleID: entry.bundleID, name: entry.appName)
        let translations = cachedTranslations(entry, now: now)
        guard entry.isImage else {
            let text = entry.text ?? ""
            let plain = entry.isRich ? plainText(markdown: text) : text
            return ClipItem(
                id: id(entry.key), kind: ContentClassifier.kind(forText: plain), payload: .text(plain), source: source,
                createdAt: created, isFavorite: entry.isFavorite, contentHash: ContentHasher.hash(text: plain),
                translations: translations)
        }
        let png = try imagePNG()
        let digest = ContentHasher.sha256(png)
        let name = "\(digest).png"
        try blobs.write(png, name: name)
        return ClipItem(
            id: id(entry.key), kind: .image,
            payload: .image(ImageRef(name: name, width: Int(imagePixelSize.width), height: Int(imagePixelSize.height))),
            source: source, createdAt: created, contentHash: ContentHasher.hash(imageDigest: digest))
    }

    private static func cachedTranslations(_ entry: Entry, now: Date) -> ClipTranslations? {
        let cached = entry.cachedTargets.compactMap { target -> ClipTranslation? in
            guard let segments = entry.translations[target] else { return nil }
            return ClipTranslation(
                target: target, source: entry.source, engineName: PanelE2EStubTranslator.systemEngineName,
                isOnDevice: true, createdAt: now, segmentation: 1, segments: segments.map { Optional($0) })
        }
        return cached.isEmpty ? nil : ClipTranslations(cached)
    }

    /// 去掉受限 Markdown 的行内标记（**粗体**、[文字](链接)、`代码`）
    private static func stripMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[(.+?)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
    }

    /// 受限 Markdown → 条目里保存的纯文本（去掉标记，标题与列表保留文字）
    static func plainText(markdown: String) -> String {
        paragraphs(markdown).map { paragraph in
            let body = paragraph.hasPrefix("# ") ? String(paragraph.dropFirst(2)) : paragraph
            let listed = body.hasPrefix("- ") ? "• " + body.dropFirst(2) : Substring(body)
            return stripMarkup(String(listed))
        }
        .joined(separator: "\n\n")
    }

    // MARK: - 图片

    /// 五块文字的位置与字号（图片点，左上原点；原型 400 × 250 的对话框放大 2 倍）与样式：标题、正文、复选框、两个按钮
    struct ImageBlockLayout {
        let frame: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let background: PixelColor
        let color: PixelColor
    }

    static let imageBlocks: [ImageBlockLayout] = [
        ImageBlockLayout(
            frame: CGRect(x: 184, y: 44, width: 420, height: 48), fontSize: 30, isBold: true,
            background: dialogColor, color: PixelColor(red: 0.11, green: 0.11, blue: 0.12)),
        ImageBlockLayout(
            frame: CGRect(x: 184, y: 104, width: 568, height: 140), fontSize: 24, isBold: false,
            background: dialogColor, color: PixelColor(red: 0.24, green: 0.24, blue: 0.26)),
        ImageBlockLayout(
            frame: CGRect(x: 226, y: 278, width: 480, height: 40), fontSize: 24, isBold: false,
            background: dialogColor, color: PixelColor(red: 0.11, green: 0.11, blue: 0.12)),
        ImageBlockLayout(
            frame: CGRect(x: 476, y: 412, width: 124, height: 48), fontSize: 24, isBold: false, background: .white,
            color: PixelColor(red: 0.11, green: 0.11, blue: 0.12)),
        ImageBlockLayout(
            frame: CGRect(x: 616, y: 412, width: 164, height: 48), fontSize: 24, isBold: false,
            background: PixelColor(red: 0.04, green: 0.49, blue: 1.0), color: .white),
    ]

    static let dialogColor = PixelColor(red: 0.925, green: 0.925, blue: 0.933)

    /// 画出对话框截图（144 DPI）
    static func imagePNG() throws -> Data {
        guard let image = drawDialog() else { throw FixtureError.drawingFailed }
        return try png(image, scale: imageScale)
    }

    static func png(_ image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw FixtureError.drawingFailed }
        let dpi = 72 * scale
        CGImageDestinationAddImage(
            destination, image,
            [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.drawingFailed }
        return data as Data
    }

    private static func drawDialog() -> CGImage? {
        let size = imagePixelSize
        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.925, green: 0.925, blue: 0.933, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        // 齿轮图标底板（点 (44, 44)，边长 104）
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.54, alpha: 1))
        let icon = 104 * imageScale
        context.fill(CGRect(x: 44 * imageScale, y: size.height - 44 * imageScale - icon, width: icon, height: icon))
        let environment = RenderEnvironment(
            origin: .zero, scale: imageScale, targetPixelSize: size, pixelatedFrame: nil, frameOrigin: .zero)
        TranslationPainter.draw(blocks(texts: imageTexts), in: context, environment: environment)
        return context.makeImage()
    }

    /// 五块文字的版面（图片点）；译文字号略小，与截图翻译「放不下时缩字」的效果接近
    static func blocks(texts: [String], fontScale: CGFloat = 1) -> [TranslatedBlock] {
        zip(imageBlocks, texts).enumerated().map { index, pair in
            let (layout, text) = pair
            return TranslatedBlock(
                blockID: index, eraseFrame: layout.frame, backdrop: .solid(layout.background), text: text,
                textFrame: layout.frame.insetBy(dx: 6, dy: 2), fontSize: layout.fontSize * fontScale,
                isBold: layout.isBold, textColor: layout.color, alignment: .leading)
        }
    }

    /// 第 index 块中心在舞台（E2E 全局矩形）里的位置
    static func stagePoint(of index: Int, in stage: CGRect) -> CGPoint {
        let block = imageBlocks[index].frame
        let points = CGSize(width: imagePixelSize.width / imageScale, height: imagePixelSize.height / imageScale)
        return CGPoint(
            x: stage.minX + block.midX / points.width * stage.width,
            y: stage.minY + block.midY / points.height * stage.height)
    }

    enum FixtureError: Error {
        case drawingFailed
    }
}
#endif
