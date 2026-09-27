#if DEBUG
import Foundation

/// README 展示场景（`--scenario screenshot:showcase`）的文案：界面语言为简体中文时用中文，否则英文。
/// 汉字一律写成 Unicode 转义（源码中不出现汉字字面量），上一行注释给出原文。
/// 画面全部是虚构内容：发布说明，以及一个天气窗口（不放任何关于 Cubby 本身的统计数字）
struct ShowcaseCopy: Sendable {
    /// 天气窗口的一块指标卡：标签、数值与右侧的简短说明
    struct Tile: Sendable {
        let label: String
        let value: String
        let detail: String
    }

    let notesTitle: String
    let heading: String
    let subtitle: String
    let whatsNew: String
    let bullets: [String]
    let feedback: String
    let contactPrefix: String
    /// 虚构的邮箱（example.com 是保留域名），展示马赛克的遮挡效果
    let email: String
    let weatherTitle: String
    let city: String
    let outlook: String
    let tiles: [Tile]
    /// 七天预报柱状图下方的首尾两天
    let firstDay: String
    let lastDay: String
    /// 文字标注
    let callout: String

    static var current: ShowcaseCopy {
        Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static let english = ShowcaseCopy(
        notesTitle: "Release Notes.md",
        heading: "Cubby 0.2",
        subtitle: "Release notes \u{B7} September 2026",
        whatsNew: "What\u{2019}s new",
        bullets: [
            "Mark up screenshots with \u{21E7}\u{2318}2",
            "Search images by the text in them",
            "Pin any image to the screen",
            "Liquid Glass on macOS 26",
        ],
        feedback: "Feedback",
        contactPrefix: "Questions? Write to ",
        email: "jamie.chen@example.com",
        weatherTitle: "Weather",
        city: "Lisbon",
        outlook: "Mostly sunny all week",
        tiles: [
            Tile(label: "Now", value: "24\u{B0}", detail: "Sunny"),
            Tile(label: "UV index", value: "6", detail: "High"),
        ],
        firstDay: "Mon",
        lastDay: "Sun",
        callout: "Beach day!"
    )

    /// 截图翻译演示（`screenshot:translate-demo`）的原文：不论界面语言都是英文。
    /// 第一条要点换成不含快捷键符号的句子（⇧⌘ 这类符号本来就不是要翻译的文字）；
    /// 反馈一行不放蓝色邮箱，整行同一种颜色，演示的是一句完整的话
    static let translationSource = ShowcaseCopy(
        notesTitle: english.notesTitle,
        heading: english.heading,
        subtitle: english.subtitle,
        whatsNew: english.whatsNew,
        bullets: ["Translate screenshots in place"] + english.bullets.dropFirst(),
        feedback: english.feedback,
        contactPrefix: "Questions? See the user guide.",
        email: "",
        weatherTitle: english.weatherTitle,
        city: english.city,
        outlook: english.outlook,
        tiles: english.tiles,
        firstDay: english.firstDay,
        lastDay: english.lastDay,
        callout: english.callout
    )

    static let chinese = ShowcaseCopy(
        // 发布说明.md
        notesTitle: "\u{53D1}\u{5E03}\u{8BF4}\u{660E}.md",
        heading: "Cubby 0.2",
        // 发布说明 · 2026 年 9 月
        subtitle: "\u{53D1}\u{5E03}\u{8BF4}\u{660E} \u{B7} 2026 \u{5E74} 9 \u{6708}",
        // 新功能
        whatsNew: "\u{65B0}\u{529F}\u{80FD}",
        bullets: [
            // 截图后直接标注：⇧⌘2
            "\u{622A}\u{56FE}\u{540E}\u{76F4}\u{63A5}\u{6807}\u{6CE8}\u{FF1A}\u{21E7}\u{2318}2",
            // 按图中的文字搜索图片
            "\u{6309}\u{56FE}\u{4E2D}\u{7684}\u{6587}\u{5B57}\u{641C}\u{7D22}\u{56FE}\u{7247}",
            // 把任意图片贴到屏幕上
            "\u{628A}\u{4EFB}\u{610F}\u{56FE}\u{7247}\u{8D34}\u{5230}\u{5C4F}\u{5E55}\u{4E0A}",
            // macOS 26 上的 Liquid Glass
            "macOS 26 \u{4E0A}\u{7684} Liquid Glass",
        ],
        // 反馈
        feedback: "\u{53CD}\u{9988}",
        // 有问题？请写信到
        contactPrefix: "\u{6709}\u{95EE}\u{9898}\u{FF1F}\u{8BF7}\u{5199}\u{4FE1}\u{5230} ",
        email: "jamie.chen@example.com",
        // 天气
        weatherTitle: "\u{5929}\u{6C14}",
        // 里斯本
        city: "\u{91CC}\u{65AF}\u{672C}",
        // 本周大多晴朗
        outlook: "\u{672C}\u{5468}\u{5927}\u{591A}\u{6674}\u{6717}",
        tiles: [
            // 现在 · 晴
            Tile(label: "\u{73B0}\u{5728}", value: "24\u{B0}", detail: "\u{6674}"),
            // 紫外线指数 · 强
            Tile(label: "\u{7D2B}\u{5916}\u{7EBF}\u{6307}\u{6570}", value: "6", detail: "\u{5F3A}"),
        ],
        // 周一
        firstDay: "\u{5468}\u{4E00}",
        // 周日
        lastDay: "\u{5468}\u{65E5}",
        // 去海边！
        callout: "\u{53BB}\u{6D77}\u{8FB9}\u{FF01}"
    )
}
#endif
