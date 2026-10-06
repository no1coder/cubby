# Cubby 剪贴板条目翻译 · 集成设计

> 状态：已实现（2026-09-27），随首个公开版本 v0.2.0 发布。原型与第 10.4 节的 3 个问题由产品负责人确认（全部按建议）。安全审查后的补充：链接地址从不发送（大模型收到 `[文字](L1)` 占位符，本机还原），疑似密钥检查扫描实际发送内容（`ClipTranslationDocument.sentTexts`），按住 ⌥ 预览在云端引擎下也需 0.6 s 停留，密钥确认只对同一计划（目标语言、引擎、主机）有效。**§0.1 的增量优先于正文中与之冲突的描述。**
> 依据：产品决策（翻译卡 ⌘T、⌥↩ 翻译并粘贴、图片原位翻译、按条目 × 目标语言缓存、译文可搜、复制时自动翻译）+ 截图翻译设计 [`TRANSLATION-DESIGN.md`](TRANSLATION-DESIGN.md)。交互与视觉以原型 `docs/prototypes/clipboard-translate.html` 为准，本文只写原型表达不了的接入点、数据、契约与分工。
> 约定：`文件:行` 均指本文撰写时主仓库的代码。

## 0. 结论速览

| # | 决策 |
| --- | --- |
| K1 | 翻译卡复用预览面板窗口（不可成为 key），面板新增「详情区」模式：预览 / 翻译，二者互斥 |
| K2 | 新增指令 `⌘T`（别名 `⇧⌘T`）、`⌥↩`；翻译卡打开时额外占用 `⌘C`、`⌘S`，且 ↩ / ⇧↩ / ⌥↩ 都粘贴译文 |
| K3 | 缓存放在 `ClipItem.translations`（可选字段，缺失解码为 nil，nil 不编码，**schema 不升级**）；**容器必须容错解码**（§2.2） |
| K4 | 缓存键 = 目标语言（每种语言只留一份，换引擎重译即覆盖）；每条最多 3 种语言；译后图片存为 blob |
| K5 | 搜索：译文进预折叠索引，排在正文与图片识别文字之后（新增 3 档） |
| K6 | 粘贴译文一律纯文本；复制 / 粘贴译文**不**新建条目，只有「存为新条目」（⌘S）才入历史 |
| K7 | 图片翻译用「合成屏幕」把历史图片包装成 `FrozenFrame`，**不改截图翻译的任何契约**；编排由本功能自写 |
| K8 | 与截图翻译同一门槛：`#available(macOS 26, *)` 且翻译服务已接线，否则所有入口隐藏、快捷键不映射 |

### 0.1 已确认的决策与原型增量（优先于正文）

| # | 决策 |
| --- | --- |
| A1 | Q1–Q3 按建议：面板 `⌘T`（别名 `⇧⌘T`）；复制 / 粘贴译文不入历史，只有 ⌘S 存为新条目；仅 macOS 26+ |
| A2 | **富文本保留结构**（推翻 K6 与 §4「一律纯文本」）：译文保留标题、段落、列表、粗体、链接，行内代码不翻译不发送；粘贴富文本条目的译文时写 RTF / HTML + 纯文本，翻译卡里 ⇧↩ 只粘贴纯文本。实现：分段器对富文本按段落拆分并记录段落样式；大模型发送受限 Markdown（`**粗体**`、`[文字](链接)`、`` `代码` ``）并要求原样保留标记，返回后解析回行内样式；系统翻译只发段落纯文本，保留段落级样式、丢弃段内行内样式。缓存里 `usesInlineMarkup` 标明段内是否含标记 |
| A3 | **翻译卡跟随选中项**（推翻 §1.3 / §8「跟随时不向云端发送」）：卡片打开时切换选中项即翻译新条目；系统翻译立即开始，大模型需在该条停留 0.6 s 才发送；已缓存的立即显示 |
| A4 | **列表中按住 ⌥ 约 300 ms（期间未按其他键）**：选中卡片内容淡入为流式译文，松开恢复；此时按 ↩（即 ⌥↩）粘贴的就是正在显示的内容；按下其他键立即取消预览（⌥↑ / ⌥↓ 保持原义） |
| A5 | 语言胶囊显示检测到的源语言「英语（自动检测）→ 简体中文」，旁边 **⇄ 对调**：把当前译文作为输入译回源语言（不写缓存） |
| A6 | 胶囊下方一行隐私说明：「本机翻译，内容未离开此 Mac」/「已发送到 <主机名>」 |
| A7 | 粘贴译文、⌥↩ 之后 HUD 注明所用引擎（「已用系统翻译（本机）翻译并粘贴」/「已用 DeepSeek 翻译并粘贴」，云端带云图标），停留 2.6 s |
| A8 | 语言选单里「粘贴到 <App> 时总是译为此语言」：按粘贴目标应用的 bundle id 记住目标语言（新设置键，C3 在 T2 合并后添加） |
| A9 | 流式呈现：引擎按段 / 块返回，界面在每段到达时以约 150–300 ms 的逐字显现动画呈现（保留原型的流式观感，不做逐 token） |
| A10 | 原型数值照搬：卡片宽 440、头 56 / 工具条 40 / 底栏 36，高度 236–620 且流式时不跳动；⌥ 预览 300 ms；自动翻译在复制后 500 ms；卡片译文行 12 pt 单行、左侧 2 pt 强调色竖条 |
| A11 | 分工调整：`CubbyCore/Clipboard/PasteboardWriter.swift` 的新入口归 **C2**（粘贴链路），C1 不改它；契约文件见 §10.1（已由协调者写入主仓库） |

## 1. 与现有架构的接入点

### 1.1 快捷键核查

面板按键走 `PanelKeyboard` 的本地 keyDown 监听（`PanelController.swift:357`），先于搜索框的字段编辑器与主菜单等价键；未映射的组合原样放行（`PanelController.swift:359`）。输入法组字期间整体放行（`PanelController.swift:331`）。

| 状态 | ⌘T | ⌥↩ | 依据 |
| --- | --- | --- | --- |
| 搜索框聚焦（常态） | 空闲：`characterCommand` 无 `t`；主菜单只有 w/q/z/⇧z/x/c/v/a | 空闲：`returnCommand` 对 `.option` 返回 nil，今天会落到搜索框（字段编辑器可能插入换行，映射后顺带消除） | `PanelCommand.swift:108-120`、`MainMenu.swift:19-62`、`PanelCommand.swift:98-105` |
| 预览打开 | 空闲：预览面板不可成为 key，键盘仍在主面板 | 空闲 | `PreviewPanelController.swift:12-15`、`ClipPanel.swift:29` |
| 帮助打开 | 空闲：帮助是主面板内浮层，`handle` 不区分帮助状态 | 空闲 | `PanelView.swift:37-43`、`PanelViewModel.swift:118-138` |
| 全局热键 | 默认 ⇧⌘V / ⇧⌘2，不冲突；用户若把全局热键录成 ⌘T，Carbon 热键优先 | 同左 | `HotKey.swift:11-22` |

结论：两者在所有面板状态下都空闲。**但与截图覆盖层语义冲突**：覆盖层 `⌘T` = 提取文字、`⇧⌘T` = 翻译（`ScreenshotCommand.swift:158`、`TRANSLATION-DESIGN.md:21,71`）。建议面板以 `⌘T` 为主、同时接受 `⇧⌘T`（见 §10.4 Q1）。

`PanelCommand` 改动（`CubbyCore/Panel/PanelCommand.swift`）：

| 新指令 | 按键 | 条件 |
| --- | --- | --- |
| `.translate` | ⌘T、⇧⌘T | 始终映射（不可用时由视图模型提示音） |
| `.translateAndPaste` | ⌥↩、⌥ + 小键盘 Enter | 始终映射 |
| `.copyTranslation` | ⌘C | 仅 `from(…, translationCardOpen: true)`；否则放行给搜索框的「拷贝」 |
| `.saveTranslation` | ⌘S | 同上 |

↩ / ⇧↩ 仍映射为 `.paste` / `.pasteAlternate`，由视图模型按状态改道（翻译卡打开时粘贴译文；译文只有纯文本，「另一种格式」无意义）。`⌥↑/⌥↓`（`PanelCommand.swift:75-78`）不受影响。

### 1.2 翻译卡挂载

- 复用 `PreviewPanelController` 的窗口、定位（`PanelPlacement.frame(beside:)`，优先左侧）与淡入（`PreviewPanelController.swift:36-48`）。`PreviewPanelView` 按视图模型的 `detailPane` 选择 `ClipPreviewView` 或 `TranslationCardView`；`PreviewMount` 的「只在显示期间挂载」规则不变（`ClipPreviewView.swift:5-28`）。
- 高度：文本卡取主面板等高（有三个视图切换，内容高度不稳定）；图片卡 = `imageHeight(ref)` + 翻译条 36（`PreviewPanelController.swift:110-118`）。`heightCache` 的键从 `UUID` 改为 `(UUID, pane)`（`PreviewPanelController.swift:21`）。
- **限制**：窗口 `canBecomeKey == false`（`ClipPanel.swift:29`，`DESIGN.md:147` 的硬约束），不能改——一旦成为 key，主面板 `resignKey` 即收起（`PanelController.swift:59-65`）。所以翻译卡上的一切键盘操作都经主面板的指令；鼠标操作依赖 `FirstMouseHostingView`（`ClipPanel.swift:39-41`）。语言选单（SwiftUI `Menu`）与卷帘拖动在非 key 面板中的表现需第一天做验证（§10.3 R1）。
- 「按住 ⌥ 看原文」需要 `flagsChanged`：`PanelKeyboard` 现在只监听 `.keyDown`（`PanelController.swift:357`），扩展为 `[.keyDown, .flagsChanged]`，后者只转发 ⌥ 的按下 / 松开，不消费事件。

### 1.3 视图模型状态

`PanelViewModel` 已 272 行，翻译逻辑放进新的 `ClipTranslationController`（`@MainActor @Observable`，App 层），视图模型只路由：

```swift
enum DetailPane: Equatable { case preview, translation }
private(set) var detailPane: DetailPane?          // 取代 isPreviewVisible（保留同名计算属性，避免波及 PanelController）
@ObservationIgnored var translator: ClipTranslationController?   // nil = 不可用（K8）
```

`ClipTranslationController` 持有：
- `card: CardState?`——`itemID`、`languages`、引擎名与是否云端、`phase`（`.working(done,total)` / `.done` / `.failed(TranslationFailure)` / `.needsSecretConfirmation` / `.alreadyTarget` / `.unsupported(reason)`）、`view`（译文 / 对照 / 原文）、图片的原图 / 译图 / 卷帘位置 / `isPeeking`。
- `inline: InlineJob?`——⌥↩ 的单个进行中任务（条目 id、进度、失败原因），卡片据此显示行内进度或错误。
- 同一时刻最多一个翻译卡任务 + 一个 ⌥↩ 任务；新任务取消同类旧任务，未完成的部分结果丢弃、不缓存。

**翻译卡跟随选中项**（与预览一致）：切换选中项时取消旧任务；新条目有缓存 → 立即显示；无缓存且引擎在本机 → 停留 300 ms 后自动翻译；无缓存且引擎为云端 → 显示「按 ⌘T 翻译此条」，**不自动联网**（沿用 `TRANSLATION-DESIGN.md:173`「只在用户操作时联网」）。

### 1.4 焦点与粘贴目标

- 粘贴目标在面板呼出时取一次（`PanelController.swift:96`、`PanelViewModel.swift:89-91`）；面板是 `.nonactivatingPanel`（`ClipPanel.swift:14`），翻译期间目标应用始终在前台，无需额外处理。
- 翻译完成后走现有投递路径：写剪贴板 → 无动画隐藏 → 120 ms → 校验前台 pid 仍是目标 → 发送 ⌘V，否则 HUD「目标应用已切换，已复制」（`PanelController.swift:276-312`）。
- 翻译期间用户点到别处 → 面板失焦收起（`PanelController.swift:59-65`）→ `panelDidHide` 取消全部翻译任务（`PanelViewModel.swift:102-106` 中追加）。

### 1.5 esc 与其他状态规则

现有顺序：帮助 → 预览 → 清空搜索 → 关闭（`PanelViewModel.swift:261-271`）。新顺序：**帮助 → 取消进行中的翻译（卡片或 ⌥↩，已到达的译文丢弃）→ 关闭详情区（翻译卡 / 预览）→ 清空搜索 → 关闭面板**，与截图「翻译中 Esc 只取消翻译」一致（`TRANSLATION-DESIGN.md:55`）。
- 帮助打开时按 ⌘T / ⌥↩：先关帮助再执行。
- 翻译卡打开时按空格 / ⌘Y：切到预览；预览打开时按 ⌘T：切到翻译卡；翻译卡打开时再按 ⌘T：关闭。
- 不支持的类型按 ⌘T / ⌥↩：提示音 + 底栏提示「此类内容不支持翻译」（同「贴到屏幕」对非图片条目的处理，`PanelViewModel.swift:206-212`）。
- 帮助浮层新增两行（⌘T、⌥↩）并在翻译卡打开时显示 ⌘C / ⌘S（`ShortcutHelpView.swift:47-87`）；620 pt 面板里是否放得下需在实现时截图确认。卡片右键菜单与 VoiceOver 操作各加「翻译」「翻译并粘贴」（`CardList.swift:71-145`）。`DESIGN.md` 键盘表（`DESIGN.md:106-125`）同步更新。

## 2. 数据模型

### 2.1 形状（`CubbyCore/Models/ClipTranslation.swift`，新）

```swift
public struct ClipTranslation: Codable, Equatable, Sendable {
    public let target: String        // BCP-47，缓存键（K4）
    public let source: String?       // 检测到的源语言
    public let engineName: String    // 翻译卡引擎徽标、「译」角标的悬停说明
    public let isOnDevice: Bool
    public let createdAt: Date
    public let segmentation: Int     // 分段算法版本；与当前不一致时「对照」退化为上下两整段
    public let segments: [String?]   // 文本：与分段一一对应，nil = 该段未翻译（用原文）；图片：按块 id 顺序的译文
    public let imageName: String?    // 图片：译后 PNG 的 blob 名；文本为 nil
}
// ClipItem 新增：public let translations: ClipTranslations?   （nil 表示没有任何译文）
```

- 文本的完整译文 = `ClipTextSegmenter.join(original:, segments:)`：按原文的分隔符（空行、换行）拼回，未翻译段用原文，保证粘贴结果保留原有段落结构。分段器是纯函数：空行分段；段内若判定为硬换行（除末行外行长接近、非列表项）则合并为一块，否则逐行成块；代码行、URL、纯数字行原样保留不发送。
- 不存原文副本（条目内容不可变，按 `contentHash` 唯一确定），也不存图片的 `TranslatedBlock` 版面（T3 可改其字段，`TranslationPlacement.swift:5-7`），只存译后成图。

### 2.2 兼容与容错（关键约束）

- 沿用 `recognizedText` 的先例：可选字段、缺失解码为 nil、nil 不编码、**不升 schema**（`ClipItem.swift:46-48`、`HistoryMigrator.swift:17-18`、`SCREENSHOT-DESIGN.md:1327`）。旧版（v0.2）读新文件时合成的 Codable 忽略未知键，数据可读。
- **必须容错**：`ClipItem` 用合成 Codable，嵌套结构任何一项解码失败都会让整个历史解码失败，而加载失败的处理是「备份后从空历史开始」（`ClipStoreLoading.swift:48-50`）。因此 `ClipTranslations` 是一个自定义 `init(from:)` 的包装类型：逐项 `try?` 解码，坏项丢弃，全坏则为空；以后给 `ClipTranslation` 加字段一律可选。测试须覆盖「一项坏数据不影响整份历史」。
- `ClipItem` 里 6 处 `ClipItem(...)` 构造（`ClipItem.swift:72-105`）都要带上新字段；`replacing(_:)` 在新条目没有译文时沿用旧条目的译文（同内容同译文，同 `recognizedText` 的处理，`ClipItem.swift:78-85`）。

### 2.3 上限（`ClipTranslationPolicy`，Core 纯逻辑）

| 项 | 值 | 理由 |
| --- | --- | --- |
| 可翻译原文长度 | ≤ 10 000 字符 | 与 `ImageTextIndexPolicy.maxTextLength` 同级（`ImageTextIndexing.swift:6`）；大模型约 2 批（每批 ≤ 6000，`TRANSLATION-DESIGN.md:131`） |
| 每种语言保存的译文 | ≤ 30 000 字符，超出只显示不缓存 | 大模型单块上限 `4 × 原文 + 200`（`TRANSLATION-DESIGN.md:130`） |
| 每条语言数 | ≤ 3，超出淘汰最早的 | 缓存键只有目标语言 |
| 全部译文总字符 | ≤ 1 000 000，超出按 `createdAt` 淘汰最早的译文（不动条目） | 历史文件每次整体重写（`ClipStore.swift:249-251`），控制写放大 |
| 图片 | 最长边 ≤ 8192 且面积 ≤ 7680×4320，否则「图片过大，无法翻译」 | 需整图解码后绘制；识别侧 > 4K 由 T3 分片（`TRANSLATION-DESIGN.md:89`） |

上限在 `ClipHistory.settingTranslation(_:for:)` 这个纯函数里执行（仿 `settingRecognizedText`，`ClipHistory.swift:37-43`），单测可直接断言。

### 2.4 生命周期

- **删除 / 撤销 / 清空 / 裁剪**：译文长在条目上，随条目走。译后图片 blob 并入 `ClipItem.blobNames`（`ClipItem.swift:127-129`），于是 `apply` 的孤立文件清理、待撤销条目的文件保护、启动时 `removeOrphanedBlobs` 全部自动覆盖（`ClipStore.swift:238-258,348-358`）。blob 名按内容哈希（`<sha256>.png`），与「存为新条目」产生的同一张图共享文件是安全的。
- **修复**：`repairingMissingBlobs` 目前只处理原图与富文本格式（`ClipStore.swift:361-370`）；新增「译后图片缺失 → 只删该条译文，不删条目」。这也覆盖降级场景：v0.2 启动时不认识译后图片，会当孤立文件删掉，升级回来后由修复丢弃对应译文。
- **全部清除**：`ClipStore.clearTranslations()`，仿 `clearRecognizedText`，同时清理待撤销条目上的译文（`ClipStore.swift:197-203`）。
- 写盘走现有合并保存（`CoalescingSaver`），译文到达完成后一次写入，不逐块写。

### 2.5 暂停、忽略应用、隐私

- **暂停记录**：手动翻译已有条目照常可用并缓存（不是记录新的剪贴板内容）；自动翻译停止（同 `ImageTextIndexer` 暂停即停，`ImageTextIndexer.swift:99-104`）；「存为新条目」禁用，悬停说明「已暂停记录」（同截图 `recordText` 在暂停时跳过，`ScreenshotOutputService.swift:209-215`）。
- **忽略的应用**：来自忽略应用的内容本就不入历史（`AppDelegate.swift:200`、`AppSettings.swift:201-205`）；事后才加入忽略名单的应用，其已有条目不回溯处理，但自动翻译只作用于新记录的条目，因此不会触发。
- **疑似密钥**：「不记录疑似密钥」默认开（`AppSettings.swift:160`），但用户可关，所以翻译前仍用 `SecretDetector.containsSecret` 检查（§8）。
- 译文与历史同一文件、同一权限（0600）；日志只记长度、段数、耗时、状态码，不记原文、译文。

### 2.6 「存为新条目」（⌘S）

- 文本：`store.recordInBackground(.text(译文), source:)`；图片：`.image(png:width:height:)`。来源用 Cubby 自身 bundle id + 名称「译文」（本地化），与截图条目的「截图」来源同一做法（`ScreenshotOutputService.swift:44-49`），搜索「译文」即可找到全部保存的译文。
- 受暂停、疑似密钥、`CaptureLimits.maxTextBytes` 约束（同 `ScreenshotOutputService.swift:209-215`）。
- 去重：同内容按 `contentHash` 合并并移到最前（`ClipHistory.swift:15-20`），重复保存不产生重复条目。
- 保存后翻译卡仍停在原条目，底栏提示「已存为新条目」；富文本条目存出的是纯文本。

## 3. 搜索

- `ClipSearchIndex.Entry` 增加 `translation: FoldedText?`（该条全部语言的译文以换行拼接）并参与 `requiresExactMatch` 判定；`isCurrent` 增加译文签名比较，保证写入译文后该条被重新折叠（`ClipSearchIndex.swift:21-47`）。`RawSearchRecord` 同步增加原文路径（`ClipSearchRanking.swift:175-189`），两条路径的等价性由现有等价测试扩展覆盖（`Tests/CubbyCoreTests/ClipSearchIndexEquivalenceTests.swift`）。
- 档位：在图片识别文字三档之后追加 `translationPhrase / translationLeading / translationOther`（`ClipSearchRanking.swift:6-26`）。判定：正文 + 元数据命中全部关键词 → 前三档；否则再允许图片识别文字 → 图片三档；否则再允许译文 → 译文三档。即「原文 > 图中文字 > 译文」，多个关键词可跨字段命中（与现有规则一致，`ClipSearchRanking.swift:110-137`）。
- `ClipItem.matches(keyword:)` 同步纳入译文（`ClipItemMatching.swift:8-10`）；`ClipSearchSession` 的前缀收窄仍成立（仍是字节子串查找，单调性不变，`ClipSearchSession.swift:1-6`）。
- 只因译文命中的卡片：卡片显示译文首行并高亮关键词（无论「在卡片上显示译文」是否开启），否则用户看不懂为何命中。
- 性能：写入译文只重折叠该条（`ClipSearchIndex.swift:75-87`）；查询只对正文与图中文字都没命中的条目多做一次 memmem。按全局 1 M 字符上限估算，最坏每次按键多扫约 3 MB 折叠字节，亚毫秒级。

## 4. 粘贴

- **格式**：一律纯文本。富文本条目只翻译其纯文本（`item.text`）；保留 RTF / HTML 样式需要把译文映射回样式区间，两种引擎都只处理纯文本，本期不做。
- **写剪贴板**：把 `PanelController.perform`（`PanelController.swift:264-313`）拆成「写入」与「投递」两段，投递段（隐藏、直接粘贴开关、辅助功能、目标校验、⌘V）原样复用。写入新增两种来源：纯文本、译后 PNG 文件。Core 的 `PasteboardWriter` 增加 `write(text:to:)`、`write(pngAt:to:)`，同样附带 `markerType`，监听器因此跳过，不会自动入历史（`PasteboardWriter.swift:48`、`PasteboardReader.swift:18`）。目标剪贴板改为注入（今天写死 `.general`，`PanelController.swift:268`），E2E 用命名剪贴板。
- 粘贴译文后照常 `store.promote(原条目)`（`PanelController.swift:278`）。
- **翻译卡**：↩ / ⇧↩ / ⌥↩ 粘贴译文（任何视图下都粘贴译文，与原型一致；「原文」视图只用于查看）；⌘C 复制译文并留在面板（底栏提示「已复制译文」）；图片卡 ⌘C / ↩ 复制 / 粘贴**译后图片**（含 DPI，按 `ScreenshotExporter.pngData` 写入，`ScreenshotExporter.swift:88`）。
- **⌥↩ 翻译并粘贴**：
  1. 资格检查（§5 末、§8）；不支持 → 提示音；疑似密钥且引擎在云端 → 卡片行内提示「疑似密钥，未发送到 <引擎> · 仍然翻译」，必须点按钮确认。
  2. 已有该目标语言的缓存 → 立即粘贴。
  3. 否则卡片行内显示进度「翻译中 3/12 · esc 取消」，面板保持打开；完成后写入缓存再粘贴。
  4. 超时：沿用引擎自身的首字节 20 s / 整体 90 s（`TRANSLATION-DESIGN.md:132`），另加 ⌥↩ 专用的 30 s 总时限，超时 → 行内「翻译超时 · 重试 · 打开翻译卡（⌘T）」。
  5. 失败：行内给出原因与操作（沿用 `TRANSLATION-DESIGN.md:56-67` 的文案与按钮）；**绝不退回粘贴原文**；部分完成不粘贴、不缓存。
  6. 原文已是目标语言 → 行内「原文已是 <语言> · ⌘T 选择目标语言」，不粘贴。
  7. 面板关闭、esc、对另一条再按 ⌥↩ → 取消。
- 「去设置 / 下载语言」：先无动画隐藏面板（同 `onOpenSettings`，`PanelController.swift:68-71`），再 `await provider.resolve(failure)`；面板已关，不自动重试，下次打开该条时自然重新翻译。

## 5. 图片

### 5.1 适配器：合成屏幕（不改契约）

截图的识别 / 版面 / 绘制契约都以「冻结帧 + 全局点」为坐标系：`TranslationTextRecognizing.blocks(in: FrozenFrame, selection:)`（`TranslationProviding.swift:24-28`）、`TranslationPlacer.place(_:translation:in: FrozenFrame)`、`TranslationPainter.draw(_:in:environment:)`（`TranslationPlacement.swift:67-92`）。`FrozenFrame` 只是「一块屏幕 + 一张 CGImage」（`FrozenFrame.swift:7-16`），`CaptureScreen` 只有 id / frame / scale 三个值（`CaptureScreen.swift:9-21`）。所以一张历史图片可以无损地伪装成「原点在 (0,0) 的一块屏幕」：

```swift
// CubbyCore/ClipTranslation/HistoryImageFrame.swift（新，纯函数）
public enum HistoryImageFrame {
    /// scale 取自 PNG 的 DPI（DPI / 72，四舍五入并夹在 1…3），没有 DPI 时为 1
    public static func scale(dpi: Double?) -> CGFloat
    /// 合成屏幕：CaptureScreen(id: 0, frame: (0, 0, 像素宽 / scale, 像素高 / scale), scale)；selection = 整个 frame
    public static func make(image: CGImage, scale: CGFloat) -> (frame: FrozenFrame, selection: CGRect)
    /// RenderEnvironment(origin: .zero, scale:, targetPixelSize: 图片像素尺寸, pixelatedFrame: nil, frameOrigin: .zero)
    public static func environment(for frame: FrozenFrame) -> RenderEnvironment
    /// 原图 + TranslationPainter.draw → 译后成图（CGImage）
    public static func render(_ frame: FrozenFrame, blocks: [TranslatedBlock]) throws -> CGImage
}
```

- DPI → scale 与贴图的先例一致（`HistoryImagePin.swift:62-64`）；scale 之所以要对，是因为版面参数以点为单位（外扩 `max(2 pt, …)`、衬底 6 pt、模糊 10 pt，`TRANSLATION-DESIGN.md:41-42,116`），字号乘 `environment.scale` 换算像素（`TranslationPlacement.swift:105`）。
- 整数 scale 下 `screen.pixelSize` 与图片像素尺寸严格相等，`ScreenshotExporter.crop` 的像素矩形计算（`ScreenshotExporter.swift:79-85`、`CaptureScreen.swift:41-49`）因此取到整张图。
- `hidden` 传空数组（历史图片没有马赛克）；`TranslationCandidates` 的其余跳过规则（密钥、无字母、代码、已是目标语言）照搬（`TRANSLATION-DESIGN.md:101-106`）。

### 5.2 截图实现线需要改什么

**契约文件一个字都不用改。** 只需向拥有者提出两条非契约约束（写进各自的单测即可）：

| 线 | 约束 |
| --- | --- |
| T3 | 识别器与 placer 只通过 `frame.image` 与 `frame.screen.frame / scale / pixelRect` 取像素，不把 `screen.id` 当真实显示器、不读取屏幕；以原点 (0,0) 的合成帧加一条单测 |
| T1 | 无。识别 → 过滤 → 语言 → 引擎流 → 逐块 place 的编排在 T1 的会话代码里，与撤销 / reducer 耦合，不复用；本功能自写 `ClipImageTranslator`（约 150 行，只调用契约函数） |

对比视觉（原文 | 译文、卷帘、按住看原文）在截图侧是覆盖层 AppKit 视图（T1 的 `Cubby/Screenshot/Overlay/**`），本功能用 SwiftUI 按 `TRANSLATION-DESIGN.md:39` 的数值重做（2 pt 白线、28 pt 拖柄、←/→ 微调）；「按住空格」换成「按住 ⌥」，因为空格在面板里是预览开关（`PanelCommand.swift:91-92`）。

### 5.3 流程与显示

1. 后台解码原图（取 DPI）→ 合成帧 → `recognizer.blocks` → 过滤 → `TranslationTargetResolver.languages` → `engine.translate` 流式到达 → 逐块 `place`。
2. 卡片上原图之上叠一层 `CALayer`，用 `TranslationPainter.draw` 按视图缩放后的 environment 逐块重画，得到与截图一致的流式淡入。
3. 全部完成后 `render` 出整图，PNG（带 DPI）写入 blob，缓存 `imageName` 与块译文（供搜索、「复制译文文字」）。部分块失败：显示「部分内容未翻译 · 重试」，不缓存。
4. 图片中的疑似密钥块**永不发送、不可覆盖**（沿用截图规则 D6）；「仍然翻译」只适用于文本条目。

## 6. 自动翻译（复制时，默认关）

- **触发点**：`AppDelegate.capture` 调 `recordInBackground` 后等待其返回的任务，拿到入历史的条目再交给 `ClipAutoTranslator`（`AppDelegate.swift:199-205`、`ClipStore.swift:85-88`）。不观察 `store.revision`：粘贴会 `promote` 刷新时间（`ClipHistory.swift:23-27`），按时间判断会误把「刚粘贴的旧条目」当新复制。
- **资格**（`ClipAutoTranslatePolicy`，Core 纯逻辑）：`kind == .text`（链接、颜色、文件、图片都不自动）；非代码（`TextHeuristics.looksLikeCode`，`TextHeuristics.swift:24-35`）；2…2000 字符且含字母；非疑似密钥；未暂停；已有该目标语言缓存则跳过；源语言置信度 ≥ 0.8 且 ≠ 目标语言。
- **引擎**：只用系统翻译，且语言对必须 `.installed`；`.supported`（需下载）直接跳过，**绝不在后台弹出下载**；设置里配置了大模型也不用。
- **节流**：串行、`utility` 优先级；只保留最新一条待办（连续复制时丢弃旧的）；相邻两次至少间隔 1 s；单次 10 s 超时；低电量模式（`ProcessInfo.isLowPowerModeEnabled`）下不运行；关闭开关或暂停记录时取消。
- 结果经 `store.setTranslation` 写回；条目已被删除时忽略（同 `settingRecognizedText` 对缺失 id 的处理）。失败静默，只记次数。
- 能耗：系统翻译在本机运行，单条 ≤ 2000 字符约数百毫秒，加上合并与间隔，远低于图片 OCR 回填（间隔 2 s，`ImageTextIndexing.swift:38`）。

## 7. 引擎与设置

- **复用**：同一个 T2 `TranslationService`（实现 `TranslationProviding`）同时赋给截图协调器和面板；语言选单读写同一个 `targetLanguage`（`TranslationProviding.swift:11`），与截图共享。引擎徽标显示 `shortName`（与截图翻译条同一规则：品牌名或自定义服务的域名主体），悬停说明用完整的 `displayName`，图标看 `sendsTextOffDevice`（`TranslationContract.swift`）；缓存比对仍只用 `displayName`。
- **文本 → 引擎的适配**：每段构造 `TextBlock(id: i, lines: [], alignment: .leading, text: 段落)`；`frame` 为 `.null` 无妨，引擎按契约不读坐标（`TranslationContract.swift:25-26,43-45`）。
- **缺口（需 T2 配合，不动契约文件）**：
  1. 大模型提示词是为截图写的（「截图文字」「界面标签简短」，`TRANSLATION-DESIGN.md:128`），不适合段落文本。请 T2 让 Core 的大模型引擎接受提示词参数（默认 = 截图版），本功能传「剪贴板文本版」。
  2. `makeEngine()` 在配置了大模型时总返回大模型（`TranslationProviding.swift:14-15`），自动翻译需要「只要系统翻译」。本功能在自己的文件里定义 `ClipTranslationProviding: TranslationProviding`（`makeEngine(purpose:onDeviceOnly:)`），由本功能在 T2 合并后给 `TranslationService` 写扩展实现；需要 T2 的系统引擎与大模型引擎类型在模块内可构造。
- **新设置项**（`AppSettings` 由 T2 拥有，T2 合并后再加；界面放在 T2 的「设置 › 翻译」下新增「剪贴板」一组）：

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `translatesClipsOnCopy` | false | 复制时自动翻译（仅系统翻译，本机） |
| `showsTranslationOnCards` | false | 在卡片上显示译文首行（列表保持紧凑；只因译文命中时无论开关都显示） |

- 不设「缓存保留期」键：译文随条目存亡，条目数已由历史上限约束，单条与总量有 §2.3 上限。改为一个「清除全部译文」按钮（调用 `clearTranslations()`）。
- 卡片：「译」角标放在收藏星标旁（`ClipCardView.swift:63-73`）；译文首行放在内容与元信息之间（`ClipCardView.swift:31-37`）；VoiceOver 标签追加「已翻译」。

## 8. 隐私与安全

- 联网条件与截图一致：只在用户按 ⌘T / ⌥↩ / 点「翻译」且引擎为大模型时发送；云端引擎在翻译卡上始终显示引擎名与云图标。翻译卡跟随选中项时不向云端自动发送（§1.3）。
- 疑似密钥：文本条目用 `SecretDetector.containsSecret` 检查整段；本机引擎直接翻译；云端引擎须点「仍然翻译」（每次、每条，不记住选择）；图片中的密钥块永不发送。自动翻译跳过密钥。
- 不支持：链接、文件、颜色、代码片段（`ContentClassifier.swift:7-12`、`CardStyle` 的代码判定 `ClipCardView.swift:154`）。
- `PRIVACY.md` 中英两节（`PRIVACY.md:5`、`PRIVACY.md:93`）的增量：
  - 「网络访问」（`PRIVACY.md:36-44 / 124-132`，T2 会先加截图翻译）：再加一句「翻译剪贴板条目时，若引擎为你配置的大模型，Cubby 会把该条目的文字（图片则为识别出的文字）发送到该服务；复制时自动翻译只使用系统翻译，不联网。」
  - 「本机存储的内容」（`PRIVACY.md:13 / 101`）：「译文保存在本地历史文件中、随条目删除；翻译后的图片保存在图片目录；可在设置 › 翻译中清除全部译文。」
  - 「不会记录的内容」附近：「疑似密钥的文本不会自动发送到云端翻译，需你确认；图片中的疑似密钥不会发送。」

## 9. 测试计划

**现状**：Core 单测 + 覆盖率门槛（`CubbyCore` 行覆盖率 ≥ 95%，`scripts/check-coverage.sh:15`）；端到端只有截图的 `make e2e`（`Makefile:18-20`，`Cubby --e2e`）；面板只有截图走查用的 `--scenario`（`PanelController.swift:161-184`、`PanelDebugInput.swift:30-49`），不做断言。面板没有 E2E 框架。

**Core 单测**（门槛不变，≥ 95%）：
- 模型：编解码往返、nil 不编码、旧 JSON 无该字段、**坏项丢弃而整份历史可读**、`replacing` / `touched` 保留译文。
- `ClipHistory`：按语言覆盖、每条 3 种淘汰、单条 / 总量上限、缺失 id 与不支持类型忽略、全部清除。
- `ClipStore`：译后图片 blob 的删除 → 撤销 → 放弃、裁剪、清空、启动孤立清理、缺失修复只丢译文；清除译文时待撤销条目一并清除；持久化往返。
- 分段器：`join(原文, 各段原文) == 原文` 恒等、空行 / 硬换行 / 列表 / CJK / CRLF / 末尾换行、代码与 URL 行原样保留。
- 资格与策略：`ClipTranslationEligibility`（类型、代码、长度、密钥 × 云端 → 需确认）、`ClipAutoTranslatePolicy`（全部跳过规则、只留最新、间隔）。
- 搜索：档位顺序（正文 > 图中文字 > 译文）、跨字段关键词、原文与索引路径等价（扩展等价测试）、会话收窄、写入译文只重折叠 1 条（`lastFoldedCount`）。
- `PanelCommandTests`：⌘T / ⇧⌘T / ⌥↩ / ⌥+小键盘 Enter；⌘C / ⌘S 只在 `translationCardOpen` 时映射。
- `HistoryImageFrame`：DPI 72 / 144 / 216 / 缺失 / 非整数 → scale；`pixelSize` 等于图片尺寸；整图裁剪逐像素相同；`render` 的像素断言（沿用 `TestBitmaps`）。

**面板 E2E**（新，仅 DEBUG）：`Cubby --panel-e2e <名称|all>` + `make e2e-panel`，仿 `E2EWorld` 的隔离方式（独立偏好域、临时数据目录、命名剪贴板，`E2EWorld.swift:1-60`），桩 provider / 桩引擎（确定性流式延迟）/ 桩识别器，不联网、不读系统剪贴板。脚本：⌘T 打开 / 关闭 / 与预览互切、逐段到达、三种视图、⌘C / ⌘S / ↩ 结果（关闭直接粘贴，断言命名剪贴板内容）、⌥↩ 行内进度后粘贴、翻译中 esc、面板关闭取消、未配置 → 去设置、密钥 × 云端 → 仍然翻译、缓存命中即时显示与「译」角标、搜索命中译文、图片翻译（合成图 + 桩识别器）、按住 ⌥ 看原文、自动翻译（桩系统引擎）。另加 `--scenario translate:<分类>` 供截图走查。

**视觉 / 手工**：`docs/QA-CHECKLIST.md` 增加条目（该文件归 T1，合并时协调）。

## 10. 分工与阶段

### 10.1 契约先行（协调者，半天）

`CubbyCore/ClipTranslation/ClipTranslationContract.swift`（`ClipTranslation`、`ClipTranslations` 容错包装、资格结果枚举）与 `Cubby/ClipTranslation/ClipTranslating.swift`（C2 调用、C3 实现：`translate(_ item:, target:) -> AsyncThrowingStream<ClipTranslationEvent, Error>`、`render…`、`resolve…`），外加 `PanelCommand` 新 case 的签名。

### 10.2 三条实现线

| 线 | 范围 | 拥有的文件 | 估算 |
| --- | --- | --- | --- |
| **C1 数据与搜索**（Core） | 模型与容错解码、`ClipHistory` / `ClipStore` 译文操作与 blob 生命周期、上限策略、分段器、资格与自动翻译策略、`HistoryImageFrame`、搜索索引与档位、`PasteboardWriter` 两个新入口 | `CubbyCore/Models/ClipItem*.swift`、`ClipTranslation.swift`；`CubbyCore/History/ClipHistory.swift`、`ClipStore*.swift`、`ClipSearch*.swift`；`CubbyCore/Clipboard/PasteboardWriter.swift`；`CubbyCore/ClipTranslation/**`；对应测试 | 3 人日 |
| **C2 面板交互**（App） | `PanelCommand`、视图模型路由与 esc、`ClipTranslationController`、翻译卡（文本三视图、图片对比 / 卷帘 / 按住 ⌥）、详情区模式、`flagsChanged`、粘贴拆分与剪贴板注入、卡片角标 / 首行 / 行内进度、右键与读屏操作、帮助、面板 E2E | `CubbyCore/Panel/PanelCommand.swift`、`Cubby/Panel/**`、`Cubby/Views/**`、`Cubby/ClipTranslation/UI/**`、`Cubby/Panel/Debug/**`；`docs/DESIGN.md`；`Makefile`（e2e-panel 目标） | 5 人日 |
| **C3 引擎、图片与设置**（App） | `ClipTranslating` 实现（文本编排、`ClipImageTranslator`）、`ClipTranslationProviding` 扩展、自动翻译器、设置项与「设置 › 翻译 › 剪贴板」、AppDelegate 接线、`PRIVACY.md` / README | `Cubby/ClipTranslation/**`（UI 除外）；T2 合并后：`CubbyCore/Settings/AppSettings.swift`、`Cubby/Settings/**`、`Cubby/App/AppDelegate.swift`、`PRIVACY.md`、README | 4 人日 |

合计约 12 人日 + 联调与 QA 2 天；三线并行时约 7–8 个工作日。`Resources/Localizable.xcstrings` 按截图翻译的做法各线自行 `make strings`，由协调者合并（`TRANSLATION-DESIGN.md:169`）。

### 10.3 依赖与合并顺序

1. **T2 必须先合并**：C3 要改的 `AppSettings.swift`、`Cubby/Settings/**`、`AppDelegate.swift`、`PRIVACY.md` 都归 T2（`TRANSLATION-DESIGN.md:166`），且需要 `TranslationService` 与两种引擎；并请 T2 顺带完成 §7 的「提示词可注入」。C3 在此之前可先用桩写编排与自动翻译器。
2. **T3 不阻塞**：契约已稳定，C3 对着占位实现开发；视觉质量随 T3 合并提升。请 T3 加 §5.2 的合成帧单测。
3. **T1 无代码依赖**：只需同步 `QA-CHECKLIST.md`，以及把 `TRANSLATION-DESIGN.md:188` 非目标里的「翻译历史图片」划掉（产品已决定做）。
4. C1、C2 可立即开工（这些文件不归任何截图翻译线）；C2 先对桩 `ClipTranslating` 开发，C1 合并后接真实数据。

风险：
- **R1 非 key 面板交互**：语言选单与卷帘拖动在 `canBecomeKey == false` 的面板中是否可用，第一天用最小样例验证；不行则语言选单改为程序化弹出 `NSMenu`。
- **R2 历史文件增长**：§2.3 的总量上限是防线；上线前用 500 条 × 3 语言的夹具量写盘耗时。
- **R3 容错解码**：漏做会在数据异常时清空用户历史（§2.2），列为 C1 的验收必查项。
- **R4 系统翻译语言包**：自动翻译在未安装语言包时静默无效；设置里该开关下方注明「需已下载对应语言」。
- **R5 帮助浮层高度**：多两行后可能超出 620 pt，需要截图确认或改为两列。

### 10.4 待产品负责人确认（附建议）

- **Q1 ⌘T 语义与截图不一致**（截图里 ⌘T 是提取文字、⇧⌘T 是翻译）。建议：面板保留 ⌘T = 翻译（面板没有「提取文字」，⌘T 最好记），同时接受 ⇧⌘T 作为别名，帮助里写「⌘T（或 ⇧⌘T）」。
- **Q2 复制 / 粘贴译文是否入历史**：截图的「复制译文」会入历史（`TRANSLATION-DESIGN.md:70`）。建议面板里**不入**：译文已缓存在原条目上且可搜，自动入历史会让同一内容出现两条；需要独立条目时用 ⌘S。
- **Q3 仅 macOS 26+**：沿用 D5，macOS 14 / 15（`Package.swift:7` 仍支持）上整个功能不可见——即使大模型翻译文本并不依赖 macOS 26。建议 v0.3 保持一致（翻译设置在旧系统上本就隐藏，用户无从配置大模型），之后再评估为旧系统开放「仅大模型的文本翻译」。
