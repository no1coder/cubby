# Cubby v0.3 UI 升级 · 开发交接文档

> 给接手开发的 Claude Code / 开发者。设计已定稿（2026-10-12），本文是唯一的实现依据。
> 分支：`feat/ui-dock-gallery-clothesline`（已从 `main` 切出，见第 7 节的现状）。

## 0. 先读这些

| 内容 | 位置 |
| --- | --- |
| 设计稿截图（24 张，按画板命名） | `docs/design/ui-upgrade/*.png` |
| 设计稿源码（HTML，精确的颜色 / 尺寸 / 文案都在这里） | `docs/design/ui-upgrade/src/*.dc.html` |
| 画板布局与标题 | `docs/design/ui-upgrade/src/canvas.json` |
| 现有设计规范（令牌、动效、键盘、可访问性、实现约束） | `docs/DESIGN.md` |
| 项目约定 | `CONTRIBUTING.md`、`Makefile`（`make test` / `lint` / `check-cjk` / `strings`） |

设计稿是 HTML 摆拍，不是像素级规范：**数值以本文 + `docs/DESIGN.md` 的令牌为准**，HTML 用来确认层级、布局、文案与状态。源码里不能出现中文（`make check-cjk`），界面文案一律用英文键 + `Resources/Localizable.xcstrings` 的 zh-Hans 翻译，下文给出的中文即翻译值。

### 画板索引

| 画板 | 内容 |
| --- | --- |
| `Main` / `MainLight` | 浮动面板新卡片样式（深 / 浅）、卡片悬停快捷操作、右键菜单 |
| `ImageGrid` / `ImageGridLight` | ⌃⇧V 只看图片的两列网格 |
| `DockRight` / `DockRightLight` | 固定右侧整高侧栏 |
| `DockBottom` / `DockBottomLight` | 固定底部整宽横条 + 选中卡片上方的预览 |
| `Clothesline` / `ClotheslineLight` | 屏幕顶部晾衣绳 |
| `ClotheslineEdit` | 单击绳上图片：放大 + 标注 |
| `Preview` | 空格预览 |
| `Search` | 搜索高亮、分类命中数、无结果、空历史 |
| `Help` | 快捷键帮助浮层（新增「图片」「翻译」组） |
| `MenuBar` | 菜单栏菜单 + 「面板位置」子菜单 |
| `Settings` / `SettingsLight` | 设置 › 通用（外观、快捷键与面板、晾衣绳） |
| `SettingsHistory` / `SettingsScreenshots` / `SettingsPrivacy` | 其他设置页 |
| `SettingsSecurity` | 设置 › 剪贴板安全 |
| `TamperAlert` | 地址被替换警示卡 |
| `PanelSecurity` | 面板里的地址卡、被替换记录、粘贴前确认、粘贴核对 HUD |
| `Onboarding` | 首次引导第 3 步「你希望剪贴板出现在哪里？」 |

---

## 1. 视觉升级（所有面板）

整体方向：macOS 26+ Liquid Glass，更通透、层级更清楚。只列与现状不同之处，其余遵循 `docs/DESIGN.md`。

- **面板**：圆角 22（`Radius.panel` 在 macOS 26 上由 18 改 22），玻璃更透（深色约 `rgba(24,25,33,0.58)` 的观感），顶边 1pt 高光。macOS 14–25 的毛玻璃回退保持。
- **卡片**：圆角 15（`Radius.card` 12 → 15，嵌套元素同步检查），内边距 12 × 13，卡片间距 8。
- **卡片头部一行**：18pt 来源图标 + 应用名（11pt semibold）+ 相对时间 + 右侧 ⌘N 键帽。图标不再单独占左侧一列，正文因此占满宽度。
- **正文**：13 → 14pt，行高 1.5（字号阶梯需加 14 档的正文用法，更新 `FontSize` 注释与 DESIGN.md）。
- **选中态**：2pt 强调色外环 + 6pt 强调色 22% 光晕 + 背景略提亮；选中卡片的 ⌘N 键帽变为实心强调色。
- **类型化卡片**：
  - 链接：38pt 网站图标底板 + 域名 + 页面标题（有则显示）+ 完整地址（中间截断）。
  - 代码：语言徽标（如「Swift」）+ 轻量语法着色（关键字 / 字符串 / 类型三色即可）；两种外观下代码卡都是深底。
  - 颜色：左侧 40pt 色块图标 + HEX（18pt 等宽）+ `rgb(...)` · 来源 · 时间；卡片底色仍是该颜色。
  - 图片：缩略图内缩 6pt、圆角 11，高 128；下方一行来源 · 尺寸；晾在绳上的图片右上角「晾着」徽标。
- **分组标题**：列表按「今天 / 昨天 / 更早」分组（11pt semibold，次要色）。
- **悬停快捷操作**：鼠标悬停卡片时右上角出现浮动工具条：收藏 ⌘P / 预览 空格 / 删除 ⌘⌫（图片卡另有「挂到晾衣绳」「贴到屏幕」）。注意面板是 key window，可用 `onHover`；预览面板不是，见 DESIGN.md 实现约束。
- **分类栏**：分段控件样式（深色底槽 + 选中项浮起的胶囊）。
- **顶栏**：搜索框（36pt 高）+ 布局切换按钮 + 截图 + 设置。**搜索框所在的 HStack 必须允许收缩**（设计复查时发现搜索框会把设置按钮挤出面板）。
- **底栏**：38pt，略深的底色；内容规则不变。

## 2. 深浅色：用户可选，默认跟随系统

- 新设置 `AppSettings.appearance: AppAppearance`（`system` 默认 / `light` / `dark`），持久化键 `appearance`。
- 应用方式：`NSApp.appearance = nil / .aqua / .darkAqua`，启动时与设置变更时都要应用（AppDelegate 里 `observe` 一下）。作用于面板、预览、晾衣绳、设置、引导等所有窗口。
- 入口：设置 › 通用最上方「外观」（三张缩略图），菜单栏菜单「外观 ›」子菜单，首次引导第 3 步。
- 浅色画板（`*Light`）给出浅色令牌的样子；未画浅色的界面（预览、搜索、帮助、菜单、其他设置页、引导）照同一规律换色。

## 3. 停靠位置：固定右侧 / 固定底部（Paste 风格）

`PanelPosition` 增加 `.dockRight`、`.dockBottom`，并新增 `PanelLayout { floating, sidebar, shelf }`（**已在分支上写好，见第 7 节**）。

- **固定右侧（sidebar）**：宽 400，高 = 可见区域高 − 16，距右边与上下各 8pt。内容与浮动面板相同（竖向列表），只是更高。入场：从右侧滑入 24pt + 淡入；减弱动态效果时原地淡入。
- **固定底部（shelf）**：宽 = 可见区域宽 − 16，高约 304，距左右下各 8pt。
  - 顶部一行：搜索框（260 宽）+ 分类分段 + 右侧「← → 选择」「↩ 粘贴到 App」提示 + 布局按钮 + 设置。
  - 卡片 214 × 约 220 横向排列，可横向滚动；卡片顶部 34pt 类型色条（类型名 + 时间 + 来源图标），中部内容，底部元信息 + ⌘N。色条用半透明类型色（文本琥珀、链接蓝、图片橙、文件绿、代码中性深色），不是纯色块。
  - 选中卡片上浮 6pt + 外环光晕。
  - 键盘：搜索框为空时 ← → 移动选中项，↑ ↓ 同样可用；翻译卡打开时 ← → 仍归翻译卡。
  - 预览 / 翻译卡出现在横条**正上方、水平居中于选中卡片**，底部对齐、向上长高，最高不超过横条上方剩余空间与 620。
- **切换入口**：设置 › 通用「面板位置」（五张缩略图：鼠标旁、菜单栏图标下、屏幕中央、固定右侧、固定底部）；面板顶栏布局按钮循环 浮动 → 右侧 → 底部 → 浮动（回到上次选的浮动位置 `floatingPanelPosition`）；菜单栏「面板位置 ›」子菜单。
- 点击菜单栏图标时，停靠模式仍然按停靠位置出现（只是出现在图标所在的屏幕）。
- 预览旁置逻辑：浮动 / 侧栏仍是「面板旁边、优先左侧、顶部对齐」。

## 4. ⌃⇧V 只看图片

- 新全局快捷键 `HotKeyAction.images`（id 3），默认 ⌃⇧V（`HotKey.imagesDefault`），可录制、可关闭（与截图快捷键同一套「禁用标志」存储，已写好）。设置 › 通用「只看图片」一行；录制器要与面板、截图、晾衣绳快捷键互相保留（`ShortcutRecorder.Reservation`）。
- 行为：面板未显示 → 打开并切到「图片」分类；已显示且不在图片分类 → 切到图片；已在图片分类 → 关闭。
- **规则统一**：只要分类是「图片」，浮动面板与侧栏就以两列网格显示（150pt 高的格子，圆角 14，底部渐变上叠「来源 · 时间」与 ⌘N）；横条本来就是方卡，不另做网格。
- 网格键盘：↑ ↓ 移动一整行，← → 移动一格（搜索框为空时），翻页移动 5 行（`PanelCommand.selectionIndex(from:count:columns:)` 已支持）。
- 顶部 HUD 胶囊「⌃⇧V 只看图片 · ←→↑↓ 在网格中移动」只在通过快捷键进入时短暂显示。
- 搜索框占位文字改为「按图中文字搜索图片」。

## 5. 晾衣绳（参考 Tendedero，手动挂图）

- 设置：`clotheslineEnabled`（默认开）、`clotheslineHotKey`（默认 ⌃⌥T，可关闭）、`clothesline: Clothesline`（绳上的条目 id，已写好）。另需新增「指针停在顶边多久后滑下」（默认 0.5 秒）。
- **挂上去**：面板里图片卡右键「挂到晾衣绳 ⌘L」、悬停工具条、空格预览底部「晾起来」；已挂的再按 ⌘L 为「从晾衣绳取下」。只支持图片。最多 12 张，超出时取下最早的（`Clothesline.hanging(_:)`）。挂上时绳子短暂滑下 2.5 秒，新照片带一次衰减摆动。
- **截图联动（可选）**：设置 › 截图与标注「自动挂到晾衣绳」，默认关。
- **显示**：屏幕顶部一个透明的非激活 `NSPanel`（与菜单栏同宽，约 250 高，层级低于菜单栏），从菜单栏下方滑出。触发：快捷键切换、菜单栏「显示晾衣绳 · N 张」、指针在屏幕最顶部 2pt 停留设定时长（绳上为空时不触发）。指针离开绳子区域 0.6 秒后收起。全屏应用的空间里不显示。
- **外观**：两端固定点 + 下垂抛物线绳子（`ClotheslineGeometry.ropeDrop`），木夹子，白边相纸（底边留白更宽），静止倾角交替（`restingTilt`），微风摆动（`swing`，减弱动态效果时静止）。悬停的照片放大 1.04、强调色外环、左上角 × 按钮，下方提示胶囊「单击 放大编辑 | 双击 复制 | 拖到应用」。
- 绳窗口不是 key window：悬停状态由控制器轮询指针位置计算，不依赖 `onHover`（DESIGN.md 已有此约束）。
- **交互**（用户明确要求）：
  - **单击 → 放大并标注**（`ClotheslineEdit`）：背景压暗模糊，图片连同夹子落到屏幕中央，绳上原位置显示虚线空位。顶部：来源 · 尺寸 · 晾上时间、缩放、关闭。底部工具条复用截图标注：矩形、椭圆、箭头、画笔、荧光笔、马赛克、文字、序号、6 色、撤销、提取文字、翻译、贴到屏幕、存储、「复制」「完成并晾回」。
    - 优先复用 `ScreenshotOverlayController` / `ScreenshotReducer` / `AnnotationRenderer` 的标注能力（把历史图片当作冻结帧喂进去），而不是另写一套。
    - ⌘C 复制标注后的图；↩「完成并晾回」= 标注结果存为新历史条目并替换绳上原位置，原图保留在历史；esc 放回绳上不保存。
  - **双击 → 复制**到剪贴板 + HUD「已复制到剪贴板」。单击要等双击判定超时后再执行。
  - 拖出 → 发送图片文件副本（`DragProvider`）；× → 取下（不删历史）。
- 条目被删除 / 清空 / 超出历史上限时从绳上消失（`Clothesline.retaining(_:)`）；**收藏与晾着的条目不参与自动清理**。

## 6. 剪贴板安全：地址守护（新功能）

底线（用户明确要求）：**不清除剪贴板、不拦截系统 ⌘V、不改变正常的复制粘贴**。什么都没发生时用户感知不到。

### 6.1 识别（CubbyCore，纯函数 + 单测）
- `SensitiveTextClassifier`：
  - 比特币：Base58Check（1… / 3…）与 Bech32/Bech32m（bc1…），校验和必须通过。
  - 以太坊及 EVM：`0x` + 40 hex；大小写混合时校验 EIP-55。
  - 波场：`T` 开头 Base58Check。
  - Solana：Base58，解码后 32 字节。
  - 莱特币：L/M/ltc1。
  - 银行卡号：13–19 位（允许空格 / 连字符），Luhn 通过。
  - 只对整段文本（去首尾空白）判断，不在长文里搜。

### 6.2 替换检测
- 在 `ClipboardMonitor` 的变化回调上加一层 `AddressGuard`（Core 里做成纯状态机，App 层喂事件）：
  - 记住最近一次「用户复制」的敏感条目（值、类型、时间、当时前台应用）。
  - 剪贴板在 **N 秒（默认 10）内**变成**另一个同类型**敏感值，且前台应用未变，且（有输入监控权限时）期间没有 ⌘C / ⌘X → 判定为被替换。
  - 没有输入监控权限时降级为「同类型 + 前台未变 + 时间窗」，误报会多一些（用户自己连续复制两个地址）。
  - 地址逐位比对整串，计算不同的区段（警示卡标红用）；攻击者常用开头结尾相同的地址。
- 可选「输入监控」：只用 listen-only 的 `CGEventTap` 识别 ⌘C / ⌘X，不记录任何按键内容；设置里显示授权状态与「去授权」。

### 6.3 界面
- **警示卡**（`TamperAlert`）：屏幕中央非激活浮窗，不抢焦点；红色描边与光晕；标题「剪贴板里的地址被替换了」；说明含时间差与前台应用；上下对照「你复制的」（来源 · 时间 · 链 · 校验通过）与「现在剪贴板里的」（来源未知 · 时间 · 不同位数），4 位一组等宽显示，不同段标红；按钮「恢复我复制的地址」（主）/「是我自己换的」/「查看安全记录」。
- 菜单栏图标同时变为红色「地址被替换」，处理后恢复。
- **面板**（`PanelSecurity`）：敏感条目显示链图标、「校验通过」、绿色「守护中」（最近一次复制的那条）或「已核验」；被替换进来的条目显示为红色记录（地址划掉，「来源未知 · 替换了上一条」），不参与 ⌘1–⌘9；从 Cubby 主动粘贴它时弹出确认「仍然粘贴 / 改粘贴我复制的」。银行卡号默认遮挡（`6222 •••• •••• 4821`），预览或粘贴时还原。
- **粘贴核对 HUD**：从 Cubby 粘贴敏感地址后显示 2 秒「已粘贴到『App』，与你复制的一致」+ 首尾高亮的地址。
- **设置 › 剪贴板安全**（`SettingsSecurity`，侧边栏位于「翻译」与「隐私」之间，所有设置页侧边栏都要加）：总开关 + 近 30 天统计；守护的内容；发现被替换时「弹出警示，由我决定」（默认）/「自动换回我复制的，并弹出警示」（仅高可信度）；粘贴后核对开关；输入监控权限行；安全记录（时间 · 事件 · 当时前台应用，本机保存）；底部引导到系统设置「从其他 App 粘贴」。
- 读取保护说明：macOS 不提供「谁读了剪贴板」的第三方接口；只能引导用户在系统设置 › 隐私与安全性 ›「从其他 App 粘贴」把陌生应用设为「询问」。

## 7. 分支现状（未编译，需先 `swift build` 修通）

设计前已在 `feat/ui-dock-gallery-clothesline` 写了 Core 层的一部分，**尚未编译、尚未写测试**：

| 文件 | 改动 |
| --- | --- |
| `CubbyCore/Settings/HotKey.swift` | `HotKey.imagesDefault`（⌃⇧V）、`clotheslineDefault`（⌃⌥T）；`PanelPosition` 加 `.dockRight` `.dockBottom`、`layout`、`cycledLayout(floatingFallback:)`；新增 `PanelLayout`（`isHorizontal`、`imageGridColumns`） |
| `CubbyCore/Settings/HotKeyRegistry.swift` | `HotKeyAction.images = 3`、`.clothesline = 4` |
| `CubbyCore/Settings/AppSettings.swift` | `floatingPanelPosition`、`imagesHotKey`、`clotheslineEnabled`、`clotheslineHotKey`、`clothesline`；可关闭快捷键的通用读写 `storedHotKey` / `store(_:key:disabledKey:in:)` |
| `CubbyCore/Panel/PanelPlacement.swift` | `DockEdge`、`dockMargin`、`docked(_:size:visibleFrame:margin:)`、`detailFrame(...)`（含横条上方预览） |
| `CubbyCore/Panel/PanelCommand.swift` | `.moveLeft` / `.moveRight`；`from(...arrowsMoveHorizontally:)`；`selectionIndex(from:count:columns:)` |
| `CubbyCore/Clothesline/Clothesline.swift`（新） | 绳上条目：去重、容量 12、`hanging` / `removing` / `retaining` |
| `CubbyCore/Clothesline/ClotheslineGeometry.swift`（新） | 绳子下垂、照片分布、尺寸、倾角、摆动 |

已知会编译失败 / 需要跟进的地方：
- `HotKeyAction` 新增 case 后，`AppDelegate` 里对它的 `switch`（`notifyHotKeyConflict`、`currentHotKey`）不再穷尽。
- `Tests/CubbyCoreTests/HotKeyTests.swift` 断言 `PanelPosition.allCases == [.mouse, .statusItem, .center]`，需更新。
- 新 Core 代码都要补测试：项目要求 CubbyCore 行覆盖率 ≥ 95%（`make coverage`）。
- 设计后新增、Core 里还没有的：`AppAppearance`、晾衣绳停留时长、截图自动挂绳、地址守护全部（6.1、6.2）。
- 晾衣绳交互已从最初的「单击复制」改为「单击放大编辑、双击复制」，以本文为准。

## 8. 建议的开发顺序

1. 修通编译，补齐第 7 节 Core 代码的单测（PanelPlacement 停靠与详情区、PanelCommand 横向 / 网格、AppSettings 新键往返与非法值回退、HotKeyRegistry 新动作、Clothesline、ClotheslineGeometry）。
2. 外观设置（第 2 节），先做，后面的界面都要在深浅两种外观下验收。
3. 视觉升级（第 1 节）：令牌 → 卡片 → 顶栏 / 分类 / 底栏。
4. 停靠位置（第 3 节）：PanelController 定位与动画 → 侧栏 → 横条视图 → 预览定位 → 设置 / 顶栏按钮 / 菜单栏子菜单。
5. 只看图片（第 4 节）：快捷键注册 → 图片网格 → 网格键盘。
6. 晾衣绳（第 5 节）：Core 已有 → 绳窗口与显示 / 收起 → 挂取入口 → 双击复制 / 拖出 → 单击放大标注（复用截图标注）→ 设置。
7. 剪贴板安全（第 6 节）：识别器 + 单测 → AddressGuard 状态机 + 单测 → 警示卡 → 面板标记与粘贴确认 → 设置页 → 可选输入监控。
8. 帮助浮层、菜单栏菜单、首次引导第 3 步、设置各页侧边栏、本地化（`make strings` 后补 zh-Hans）、`docs/DESIGN.md` 与 `docs/USER-GUIDE*.md` 同步更新。

每一步都跑 `swift build`、`make test`、`make lint`、`make check-cjk`、`make check-strings`；界面改动用 `make e2e-panel` 与 DEBUG 构建的 `--scenario` 截图对照设计稿（`CUBBY_DATA_DIR` 指向演示数据，见 CONTRIBUTING.md）。

## 9. 杂项

- `.claude/runner/` 是设计阶段远程编译用的临时脚本（已被 `.gitignore` 忽略），可以删除。
- 面板内不要使用 `NSPopover` / sheet 等会成为 key 的子窗口（DESIGN.md 实现约束）；警示卡、绳窗口、放大编辑都应是独立的非激活面板或覆盖层。
- 所有新动画遵循 `Motion` 令牌与「减弱动态效果」规则。
