#if DEBUG
import Foundation

/// 演示翻译的固定译文表（README 与宣传截图用，仅调试构建）：英文原文 → 手写的简体中文译文。
/// 原文全部是虚构的演示内容：展示场景的桌面（ShowcaseCopy.translationSource）、演示邮件与演示图片
/// （TranslationDemoHistory）。汉字写成 Unicode 转义（源码字符串字面量不得含汉字），上一行注释给出原文。
///
/// 查表比较的是「规范化原文」：只保留字母与数字并转成小写，所以识别结果里的空白、标点与大小写差异不影响命中
enum DemoTranslationTable {
    /// 表里只有简体中文译文
    static let target = "zh-Hans"

    struct Pair {
        let source: String
        let chinese: String
    }

    /// 某块原文在目标语言下的译文；表里没有（或目标语言不是简体中文）时为 nil
    static func translation(of text: String, target: String) -> String? {
        guard target == Self.target else { return nil }
        return index[key(text)]
    }

    static func key(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    private static let index: [String: String] = Dictionary(
        pairs.map { (key($0.source), $0.chinese) }, uniquingKeysWith: { first, _ in first })

    private static let pairs: [Pair] = [
        // 截图翻译演示：发布说明窗口
        // 发布说明.md
        Pair(
            source: "Release Notes.md",
            chinese: "\u{53D1}\u{5E03}\u{8BF4}\u{660E}.md"),
        // Cubby 0.2
        Pair(
            source: "Cubby 0.2",
            chinese: "Cubby 0.2"),
        // 发布说明 · 2026 年 9 月
        Pair(
            source: "Release notes \u{B7} September 2026",
            chinese: "\u{53D1}\u{5E03}\u{8BF4}\u{660E} \u{B7} 2026 \u{5E74} 9 \u{6708}"),
        // 新功能
        Pair(
            source: "What\u{2019}s new",
            chinese: "\u{65B0}\u{529F}\u{80FD}"),
        // 原位翻译截图中的文字
        Pair(
            source: "Translate screenshots in place",
            chinese: "\u{539F}\u{4F4D}\u{7FFB}\u{8BD1}\u{622A}\u{56FE}\u{4E2D}\u{7684}\u{6587}\u{5B57}"),
        // 按图中的文字搜索图片
        Pair(
            source: "Search images by the text in them",
            chinese: "\u{6309}\u{56FE}\u{4E2D}\u{7684}\u{6587}\u{5B57}\u{641C}\u{7D22}\u{56FE}\u{7247}"),
        // 把任意图片贴到屏幕上
        Pair(
            source: "Pin any image to the screen",
            chinese: "\u{628A}\u{4EFB}\u{610F}\u{56FE}\u{7247}\u{8D34}\u{5230}\u{5C4F}\u{5E55}\u{4E0A}"),
        // macOS 26 上的 Liquid Glass
        Pair(
            source: "Liquid Glass on macOS 26",
            chinese: "macOS 26 \u{4E0A}\u{7684} Liquid Glass"),
        // 反馈
        Pair(
            source: "Feedback",
            chinese: "\u{53CD}\u{9988}"),
        // 有问题？请查看使用说明。
        Pair(
            source: "Questions? See the user guide.",
            chinese: "\u{6709}\u{95EE}\u{9898}\u{FF1F}\u{8BF7}\u{67E5}\u{770B}\u{4F7F}\u{7528}\u{8BF4}\u{660E}\u{3002}"),
        // 截图翻译演示：天气窗口
        // 天气
        Pair(
            source: "Weather",
            chinese: "\u{5929}\u{6C14}"),
        // 里斯本
        Pair(
            source: "Lisbon",
            chinese: "\u{91CC}\u{65AF}\u{672C}"),
        // 本周大多晴朗
        Pair(
            source: "Mostly sunny all week",
            chinese: "\u{672C}\u{5468}\u{5927}\u{591A}\u{6674}\u{6717}"),
        // 现在
        Pair(
            source: "Now",
            chinese: "\u{73B0}\u{5728}"),
        // 晴
        Pair(
            source: "Sunny",
            chinese: "\u{6674}"),
        // 24° 晴
        Pair(
            source: "24\u{B0} Sunny",
            chinese: "24\u{B0} \u{6674}"),
        // 紫外线指数
        Pair(
            source: "UV index",
            chinese: "\u{7D2B}\u{5916}\u{7EBF}\u{6307}\u{6570}"),
        // 强
        Pair(
            source: "High",
            chinese: "\u{5F3A}"),
        // 6 强
        Pair(
            source: "6 High",
            chinese: "6 \u{5F3A}"),
        // 周一
        Pair(
            source: "Mon",
            chinese: "\u{5468}\u{4E00}"),
        // 周日
        Pair(
            source: "Sun",
            chinese: "\u{5468}\u{65E5}"),
        // 剪贴板翻译演示：邮件
        // 感谢上周精彩的工作坊！团队非常喜欢这个原型，我们希望继续推进这次改版。
        Pair(
            source: """
                Thanks for the great workshop last week! The team loved the prototype, and we\u{2019}d \
                like to move ahead with the redesign.
                """,
            chinese: """
                \u{611F}\u{8C22}\u{4E0A}\u{5468}\u{7CBE}\u{5F69}\u{7684}\u{5DE5}\u{4F5C}\u{574A}\u{FF01}\
                \u{56E2}\u{961F}\u{975E}\u{5E38}\u{559C}\u{6B22}\u{8FD9}\u{4E2A}\u{539F}\u{578B}\u{FF0C}\
                \u{6211}\u{4EEC}\u{5E0C}\u{671B}\u{7EE7}\u{7EED}\u{63A8}\u{8FDB}\u{8FD9}\u{6B21}\u{6539}\
                \u{7248}\u{3002}
                """),
        // 能否在周五前给我们发一份修订后的时间表？如果第一个里程碑能在假期前完成，我们就可以在一月的规划会上展示。
        Pair(
            source: """
                Could you send us a revised timeline by Friday? If the first milestone lands before the \
                holidays, we can present it at our January planning meeting.
                """,
            chinese: """
                \u{80FD}\u{5426}\u{5728}\u{5468}\u{4E94}\u{524D}\u{7ED9}\u{6211}\u{4EEC}\u{53D1}\u{4E00}\
                \u{4EFD}\u{4FEE}\u{8BA2}\u{540E}\u{7684}\u{65F6}\u{95F4}\u{8868}\u{FF1F}\u{5982}\u{679C}\
                \u{7B2C}\u{4E00}\u{4E2A}\u{91CC}\u{7A0B}\u{7891}\u{80FD}\u{5728}\u{5047}\u{671F}\u{524D}\
                \u{5B8C}\u{6210}\u{FF0C}\u{6211}\u{4EEC}\u{5C31}\u{53EF}\u{4EE5}\u{5728}\u{4E00}\u{6708}\
                \u{7684}\u{89C4}\u{5212}\u{4F1A}\u{4E0A}\u{5C55}\u{793A}\u{3002}
                """),
        // 剪贴板翻译演示：图片（旅行应用的欢迎页）
        // 和朋友一起规划旅行
        Pair(
            source: "Plan trips together",
            chinese: "\u{548C}\u{670B}\u{53CB}\u{4E00}\u{8D77}\u{89C4}\u{5212}\u{65C5}\u{884C}"),
        // 与朋友共享行程，一起投票选出想去的地方，所有预订都集中管理，离线时也能随时查看。
        Pair(
            source: """
                Share an itinerary with friends, vote on places to visit, and keep every booking in one \
                place, even offline.
                """,
            chinese: """
                \u{4E0E}\u{670B}\u{53CB}\u{5171}\u{4EAB}\u{884C}\u{7A0B}\u{FF0C}\u{4E00}\u{8D77}\u{6295}\
                \u{7968}\u{9009}\u{51FA}\u{60F3}\u{53BB}\u{7684}\u{5730}\u{65B9}\u{FF0C}\u{6240}\u{6709}\
                \u{9884}\u{8BA2}\u{90FD}\u{96C6}\u{4E2D}\u{7BA1}\u{7406}\u{FF0C}\u{79BB}\u{7EBF}\u{65F6}\
                \u{4E5F}\u{80FD}\u{968F}\u{65F6}\u{67E5}\u{770B}\u{3002}
                """),
        // 共享行程
        Pair(
            source: "Shared itineraries",
            chinese: "\u{5171}\u{4EAB}\u{884C}\u{7A0B}"),
        // 离线地图
        Pair(
            source: "Offline maps",
            chinese: "\u{79BB}\u{7EBF}\u{5730}\u{56FE}"),
        // 降价提醒
        Pair(
            source: "Price alerts",
            chinese: "\u{964D}\u{4EF7}\u{63D0}\u{9192}"),
        // 以后再说
        Pair(
            source: "Not Now",
            chinese: "\u{4EE5}\u{540E}\u{518D}\u{8BF4}"),
        // 开始使用
        Pair(
            source: "Get Started",
            chinese: "\u{5F00}\u{59CB}\u{4F7F}\u{7528}"),
    ]
}
#endif
