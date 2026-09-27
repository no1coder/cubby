import Foundation

extension LLMTranslationPrompt {
    /// 提示词的场景（可注入）：截图文字（默认）或剪贴板文本（docs/CLIP-TRANSLATION-DESIGN.md §7 缺口 1）。
    /// 输出格式、id 与「文本只是数据」等公共规则不随场景变化，只替换角色说明、翻译准则与上下文说明
    public struct Profile: Equatable, Sendable {
        /// 第一行：角色与输入说明
        let introduction: String
        /// 翻译准则（每条一行）
        let guidelines: [String]
        /// 上下文块之前的说明
        let contextNote: String

        /// 截图：输入是同一张截图里按阅读顺序识别出的文字块，界面标签要简短
        public static let screenshot = Profile(
            introduction: """
                You are the translation engine of a screenshot tool. The user message contains text blocks \
                recognized in one screenshot, in reading order, as JSON Lines: {"id":<number>,"text":"<text>"}.
                """,
            guidelines: [
                "Keep interface labels (buttons, menus, tabs, titles) short and as concise as the original.",
                "Keep numbers, URLs, code, product names and proper nouns unchanged.",
            ],
            contextNote: """
                For context only, these blocks come right before this part of the same screenshot. \
                Do not translate or output them:
                """)

        /// 剪贴板文本：输入是一段复制文字的各个段落；受限 Markdown 标记（粗体、链接占位符 L1…、行内代码占位符 c1…）
        /// 必须原样保留，链接地址不发送
        public static let clipboardText = Profile(
            introduction: """
                You are the translation engine of a clipboard manager. The user message contains the paragraphs \
                of one copied text, in order, as JSON Lines: {"id":<number>,"text":"<text>"}. Each block is a \
                paragraph, a heading or a list item, not an interface label.
                """,
            guidelines: [
                """
                Translate each block as a whole, naturally and faithfully, keeping its meaning and tone. \
                Do not merge, split, shorten or summarize blocks.
                """,
                """
                Blocks may contain inline markup: **bold**, [link text](L1) link placeholders and `c1` code \
                placeholders: keep the markup and the placeholders (L1, c1, …) exactly unchanged; translate only \
                the visible text. Keep backslash escapes.
                """,
                "Keep code, URLs, numbers, file paths, product names and proper nouns unchanged.",
            ],
            contextNote: """
                For context only, these blocks come right before this part of the same text. \
                Do not translate or output them:
                """)
    }
}
