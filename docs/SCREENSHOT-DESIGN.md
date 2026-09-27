# Cubby 截图与标注 · 设计文档

> 状态：草案 v1（2026-09-27）。给实现者 A / B / C 的开发契约；未拍板事项见 §8。
> 关联文档：`docs/DESIGN.md`（设计 token 与视觉规则）、`docs/ROADMAP.md`（T1.0-02 OCR 搜索）、`docs/QA-CHECKLIST.md`（发版冒烟）。

## 0. 阅读指南

| 你是谁 | 先读 | 再读 |
| --- | --- | --- |
| 实现者 A（Core 逻辑与测试） | §3.2 坐标约定、§3.3 Core 契约、§5.1 Core 测试 | §2 交互规格（弄清每个算法为什么这样） |
| 实现者 B（基础设施与输出） | §3.4 App 契约、§4 分工、§2.13–2.15 权限 / 设置 / 隐私 | §6 风险 |
| 实现者 C（覆盖层 UI） | §2 全部、§3.4 契约、§2.10 视觉规格 | §5.2 场景验证 |
| PM / 维护者 | §1、§7 阶段、§8 开放问题 | — |

术语：

- **冻结帧**（frozen frame）：触发瞬间每块屏幕的静态位图，只存在于内存。
- **覆盖层**（overlay）：铺满每块屏幕、显示冻结帧与遮罩的无边框面板。
- **选区**（selection）：用户框选的矩形，限定在一块屏幕内。
- **标注**（annotation）：画在冻结帧之上的矩形、箭头、文字等，以屏幕坐标存储。
- **贴图**（pin）：把截图作为置顶浮窗留在屏幕上。
- **会话**（session）：一次从触发到结束的完整截图过程。

## 1. 目标与原则

### 1.1 产品目标

用户原话：「截图功能要像微信截图一样，打破常规，让用户体验做到极致。截完图后，可以对图片进行一系列标注和编辑等操作。」

拆成可验收的目标：

1. **快**：按下快捷键到画面冻结 ≤ 150 ms（P50）、≤ 300 ms（P95）；完成后前台应用不变，立刻可以 ⌘V。
2. **准**：悬停自动识别窗口；放大镜像素级取点；选区可用手柄与方向键精修；导出按屏幕原生像素，不模糊。
3. **全**：矩形、椭圆、箭头、画笔、荧光笔、马赛克、文字、序号 8 种标注，撤销 / 重做，选中后可移动、删除、改色；完成 / 保存 / 贴图 / 提取文字四种出口。
4. **稳**：多屏、不同缩放、Space、全屏应用、显示器插拔、权限缺失、安全键盘输入等边界都有明确行为，不会留下卡死的覆盖层。
5. **安静**：不激活应用、不抢焦点、不出声；冻结帧不落盘；权限只在第一次需要时申请。

### 1.2 与 DESIGN.md 原则的对应

| DESIGN.md 原则 | 在截图里的体现 |
| --- | --- |
| 一眼可辨 | 亮的区域就是会被截取的区域：悬停窗口去遮罩、选区去遮罩，其余 40% 黑。 |
| 键盘优先 | 每个工具、每个出口都有单键或 ⌘ 组合；`↩` 在任何有目标的状态下都是「完成」。 |
| 行为可预期 | 标注以屏幕坐标存储，调整选区不会丢标注；撤销只管标注；Esc 永远是「退出」而不是「退一层」（理由见 §2.3）。 |
| 安静克制 | 无提示音、无动画铺陈；HUD 只在结束时出现一次；权限引导只有一个主按钮。 |

### 1.3 非目标（本设计不做）

- 录屏、GIF、定时截图、滚动长截图（长截图放 §7 后续阶段评估）。
- 截图后打开独立编辑窗口（编辑全部在覆盖层内完成，退出即结束）。
- 云上传、分享链接、任何联网行为。
- 沙盒化（Cubby 未沙盒，保存到任意文件夹不需要 bookmark）。

## 2. 交互规格

### 2.1 触发

| 入口 | 行为 | 理由 |
| --- | --- | --- |
| 全局快捷键，默认 `⇧⌘2` | 任意应用内按下即开始会话。可在设置里改或清空（清空后只剩菜单与面板按钮）。 | 与系统 `⇧⌘3/4/5` 同族、好记；避开微信 `⌃⌘A`、QQ `⌃⌘A`、Snipaste `F1`。`⇧⌘2` 未被 macOS 系统保留。 |
| 菜单栏右键菜单「Take Screenshot」 | 位于「Open Clipboard」之后，右侧灰字显示快捷键。 | 与现有菜单项一致（`StatusBarController.titleWithShortcut`）。 |
| 面板顶栏相机按钮 | `PanelHeader` 齿轮左侧加 `camera` 图标按钮，tooltip「Take Screenshot (⇧⌘2)」。 | 面板是用户最常打开的界面，放一个入口降低发现成本。 |
| 面板打开时按快捷键 | 先 `hide(animated: false)` 面板，再开始会话。 | 面板不能出现在冻结帧里；Carbon 热键是全局的，面板打开时也会触发。 |

再次按下快捷键（会话进行中）：

| 当前阶段 | 行为 | 理由 |
| --- | --- | --- |
| capturing / hovering / selecting，且没有任何标注 | 取消会话（等同 Esc） | 与面板快捷键的「toggle」语义一致；误触后再按一次就能退出。 |
| 已有标注，或正在编辑文字 | 忽略 | 一次误触不能毁掉已经画好的标注。 |

### 2.2 状态机

```
idle ──hotkey/menu/button──▶ capturing ──frames ready──▶ hovering
  ▲                             │ 失败/超时/权限                │ 拖拽 ≥ 4pt
  │                             ▼                             ▼
  │◀──────────── finishing ◀── (任何阶段: Esc / 完成 / 保存 / 贴图 / OCR / 取色 C)
  │                             ▲                        selecting
  │                             │                             │ 松开鼠标
  │                             │                             ▼
  │                         annotating ◀──选工具── adjusting ◀──单击窗口/屏幕── hovering
  │                          │      ▲          (无工具，可移动/缩放选区)
  │                          ▼      │ 提交/取消
  │                       editingText
  └────────────────────────────────────────────────── 右键（有选区）→ 回到 hovering，标注保留
```

| 阶段 | 定义 | 屏幕上有什么 | 退出条件 |
| --- | --- | --- | --- |
| `idle` | 没有会话 | — | 触发 |
| `capturing` | 已请求冻结帧，覆盖层尚未显示 | 什么都不显示（光标不变） | 帧到达 → `hovering`；失败 / 超时 2 s / 无权限 → `finishing(.failed)` |
| `hovering` | 无选区 | 冻结帧 + 40% 遮罩、光标下窗口高亮、放大镜、十字光标 | 拖拽 → `selecting`；单击 → `adjusting`；`↩` → 以悬停目标 `finishing(.copy)`；Esc / 右键 → 取消 |
| `selecting` | 正在拖拽创建选区 | 选区实时描边、尺寸标签、放大镜 | 松开 → `adjusting`（< 4×4 pt 视为单击）；Esc → 放弃本次拖拽回 `hovering` |
| `adjusting` | 有选区、无工具（指针模式） | 8 手柄、尺寸标签、工具栏；拖拽手柄时放大镜出现 | 选工具 → `annotating`；右键 → `hovering`；出口动作 → `finishing` |
| `annotating` | 有选区、某工具激活 | 同上 + 样式条；拖拽 = 画标注 | 再按同一工具键 / 点指针 / `V` → `adjusting`；文字工具单击 → `editingText` |
| `editingText` | 文本框处于编辑 | 原生 `NSTextView`、虚线框 | 点击外部 / Esc / `⌘↩` 提交（空则丢弃）→ `annotating` |
| `finishing` | 正在导出 / 写剪贴板 / 落盘 | 覆盖层立即消失，HUD 提示 | 完成 → `idle` |

**子状态**：`adjusting` 与 `annotating` 内部各有 `drag: none | creatingSelection | movingSelection | resizing(handle) | drawing(Annotation) | movingAnnotation(id)`；`selectedAnnotation: AnnotationID?` 在两者中都存在。状态机的纯逻辑部分放在 Core 的 `ScreenshotSession` / `ScreenshotReducer`（§3.3.10），覆盖层只负责渲染与把 `NSEvent` 翻译成 `ScreenshotEvent`。

**Esc 为什么不逐层退出**：DESIGN.md 的「逐层退出」针对面板这种可长期停留的界面；截图是短暂的模态操作，用户按 Esc 的心理预期是「我不截了」（macOS `⇧⌘4` 与微信都如此）。「退一层」的需求由右键（清选区）、工具键再按一次（回指针）承担。唯一例外是 `editingText`：Esc 提交文字而不退出，因为输入法用户会用 Esc 关闭候选框，这时 Esc 若退出整个会话会丢失所有标注。

### 2.3 各阶段的鼠标与键盘行为

坐标全部指 CG 全局点坐标（§3.2）。「拖拽阈值」= 4 pt：鼠标按下后移动不足 4 pt 且在 300 ms 内松开视为单击。

> 实现偏差：reducer 是纯函数、不读时间，只按距离判定（移动不足 4 pt 即视为单击），不判断 300 ms。

#### hovering（无选区）

| 输入 | 行为 | 理由 |
| --- | --- | --- |
| 移动鼠标 | 用 `WindowHitTester.topmost(at:)` 找光标下最上层普通窗口（layer 0、alpha > 0、≥ 2×2 pt、非 Cubby）；命中则该窗口区域去遮罩 + 2 pt 强调色描边；没有命中则整块屏幕去遮罩 + 描边。 | 「亮的就是会被截的」：让整屏与窗口用同一套视觉语言，用户不用学两种状态。 |
| 单击（窗口 / 屏幕上） | 选区 = 命中窗口的 frame ∩ 当前屏幕 frame（窗口跨屏时只取光标所在屏的部分）；无窗口则选区 = 整屏。进入 `adjusting`。 | 选区只限一块屏幕（§2.5），跨屏窗口截半张比拒绝操作更符合预期。 |
| 拖拽 ≥ 4 pt | 进入 `selecting`，起点为按下位置。 | — |
| 双击窗口 | 第一次单击进 `adjusting`，第二次单击落在选区内构成双击 → 完成（复制）。 | 「双击窗口即截取」是自然涌现的快捷路径，无需额外规则。 |
| 右键 | 取消会话。 | PM 规格。 |
| `↩` / `⌘C` | 以悬停目标（窗口或整屏）作为选区，直接完成（复制）。 | `⇧⌘2 ↩` 两键截整屏，比系统 `⇧⌘3` 多的只是可预览。 |
| `⌘A` | 选区 = 光标所在整屏，进入 `adjusting`。 | 与「全选」直觉一致，随后可继续标注。 |
| `C` | 复制放大镜当前显示格式的颜色（HEX 或 RGB），结束会话，HUD「Copied #FF8800」。 | 取色是单一意图动作，取完即走比多按一次 Esc 快；与微信一致。 |
| `⇧`（按住） | 放大镜信息在 HEX / RGB 之间切换（松开恢复）。 | PM 规格；按住而非切换，避免留下隐藏状态。 |
| `⌘Z` | 阶段 2：恢复上一次选区（§7.2）。阶段 1：无操作。 | — |
| Esc / 快捷键再按 | 取消会话。 | — |

#### selecting（拖拽创建选区）

| 输入 | 行为 | 理由 |
| --- | --- | --- |
| 拖动 | 选区 = `SelectionGeometry.normalized(from: anchor, to: cursor)`，夹紧到起点所在屏幕。实时显示尺寸标签与放大镜。 | 起点决定屏幕，保证选区永远在一块屏幕内。 |
| 按住 `⇧` 拖动 | 约束为正方形（边长取较小者，方向跟随光标象限）。 | PM 规格（macOS 的 ⇧ 是锁定单轴，见 §8 Q3）。 |
| 按住 `⌥` 拖动 | 以起点为中心对称扩展。 | macOS `⇧⌘4` 同款手势，沿用肌肉记忆。 |
| 按住 `空格` 拖动 | 冻结当前尺寸，随鼠标平移整个选区。 | macOS `⇧⌘4` 同款手势。 |
| 松开 | 尺寸 ≥ 4×4 pt → `adjusting`；否则视为单击（按 hovering 单击处理）。 | 避免产生看不见的 1×1 选区。 |
| Esc | 放弃本次拖拽，回 `hovering`（若之前已有选区则恢复它）。 | 拖拽途中反悔不应退出整个会话。 |
| 右键 | 同 Esc。 | — |

#### adjusting（有选区，指针模式）

| 输入 | 行为 | 理由 |
| --- | --- | --- |
| 移动鼠标 | 手柄上：对应缩放光标；边带（手柄之间 6 pt 宽）上：同侧手柄的光标；选区内：`arrow`；命中标注：`openHand`；选区外：`crosshair`。 | 光标即提示，不用文字说明。 |
| 拖手柄 / 边带 | `SelectionGeometry.resizing(_:handle:to:constrainSquare:minSize:bounds:)`；放大镜出现在光标旁；`⇧` 约束正方形；对边固定。 | — |
| 在选区内拖（未命中标注） | `SelectionGeometry.moved(_:by:bounds:)`，夹紧到屏幕。 | PM 规格。 |
| 在选区外拖 ≥ 4 pt | 创建新选区替换旧选区（进入 `selecting`）；标注保留。 | 与 macOS 一致；标注以屏幕坐标存储，不会丢。 |
| 在选区外单击 | 取消标注选中；不改变选区。 | 单击不应产生破坏性变化。 |
| 单击标注 | 选中它（最上层优先，容差 6 pt）；样式条显示其样式。 | — |
| 拖标注 | 平移该标注（`Annotation.translated(by:)`），松开时作为一次可撤销操作入栈。 | 拖动过程中不入栈，避免撤销一次只回退 1 pt。 |
| 双击选区内 | 完成（复制）。 | PM 规格。 |
| 方向键 / `⇧`+方向键 | 未选中标注：移动选区 1 / 10 pt；选中了标注：移动标注 1 / 10 pt。 | 同一按键作用于「当前焦点对象」。 |
| `⌫` / `⌦` | 删除选中标注。 | — |
| 工具键 `R O A P H M T N` | 激活工具 → `annotating`。 | — |
| `V` | 无操作（已是指针）。 | — |
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做标注。 | — |
| `↩` / `⌘C` / 工具栏 ✓ | 完成（复制）。 | — |
| `⌘S` | 保存到文件。 | — |
| `⌘P` | 贴图。 | P = Pin；单键 `P` 已给画笔。 |
| `⌘T` | 提取文字。 | T = Text；单键 `T` 已给文字工具。 |
| `⌘A` | 选区扩为整屏。 | — |
| 右键 | 清除选区，回 `hovering`；标注保留并继续显示。 | PM 规格；标注保留是因为它们以屏幕坐标存储，重新框选后依然对齐。 |
| Esc | 取消会话（丢弃一切）。 | §2.2 说明。 |
| 滚轮 | 无操作（不缩放、不滚动）。 | 冻结帧没有可滚动内容，任何响应都会让用户困惑。 |

#### annotating（有选区，工具激活）

| 输入 | 行为 | 理由 |
| --- | --- | --- |
| 按下并拖动（任意位置，含选区外） | 按工具创建标注（§2.7）；可以画到选区外，导出时裁掉。 | 允许箭头从选区外指进来，也允许先画后调选区。 |
| 单击（无拖动） | 文字工具：在点击处打开文本框 → `editingText`；序号工具：放置序号；其他工具：无操作。 | 矩形 / 箭头等零尺寸没有意义。 |
| 文字工具单击已有文字标注 | 重新打开该文字的编辑器。 | 修改错别字是高频需求。 |
| 单击 / 拖手柄 | 仍然可以缩放选区（手柄优先级高于绘制）。 | 画完发现框小了，直接拉手柄。 |
| 再按同一工具键、点工具栏同一按钮、`V`、点指针按钮 | 回 `adjusting`。 | 工具是「模式」，需要明确的退出方式。 |
| 按另一工具键 | 切换工具，保留选中状态。 | — |
| 样式条点击 | 若有选中标注：改它的颜色 / 粗细；同时更新该工具的默认样式。 | 先选后改与先改后画都成立。 |
| 其余按键 | 同 `adjusting`。 | — |

#### editingText

| 输入 | 行为 | 理由 |
| --- | --- | --- |
| 打字、输入法组字、`↩` 换行、`⌘Z` | 全部交给 `NSTextView`（覆盖层的按键监听在此阶段只拦截下面三行）。 | 中文输入法必须可用，候选窗要能显示（§2.10 窗口层级）。 |
| Esc | 有组字中的文本（`hasMarkedText`）：交给输入法；否则提交文本（空白 → 丢弃标注）。 | PM 规格 + 输入法保护。 |
| `⌘↩` | 提交。 | 多行文本需要非 Esc 的提交键。 |
| 点击文本框外 | 提交，然后该点击**不再**产生其他效果。 | 一次点击只做一件事，防止「提交 + 意外画了个矩形」。 |

#### finishing

覆盖层立即 `orderOut`（无淡出），随后执行输出（§2.8）。理由：完成后用户下一步通常是切到别处 ⌘V，任何延时都会让粘贴到「还没写入」的剪贴板。取消也立即消失，保持一致。

### 2.4 放大镜

| 项 | 规格 | 理由 |
| --- | --- | --- |
| 可见时机 | `hovering`、`selecting`、拖拽手柄时；其他时候隐藏 | 只有需要像素级精度的时候才出现，避免遮挡标注。 |
| 采样 | 以光标所在**设备像素**为中心的 15×15 像素网格（奇数保证有中心像素；视觉评审后由 17×17 缩小） | `MagnifierSampler.sample(frame:centerPixel:radius: 7)`。 |
| 显示 | 每个源像素画成 8 pt 方格（Retina 上 = 16 设备像素），网格总大小 136×136 pt，最近邻插值、1 px 网格线 `white 0.12` | 用「点」定义放大倍数，不同缩放的屏幕上视觉大小一致。 |
| 中心像素 | 外描 1 pt 强调色 + 内描 1 pt 白，另从格子边缘向中心画 `accent 0.5` 十字辅助线 | 高亮与暗底上都可辨。 |
| 信息区 | 网格下方两行 `FontSize.caption`(11) 等宽数字：第一行 `(x, y)` 为**点坐标**，相对当前屏幕左上角；第二行 `#RRGGBB`；按住 `⇧` 变为 `255, 136, 0` | 点坐标与系统 `⇧⌘4` 的标签一致；HEX 直接可粘贴进 CSS。 |
| 容器 | 圆角 `Radius.control`(8)，背景 `black 0.75`，1 pt `white 0.2` 描边，无阴影 | 不用玻璃：放大镜在暗遮罩上要清晰。 |
| 位置 | 光标右下 (+20, +20) pt；右 / 下放不下则翻到左 / 上（`MagnifierPlacement.frame`），永远完整在当前屏幕内 | PM 规格。 |
| `C` | 复制第二行当前显示的文本；HEX 进历史成为颜色卡，RGB 形式进历史是文本卡（`ContentClassifier` 只识别 HEX） | 复制「所见」最不意外；见 §8 Q5。 |
| 颜色空间 | 冻结帧以 sRGB 采集（§3.4.2），读数即 sRGB 8 位 | 与系统「数码测色计」默认一致。 |

### 2.5 选区与手柄

| 项 | 规格 | 理由 |
| --- | --- | --- |
| 最小尺寸 | 4×4 pt（`SelectionGeometry.minSize`）；拖手柄不能小于它 | 更小的选区在 1x 屏上只有几个像素，无意义。 |
| 屏幕约束 | 选区完整位于一块屏幕内：创建按起点屏幕夹紧，移动 / 缩放 / 方向键都夹紧到同一屏幕 | 不同屏幕缩放不同，跨屏导出无法定义像素。 |
| 描边 | 1 pt 强调色（`NSColor.controlAccentColor`）+ 外侧 1 pt `black 0.25` | 浅色与深色内容上都看得见；不做蚂蚁线动画（安静）。 |
| 遮罩 | 选区外 `black 0.45`；选区内透明 | PM 规格 0.4；窗口服务器按显示器色彩空间混合，实测折算回 sRGB 偏浅，故上调到 0.45（实测约 0.405）。 |
| 手柄 | 4 角 + 4 边中点，直径 8 pt 圆，白色填充、1.5 pt 强调色描边；悬停放大到 10 pt | 圆形手柄与 macOS 26 的圆润语言一致；8 pt 在 1x 屏上也够点。 |
| 手柄命中 | 手柄中心 ±8 pt；边带宽 6 pt（`SelectionGeometry.hitRegion(at:in:)`） | 手柄小、命中大。 |
| 小选区退化 | 宽或高 < 40 pt：只画 4 角手柄；< 16 pt：不画手柄，边带仍可拖 | 手柄互相重叠时反而更难操作。 |
| 尺寸标签 | 文本 `W × H`（**像素**，= 点 × 屏幕缩放），`FontSize.caption` semibold 等宽数字，白字，`black 0.65` 胶囊，内边距 3×7 | 用户关心导出像素尺寸；像素比点更直观。 |
| 尺寸标签位置 | 选区左上角外侧，上方 6 pt；上方放不下 → 下方外侧；仍放不下 → 内侧左上 6 pt（`SizeLabelPlacement.frame`） | PM 规格补全「下方」这一档，避免直接跳到内侧遮内容。 |
| 光标 | hovering / selecting：`crosshair`；手柄：macOS 15+ 用 `NSCursor.frameResize(position:directions:)`，macOS 14 回退 `resizeLeftRight` / `resizeUpDown`（角用 `crosshair`）；选区内：`arrow` | 公开 API 优先，不用私有光标。 |

### 2.6 工具栏与样式条

**工具栏内容**（从左到右，SF Symbols，tooltip 含快捷键）：

| 组 | 项 | 符号 | 快捷键 |
| --- | --- | --- | --- |
| 模式 | 指针 | `cursorarrow` | `V` |
| 工具 | 矩形 / 椭圆 / 箭头 / 画笔 / 荧光笔 / 马赛克 / 文字 / 序号 | `rectangle` / `oval` / `arrow.up.right` / `pencil.line` / `highlighter` / `checkerboard.rectangle` / `textformat` / `1.circle` | `R O A P H M T N` |
| 历史 | 撤销 / 重做 | `arrow.uturn.backward` / `arrow.uturn.forward` | `⌘Z` / `⇧⌘Z` |
| 输出 | 提取文字 / 翻译 / 贴图 / 保存 | `text.viewfinder` / `translate` / `pin` / `square.and.arrow.down` | `⌘T` / `⇧⌘T` / `⌘P` / `⌘S` |
| 结束 | 取消 / 完成 | `xmark` / `checkmark` | `Esc` / `↩` |

分隔线：模式与工具之间不分隔（指针视为工具之一）；工具｜历史｜输出｜结束之间各一条 1 pt `primary 0.1` 竖线。撤销 / 重做不可用时 `secondary` 变淡并禁用（翻译进行中也禁用：Esc 才是取消翻译）。

**翻译按钮**（截图翻译，[`TRANSLATION-DESIGN.md`](TRANSLATION-DESIGN.md)）：只在 macOS 26+ 且 App 提供了翻译服务时显示（`ScreenshotSession.isTranslationAvailable`，由协调器在覆盖层上屏前设置）。已有译文时按钮高亮，tooltip 变为「显示原文 (⇧⌘T)」/「显示译文 (⇧⌘T)」：再按切换「原文 | 译文」开关；失败状态下再按即重试。翻译条出现在工具栏远离选区的一侧（间距 6 pt、右对齐工具栏），有工具激活时样式条排在翻译条之后（`TranslationBarPlacement`）。

**尺寸与材质**：

| 项 | 规格 |
| --- | --- |
| 按钮 | 28×28 pt，图标 `FontSize.callout`(14) medium，悬停 `primary 0.08` 底、圆角 `Radius.control`；激活工具：`accent 0.15` 底 + 强调色图标；✓ 强调色，✕ `secondary` |
| 容器 | 内边距 4，项间距 2，圆角 `Radius.card`(12)；macOS 26 `NSGlassEffectView(.regular)` 经 `PanelChrome.makeContainer(for:cornerRadius:)` 圆弧裁剪（复用 §PanelChrome 的投影修复）；更早系统 `NSVisualEffectView(.hudWindow, withinWindow)` |
| 尺寸 | 16 项 ≈ 520 pt 宽、36 pt 高；宽度与选区无关，只夹紧在屏幕内 |
| 位置 | 右对齐选区右边缘、选区下方 8 pt；下方放不下 → 上方 8 pt；上方也放不下 → 选区内右下角内缩 8 pt（`ToolbarPlacement.frame` 返回 `.below / .above / .inside`）。左边缘不足时向右推到屏幕内 |
| 出现 | 进入 `adjusting` 时 0.12 s 淡入；拖拽选区 / 手柄期间隐藏（松开后回来） |

**样式条**：选中工具后出现在工具栏「远离选区」的一侧（工具栏在下则样式条在其下方，间距 6 pt），右对齐工具栏。内容按工具：

| 工具 | 第一组（`⌘1/2/3` 备选，阶段 2） | 第二组 |
| --- | --- | --- |
| 矩形 / 椭圆 / 箭头 / 画笔 | 粗细 3 档：圆点 4 / 6 / 8 pt，对应线宽 2 / 3 / 5 pt（画笔 2 / 4 / 6） | 8 色 |
| 荧光笔 | 宽度 3 档：12 / 18 / 26 pt | 8 色（默认黄） |
| 马赛克 | 笔刷 3 档：12 / 24 / 40 pt | 无 |
| 文字 | 字号 3 档：`S M L` = 14 / 20 / 28 pt | 8 色 |
| 序号 | 直径 3 档：20 / 26 / 32 pt | 8 色 |

8 色（sRGB）：`#FF3B30` 红（默认）、`#FF9500` 橙、`#FFCC00` 黄、`#34C759` 绿、`#007AFF` 蓝、`#AF52DE` 紫、`#000000` 黑、`#FFFFFF` 白。理由：Apple 系统调色板，深浅背景都可辨；白 / 黑用于高对比场景。色块 16 pt 圆、1 pt `white 0.6` 描边；选中态外加 2 pt 强调色环（与 DESIGN「选中态 2 pt 强调色外环」一致）；白色色块另加 1 pt `black 0.2` 描边防止消失在玻璃上。

**样式记忆**：每个工具的样式独立，跨会话持久化（`AppSettings.annotationStyles: ToolStyles`，§3.3.13）。改样式条即写回；有选中标注时同时应用到它。理由：用户通常固定用「红色箭头」「黄色荧光笔」，每次重设很烦。

### 2.7 各工具的行为

通用规则：拖拽期间在「实时层」画原始几何（低延迟），松开时生成不可变 `Annotation` 进入 `AnnotationDocument`（一次可撤销操作）。线宽、字号均以**点**定义，导出时乘以屏幕缩放。

| 工具 | 创建 | `⇧` | 细节 |
| --- | --- | --- | --- |
| 矩形 `R` | 拖拽对角 | 正方形 | 线宽按档；圆角 0；描边居中于几何边界。 |
| 椭圆 `O` | 拖拽外接矩形 | 圆 | 同上。 |
| 箭头 `A` | 拖拽：起点 = 尾，终点 = 头 | 角度吸附 45° | **锥形箭头**（macOS 标记同款）：单一填充路径，尾宽 = 线宽 × 0.5，箭杆渐宽至线宽 × 1.2，箭头长 = clamp(线宽 × 6, 10, 28) pt、翼宽 = 箭头长 × 0.8，箭杆两侧微凹的二次曲线（`ArrowGeometry.taperedPath`）。短于箭头长时只画箭头。 |
| 画笔 `P` | 自由拖拽 | — | 输入点抽稀（相邻 < 1.5 pt 丢弃），Catmull-Rom（张力 0.5）转三次 Bézier（`StrokeSmoothing.path(through:)`）；圆头圆角；实时层画折线，松开后换成平滑曲线。 |
| 荧光笔 `H` | 自由拖拽 | — | 宽笔、方头（`.butt`）、圆角连接；颜色 alpha 1 画进透明层，整层以 0.5 alpha（视觉评审后由 0.35 上调）、`multiply` 混合合成 → 自交叉不加深、文字仍清晰。 |
| 马赛克 `M` | 自由拖拽 | — | 笔刷式：笔迹路径（圆头，宽 = 笔刷档）作为裁剪，在其中绘制**整帧的像素化副本**（块大小 = 笔刷宽 / 2，最小 6 px）；副本按块大小惰性生成一次并缓存（`Pixelator.pixelated(_:blockSize:)`，后台线程）。像素化只作用于冻结帧，不作用于其他标注。 |
| 文字 `T` | 单击放置；拖拽 = 单击 | — | 原生 `NSTextView`：透明背景、1 pt 强调色虚线框、内边距 4、系统字体 semibold、颜色 = 样式色、最小宽 40 pt、宽度随内容增长至选区右缘再换行；提交后用 CoreText 以同一字体、同一换行宽度渲染（`TextLayout`）。不加描边 / 阴影（见 §8 Q6）。 |
| 序号 `N` | 单击放置（中心 = 点击点） | — | 实心圆（直径按档，外加 1.5 pt 白色描边）+ 白色粗体数字（字号 = 直径 × 0.6，视觉评审后由 0.55 上调）。编号 = 该标注在文档中序号类标注里的位置 + 1，**由顺序推导**而非存储：删除中间一个，后面自动补位；撤销 / 重做天然一致。 |

标注的选中态（指针模式单击后）：沿其 `bounds` 外扩 4 pt 画 1 pt 强调色虚线框；文字、序号亦同。选中后 `⌫` 删除、方向键微移、样式条改色 / 改档。不提供旋转、缩放已画标注（阶段 2 评估）。

### 2.8 输出动作

所有出口先做同一件事：`ScreenshotExporter.export(frame:screen:selection:document:)` → 在**当前屏幕原生像素**下把「选区裁剪 + 标注」渲染为 `CGImage` 并编码 PNG（`ScreenshotExport`）。像素矩形 = `(selection − screen.origin) × scale` 后取整（`integral`），避免半像素缝。PNG 附带 DPI 元数据（`kCGImagePropertyDPIWidth = 72 × scale`），让 Preview 按点尺寸显示。

| 出口 | 触发 | 行为 | HUD |
| --- | --- | --- | --- |
| 完成（复制） | `↩` `⌘C` 双击 ✓ | 写剪贴板：PNG + TIFF + `PasteboardReader.markerType`（`ScreenshotPasteboard.write(png:)`）；未暂停记录时 `ClipStore.record(.image(...), source: .screenshot)`；关闭覆盖层 | 「Copied to clipboard」 |
| 保存 | `⌘S` 按钮 | 默认（「每次存储前询问位置」开启，§9.4）：覆盖层隐藏但保留会话，后台导出后弹出存储对话框（NSSavePanel，只允许 PNG，建议文件名 `Cubby 2026-09-27 01.23.45.png`，起始目录为上次使用的文件夹）；确认后写入所选位置（同名由对话框确认替换），取消则覆盖层带着标注回来。开关关闭时直接写入 §2.14 的目录，文件名同上（`ScreenshotFileNaming`，24 小时制、固定格式、不本地化；重名追加 ` 2`、` 3`）。两种方式都设置扩展属性 `com.apple.metadata:kMDItemIsScreenCapture` 让访达 / 聚焦按截图归类；同时入历史；**不**写剪贴板 | 「Saved to Desktop」（目录名） |
| 贴图 | `⌘P` 按钮 | 创建 `PinnedImageWindow`（§2.9）；同时入历史；不写剪贴板 | 无（贴图本身就是反馈） |
| 提取文字 | `⌘T` 按钮 | 立即关闭覆盖层；对**未叠加标注的**裁剪图跑 Vision（`VNRecognizeTextRequest`，`.accurate`，`["zh-Hans", "en-US"]`，语言校正开）；结果按阅读顺序换行拼接，写剪贴板为文本 + 标记，入历史（文本类型）。识别为空 → 橙色 HUD | 先「Recognizing text…」，完成后「Text copied」 / 「No text found」 |
| 取色 | `C`（放大镜可见时） | 写文本 + 标记；入历史；关闭 | 「Copied #FF8800」 |
| 取消 | `Esc` ✕ 右键(无选区) | 丢弃一切 | 无 |
| 失败 | 权限 / 采集超时 / 无屏幕 | 关闭；见 §2.13 | 橙色 HUD 说明原因 |

历史条目的来源：`SourceApp(bundleID: Bundle.main.bundleIdentifier, name: "Screenshot")`（英文 key，本地化后中文为「截图」）。理由：卡片来源图标用 Cubby 图标（bundle 已安装，能取到图标），名称显示「截图」，一眼可辨；不用假 bundle ID，避免来源图标退化成通用符号。记录直接调用 `ClipStore.record`，不经过 `ClipboardMonitor`（写剪贴板带了标记，监视器会跳过），因此恰好一条。相同 PNG 再次记录会按 `contentHash` 合并到顶部。

HUD 位置：选区中心（转换到 AppKit 坐标后交给 `HUDToast.show(_:at:)`）；取消不提示。理由：HUD 出现在用户视线所在处。

### 2.9 贴图窗口

| 项 | 规格 | 理由 |
| --- | --- | --- |
| 窗口 | `NSPanel`，`[.borderless, .nonactivatingPanel]`，`level = .floating`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，`canBecomeKey = true`，`hasShadow = true`；出现时 `orderFrontRegardless`，不抢键盘焦点（单击后才成为 key） | 与 `ClipPanel` 同族：不激活应用；`.floating` 高于普通窗口、低于菜单栏。用户贴图后通常还要在原应用里继续输入。 |
| 初始位置与尺寸 | 与选区**原位、1:1（点）**重合，圆角 `Radius.control`(8)，1 px `white 0.15` 内描边 | PM 规格；初始像「没截走」，随后可拖开。 |
| 拖动 | 任意处按住拖动：`isMovableByWindowBackground = false`，由内容视图在 `mouseDown` 中调用 `window.performDrag(with:)`；单击同时让贴图成为 key | 系统的「按背景拖动」会吞掉 `mouseDown`，无法同时识别双击关闭。 |
| 缩放 | 滚轮（每 tick ×1.05；触控板精确滚动每 8 pt 算一 tick）与捏合手势，以光标为锚点，范围 10%–400%（另保证较短边不小于 24 pt，原图本身更小时至少 1:1）；`⌘0` 回 1:1；缩放时窗口正中显示百分比提示（子窗口，约 0.8 s 后淡出） | PM 规格；锚点在光标下缩放才不会「跑掉」；太小的贴图无法再悬停操作。 |
| 不透明度 | 右键菜单 100 / 80 / 60 / 40 % | PM 规格。 |
| 右键菜单 | Copy ⌘C · Save… ⌘S · Opacity ▸ · Close ⌘W | 与工具栏出口一致。 |
| 键盘（窗口为 key 时） | `⌘C` 复制、`⌘S` 保存、`⌘W` / `Esc` 关闭、`⌘0` 1:1 | PM 规格 + ⌘W 惯例。 |
| 双击 | 关闭 | PM 规格。 |
| 悬停 | 无额外控件（阶段 2 评估左上角关闭点） | 安静克制。 |
| 生命周期 | 可多个；退出应用即消失；不持久化 | 贴图是临时参考，不值得跨启动恢复。 |
| 被再次截图 | 贴图窗口**会**出现在下一次的冻结帧里（不排除） | 它是用户屏幕上真实可见的内容，与系统截图行为一致。 |

### 2.10 视觉规格汇总

沿用 `DesignTokens.swift`；截图专属常量放 `Sources/Cubby/Screenshot/Overlay/OverlayTokens.swift`（C 所有），Core 的摆放算法把尺寸作为参数接收、不内置 UI 常量。

| 项 | 值 |
| --- | --- |
| 遮罩 | `black 0.45`（见 §2.5 说明） |
| 悬停窗口 / 整屏描边 | 2 pt 强调色（`controlAccentColor`），内缩 1 pt |
| 选区描边 | 1 pt 强调色 + 外 1 pt `black 0.25` |
| 手柄 | Ø 8 pt（悬停 10）白填充、1.5 pt 强调色描边 |
| 尺寸标签 | 11 semibold 等宽数字，白，`black 0.65` 胶囊，内边距 3×7 |
| 放大镜 | 136×136 网格 + 2 行信息，圆角 8，`black 0.75`，1 pt `white 0.2` |
| 工具栏 / 样式条 | 圆角 12，内边距 4，项 28×28，间距 2；macOS 26 玻璃 `.regular`，更早 `.hudWindow` |
| 标注选中框 | 1 pt 强调色虚线（4-2），外扩 4 pt |
| 文本编辑框 | 1 pt 强调色虚线，内边距 4 |
| 贴图 | 圆角 8，1 px `white 0.15` 内描边，系统阴影 |
| 动效 | 覆盖层出现 / 消失：无动画；工具栏出现 0.12 s 淡入；手柄悬停放大 0.1 s |
| 光标 | 见 §2.5 |

**覆盖层窗口层级 = `.statusBar`（25）**，不是 `.screenSaver` 或 shielding。理由：25 高于菜单栏（24）与 Dock（20），满足「盖住菜单栏和 Dock」；同时低于弹出菜单（101）、工具提示（102）与输入法候选窗，所以工具栏 tooltip、贴图右键菜单、中文候选框都能显示在覆盖层之上。用 1000 级会把候选框压在下面，中文输入直接不可用。代价：其他应用的 101 级弹出窗（例如打开着的状态栏 popover）会显示在覆盖层之上；实际上覆盖层成为 key 时它们会因失焦自动关闭。

### 2.11 快捷键一览

| 按键 | hovering | selecting | adjusting | annotating | editingText | 贴图窗口 |
| --- | --- | --- | --- | --- | --- | --- |
| `Esc` | 取消 | 放弃拖拽 | 取消（识别 / 翻译进行中只取消翻译；翻译失败时关闭翻译条） | 同左 | 提交 | 关闭 |
| `↩` | 截悬停目标 | — | 完成 | 完成 | 换行 | — |
| `⌘↩` | — | — | 完成 | 完成 | 提交 | — |
| `⌘C` | 截悬停目标 | — | 完成 | 完成 | 文本复制 | 复制 |
| `⌘S` | — | — | 保存 | 保存 | — | 保存 |
| `⌘P` | — | — | 贴图 | 贴图 | — | — |
| `⌘T` | — | — | 提取文字 | 提取文字 | — | — |
| `⌘A` | 选整屏 | — | 选整屏 | 选整屏 | 全选文本 | — |
| `⌘Z` / `⇧⌘Z` | （阶段 2：恢复选区） | — | 撤销 / 重做 | 撤销 / 重做 | 文本撤销 | — |
| `⇧⌘T` | — | — | 翻译 / 切换原文·译文 / 失败时重试 | 同左 | 先提交文字再翻译 | — |
| `C` | 取色 | 取色 | 拖手柄时取色 | — | 输入 | — |
| `⇧`（按住） | HEX↔RGB | 正方形 | 正方形（手柄） | 形状约束 | — | — |
| `⌥`（按住） | — | 中心扩展 | — | — | — | — |
| `空格`（按住） | — | 平移选区 | 有译文时看原文（只影响查看） | 同左 | 输入 | — |
| `V` | — | — | — | 回指针 | 输入 | — |
| `R O A P H M T N` | — | — | 选工具 | 选 / 切换 / 取消工具 | 输入 | — |
| 方向键 / `⇧`+ | — | — | 移动选区或选中标注 1 / 10 pt（卷帘分隔线拖过之后 ← / → 微调分隔线：选区宽 1/50、⇧ 为 1/10） | 同左 | 光标移动 | — |
| `⌫` `⌦` | — | — | 删除选中标注 | 同左 | 删字 | — |
| 右键 | 取消 | 放弃拖拽 | 清选区 | 清选区 | 提交后清选区 | 菜单 |
| 双击 | 截该窗口 | — | 完成 | 完成 | 选词 | 关闭 |
| `⌘W` | — | — | — | — | — | 关闭 |
| `⌘0` | — | — | — | — | — | 1:1 |

字母键按**字符**匹配（兼容 Dvorak），修饰键组合按 `PanelCommand` 的做法用 keyCode + flags；映射函数 `ScreenshotCommand.from(keyCode:modifiers:characters:phase:)` 在 Core，可测。

### 2.12 边界情况

| 情形 | 行为 | 理由 / 实现要点 |
| --- | --- | --- |
| 多屏、缩放不同（如 2x 内置 + 1x 外接） | 每屏各自采集原生像素帧、各自一个覆盖层；选区只在一屏；导出用该屏 `scale`；放大镜格子按点定义 | §3.2 坐标约定。 |
| 屏幕排列有空隙 / 非矩形布局 | 覆盖层只覆盖每个 `NSScreen.frame`，空隙不处理；鼠标在空隙中时不会有事件 | — |
| Space / 全屏应用 | `.canJoinAllSpaces + .fullScreenAuxiliary`，`orderFrontRegardless()`；全屏应用之上也能显示；冻结帧就是当前 Space 的内容 | 与 `ClipPanel` 一致。 |
| 菜单栏、Dock、桌面 | 被覆盖层盖住；悬停时它们不算「普通窗口」（layer ≠ 0），落在其上等于选整屏 | 用户要截 Dock 时框选即可。 |
| 光标在桌面（无窗口） | 整屏高亮 | §2.3。 |
| 截图时面板 / HUD / 设置窗口打开 | 面板先隐藏；采集时 `SCContentFilter` 排除 Cubby 全部窗口但**保留贴图窗口** | 贴图是用户内容；其他是 Cubby 的 UI。 |
| 会话中再按快捷键 | §2.1 | — |
| 会话中显示器插拔 / 分辨率变化（`didChangeScreenParametersNotification`） | 立即取消会话，橙色 HUD「Screen layout changed」 | 冻结帧与新布局对不上，任何补救都不可靠。 |
| 会话中系统弹窗 / 其他应用抢 key | 覆盖层 `resignKey` 时**不**关闭（与面板不同），键盘暂时失效，点击覆盖层重新成为 key | 截图会话不能因为一个通知就消失；`ClipPanel.onResignKey` 的行为不沿用。 |
| 选区极小 | § 2.5 退化规则；工具栏 / 标签一律在外侧 | — |
| 选区贴屏幕边缘 | 工具栏 / 标签 / 放大镜都夹紧在屏幕内；工具栏可能压在选区上（`.inside`） | `ToolbarPlacement` 三档兜底。 |
| 选区 = 整屏 | 工具栏 `.inside`（右下角内缩 8 pt），标签内侧左上 | — |
| 标注画在选区外 | 显示（在遮罩之上，保持完整可见），导出裁掉 | 用户可以随后扩大选区把它们包进去。 |
| 完成时选区内没有任何像素变化 / 纯色 | 正常导出 | 不做「空截图」判定。 |
| 冻结帧采集超时（> 2 s） | 取消，HUD「Couldn't capture the screen」 | macOS 15+ 周期性确认弹窗期间采集会挂起（§6）。 |
| 无屏幕录制权限 | 不显示覆盖层，走 §2.13 引导 | — |
| 「安全键盘输入」已开启（终端 / 密码框） | Carbon 热键**预期仍可触发**（热键由系统匹配，不是事件拦截）；覆盖层自身是 key 窗口，按键直达。若实测热键失效：菜单栏与面板按钮兜底，诊断信息里显示 `Secure input: on` | 见 §6 R9；实现后必须实测。 |
| 暂停记录（`isPaused`） | 仍可截图、仍写剪贴板 / 文件 / 贴图，只是不入历史 | PM 规格。 |
| 历史只读（`ClipStore.canPersist == false`） | 入历史调用照常（store 自己不落盘） | 沿用现有语义。 |
| 输入法组字中按 Esc / ↩ | 交给输入法 | `hasMarkedText()` 判定，与 `PanelController` 一致。 |
| 文本框内容超出选区 | 允许（导出裁掉），编辑时框随内容长 | — |
| 序号超过 99 | 圆自动加宽为胶囊 | 极少见，但不能画烂。 |
| 马赛克覆盖文字标注 | 马赛克只像素化冻结帧；渲染顺序按文档顺序，先画的在下 | 与用户操作顺序一致。 |
| 保存目录不存在 / 不可写 | 回退到桌面并 HUD「Saved to Desktop (folder unavailable)」；两者都失败 → 橙色 HUD 错误 | 永远给用户一个结果。 |
| 图片超过 `CaptureLimits.maxImageBytes`（30 MB PNG） | 剪贴板 / 文件照写；历史跳过并 HUD 加一句「too large for history」 | 6K 全屏 PNG 可能 20–40 MB；限制是历史的，不是截图的。 |
| 会话期间用户切换了浅 / 深色外观 | 工具栏材质随系统 | — |
| VoiceOver | 阶段 1 不承诺；工具栏按钮有 `accessibilityLabel` | 见 §7。 |

### 2.13 权限

需要**屏幕录制**（Screen Recording）。与辅助功能、剪贴板权限相互独立（§6 R10）。

| 时机 | 行为 |
| --- | --- |
| 启动 | 不检查、不申请。 |
| 第一次触发截图 | `CGPreflightScreenCaptureAccess()` 为 false → 调用 `CGRequestScreenCaptureAccess()`（系统只在第一次显示弹窗；之后调用无效果）并**同时**显示 Cubby 自己的引导窗口（§下表）。授权后（每 1.5 s 轮询，复用 `PermissionMonitor` 模式）自动关闭引导窗并提示「Press ⇧⌘2 to take a screenshot」；不自动开始截图，因为 macOS 常要求重启应用才生效。 |
| 之后每次触发 | 只 preflight；false 则再次显示引导窗（不再 request）。 |

引导窗口（`ScreenRecordingGuideWindowController`，复用 `OnboardingStepCard` 风格，宽 460）：

- 图标 `rectangle.dashed.badge.record`，标题「Allow Screen Recording to take screenshots」。
- 正文：「Cubby needs Screen Recording to capture your screen. It only captures when you take a screenshot, and frames stay in memory until you copy, save or pin them.」
- 主按钮「Open System Settings」→ `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`；次按钮「Not Now」。
- 脚注：「macOS may ask you to quit and reopen Cubby after granting access.」

设置 › 隐私：`PermissionRow(title: "Screen Recording", systemImage: "rectangle.dashed.badge.record", buttonTitle: "Open System Settings")`，状态文案：Granted / 「Not granted. Only needed for screenshots.」；页脚补一句「Screen Recording is only used when you take a screenshot.」。引导（Onboarding）窗口**不**加这一步，理由：不是核心功能，DESIGN 要求权限「只在需要时温和提示」。

诊断信息新增三行：`Screen recording: granted|denied`、`Screenshot shortcut: ⇧⌘2|off, save location: system default|<path>`、`Secure input: on|off`（`IsSecureEventInputEnabled()`）。

### 2.14 设置

设置 › 通用新增分组「Screenshots」：

| 项 | 控件 | 存储 |
| --- | --- | --- |
| Screenshot shortcut | `ShortcutRecorder`（B 扩展为可清空：多一个「Off」按钮；默认值参数化为 `HotKey.screenshotDefault`） | `AppSettings.screenshotHotKey: HotKey?`（nil = 关闭） |
| Save screenshots to | 「Same as macOS screenshots (Desktop)」/「Choose Folder…」（`NSOpenPanel` 选目录）+ 当前路径灰字 + 「Reset」 | `AppSettings.screenshotSaveDirectory: URL?`（nil = 跟随系统：读 `com.apple.screencapture` 域的 `location`，无则桌面） |

录制器拒绝规则新增：与面板快捷键相同 → 「Already used to open the panel」；反之亦然。两个热键都注册失败时沿用 `notifyHotKeyConflict` 的回退逻辑。

不做的设置（理由：YAGNI，先看反馈）：截图后是否自动复制、是否播放声音、遮罩深浅、是否显示放大镜、文件格式（只 PNG）。

### 2.15 隐私

- 冻结帧、像素化副本、导出位图只存在于内存；会话结束（任何出口）立即释放（`CaptureSession` 被丢弃，无缓存）。
- 只在完成 / 保存 / 贴图 / 提取文字 / 取色时落盘或入历史；取消不留任何痕迹。
- 不记录窗口标题、应用名到日志；`Logger` 只记阶段与耗时，`privacy: .public` 的字段限于枚举和数字。
- OCR 完全本地（Vision），不联网；`PRIVACY.md` 需补一段（由 B 在阶段 1 末补，见 §4）。
- 屏幕录制权限只在用户主动截图时使用；启动、后台绝不采集。

## 3. 架构

### 3.1 模块与文件布局

原则：能不碰 AppKit 窗口 / 视图的逻辑一律进 `CubbyCore`（可测、95% 覆盖率门槛）；App 层只做「系统 API 适配 + 渲染 + 事件翻译」。每个文件 200–400 行，最多 800。

```
Sources/CubbyCore/Screenshot/                         ← 实现者 A（全部新文件）
  Capture/
    CaptureScreen.swift          屏幕描述与点 / 像素换算
    FrozenFrame.swift            冻结帧（CGImage + 屏幕）
    WindowCandidate.swift        窗口候选（frame、layer、owner）
    ScreenTopology.swift         屏幕 + 窗口列表（无位图，可 Equatable）
    CaptureSession.swift         topology + frames
  Selection/
    SelectionHandle.swift        8 手柄枚举、命中区域
    SelectionGeometry.swift      归一化、缩放、移动、夹紧、微调、命中
  Layout/
    ToolbarPlacement.swift       工具栏 / 样式条摆放
    MagnifierPlacement.swift     放大镜摆放
    SizeLabelPlacement.swift     尺寸标签摆放与文本
  Windows/
    WindowHitTester.swift        z 序命中、悬停目标
  Annotation/
    AnnotationColor.swift        8 色调色板（Codable）
    AnnotationStyle.swift        样式（颜色 + 档位）、ScreenshotTool、ToolStyles
    Annotation.swift             标注形状与值类型（bounds、hitTest、translated）
    AnnotationDocument.swift     不可变文档 + 撤销 / 重做
    ArrowGeometry.swift          锥形箭头路径、45° 吸附
    StrokeSmoothing.swift        抽稀 + Catmull-Rom
  Rendering/
    Pixelator.swift              像素化
    TextLayout.swift             CoreText 排版（与 NSTextView 同字体）
    AnnotationRenderer.swift     把文档画进 CGContext（任意缩放）
  Export/
    ScreenshotExporter.swift     裁剪 + 标注 → CGImage / PNG
    ScreenshotFileNaming.swift   文件名与去重
    ScreenshotSaveLocation.swift 保存目录解析
  Clipboard/
    ScreenshotPasteboard.swift   PNG / 文本写剪贴板（带标记）
  Magnifier/
    MagnifierSampler.swift       像素网格采样、颜色格式化
  Session/
    ScreenshotCommand.swift      键盘 → 命令（按阶段）
    ScreenshotSession.swift      会话状态值类型
    ScreenshotReducer.swift      (session, event) → (session, effects)
    ScreenshotReducer+Drag.swift 拖拽相关的 reduce 分支（拆文件控制长度）
    ScreenshotDebugScenario.swift  --scenario 的预置会话

Sources/Cubby/Screenshot/
  ScreenshotCoordinator.swift    ← B：对外入口，串起采集 → 覆盖层 → 输出
  ScreenshotOverlayPresenting.swift ← B：覆盖层协议 + 委托 + 结果类型（C 依赖）
  Capture/                       ← B
    ScreenRecordingAuthorization.swift   权限状态 / 申请 / 打开设置
    ScreenRecordingGuideWindowController.swift  引导窗口
    ScreenTopologyProvider.swift        NSScreen → CaptureScreen、AppKit ↔ CG 坐标换算
    FrozenFrameCapturer.swift           ScreenCaptureKit 采集（协议 FrameSource）
    FixtureFrameSource.swift            DEBUG：合成测试帧 + 假窗口列表
  Overlay/                       ← C
    OverlayTokens.swift          截图专属尺寸常量
    OverlayWindow.swift          每屏一个的无边框 key 面板
    ScreenshotOverlayController.swift   实现 ScreenshotOverlayPresenting；持有 session，分发事件
    OverlayCanvasView.swift      冻结帧、遮罩、选区、手柄、标注（CALayer 分层）
    OverlayLiveStrokeLayer.swift 拖拽中的实时几何
    OverlayInteraction.swift     NSEvent → ScreenshotEvent 翻译、光标
    OverlayKeyboard.swift        本地按键监听 + 输入法保护
    MagnifierView.swift
    SizeLabelView.swift
    ScreenshotToolbar.swift      SwiftUI 工具栏
    ScreenshotStyleBar.swift     SwiftUI 样式条
    TextAnnotationEditor.swift   NSTextView 宿主
    OverlayChrome.swift          玻璃 / 材质容器（调用 PanelChrome.makeContainer(for:cornerRadius:)）
  Output/                        ← B
    ScreenshotOutputService.swift  复制 / 保存 / OCR / 取色 → 剪贴板、历史、HUD
    ScreenshotFileSaver.swift      写文件 + xattr
    TextRecognizer.swift           Vision OCR
    PinnedImageWindow.swift        贴图窗口
    PinnedImageController.swift    贴图集合、右键菜单、缩放

Tests/CubbyCoreTests/Screenshot/   ← A（B 的设置 / 热键测试放 Tests/CubbyCoreTests/ 根目录已有文件旁）
```

B 还会修改的**既有**文件（其他人不得改动）：`Services/HotKeyManager.swift`、`App/AppDelegate.swift`、`App/StatusBarController.swift`、`Panel/PanelController.swift`、`Panel/PanelViewModel.swift`、`Views/PanelHeader.swift`、`Panel/PanelChrome.swift`（加 `cornerRadius:` 参数）、`Settings/GeneralSettingsPane.swift`、`Settings/PrivacySettingsPane.swift`、`Settings/PermissionRow.swift`、`Settings/ShortcutRecorder.swift`、`Services/Diagnostics.swift`；Core 的 `Settings/AppSettings.swift`、`Settings/HotKey.swift`、`Panel/PanelCommand.swift`（加 `.takeScreenshot`）及其测试；`PRIVACY.md`、`CONTRIBUTING.md`（场景表）。

### 3.2 坐标约定（所有人必须遵守）

| 空间 | 原点 | 单位 | 谁在用 |
| --- | --- | --- | --- |
| **全局点（Global Points）** | 主屏左上角，y 向下（即 CoreGraphics / `CGDisplayBounds` / `SCDisplay.frame` / `SCWindow.frame` / `kCGWindowBounds` 的约定） | pt | **Core 的一切**：选区、标注、悬停、摆放算法、reducer |
| AppKit 屏幕坐标 | 主屏左下角，y 向上（`NSEvent.mouseLocation`、`NSScreen.frame`、`NSWindow.frame`、`HUDToast` 锚点） | pt | 仅 App 层，进出时换算 |
| 屏幕局部像素 | 该屏左上角，y 向下 | px | 冻结帧位图、导出、放大镜采样 |

换算（`CaptureScreen`）：`localPoint = global − screen.frame.origin`；`pixel = localPoint × scale`；AppKit ↔ 全局：`globalY = primaryHeight − appKitY`，`primaryHeight = NSScreen.screens[0].frame.height`（B 的 `ScreenTopologyProvider` 提供 `toGlobal(_:)` / `toAppKit(_:)`，是 App 层唯一做这件事的地方）。

理由：采集与窗口 API 全都说 CG 坐标，Core 直接采用它就只剩一处换算（鼠标事件）；把标注存成全局点而不是选区相对坐标，是「调整选区不丢标注」的前提。

CGContext 约定：`AnnotationRenderer` 接收 CoreGraphics 默认（左下原点）的 context，在内部 `saveGState` 后自行翻转并按 `RenderEnvironment` 缩放 / 平移；调用方只需提供目标像素尺寸。

### 3.3 Core 接口契约（实现者 A）

以下签名是契约：名称、参数、`public` 与 `Sendable` 标注不得擅改；实现细节、私有函数自由。`CGImage` 在 SDK 中不是 `Sendable`，包装它的类型标 `@unchecked Sendable` 并注释「CGImage 不可变」。

#### 3.3.1 Capture/

```swift
/// 一块屏幕：CGDirectDisplayID、全局点 frame（左上原点）、缩放
public struct CaptureScreen: Hashable, Sendable, Identifiable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat
    public init(id: UInt32, frame: CGRect, scale: CGFloat)
    public var pixelSize: CGSize
    public func localPoint(_ global: CGPoint) -> CGPoint
    public func pixelPoint(_ global: CGPoint) -> CGPoint        // 向下取整到像素
    public func pixelRect(_ global: CGRect) -> CGRect            // × scale 后 integral，并与 pixelSize 相交
    public func contains(_ global: CGPoint) -> Bool
}

/// 冻结帧；CGImage 不可变，因此 @unchecked Sendable
public struct FrozenFrame: @unchecked Sendable {
    public let screen: CaptureScreen
    public let image: CGImage
    public init(screen: CaptureScreen, image: CGImage)
}

public struct WindowCandidate: Hashable, Sendable {
    public let id: UInt32
    public let frame: CGRect          // 全局点
    public let layer: Int             // 0 = 普通窗口
    public let ownerPID: pid_t
    public let alpha: Double
    public init(id: UInt32, frame: CGRect, layer: Int, ownerPID: pid_t, alpha: Double)
}

/// 屏幕与窗口的几何拓扑（无位图，可比较，供 reducer 与测试使用）
public struct ScreenTopology: Equatable, Sendable {
    public let screens: [CaptureScreen]
    public let windows: [WindowCandidate]   // 前 → 后（z 序）
    public let ownPID: pid_t
    public init(screens: [CaptureScreen], windows: [WindowCandidate], ownPID: pid_t)
    public func screen(containing point: CGPoint) -> CaptureScreen?
    public func screen(id: UInt32) -> CaptureScreen?
}

public struct CaptureSession: @unchecked Sendable {
    public let topology: ScreenTopology
    public let frames: [FrozenFrame]
    public init(topology: ScreenTopology, frames: [FrozenFrame])
    public func frame(for screenID: UInt32) -> FrozenFrame?
}
```

#### 3.3.2 Selection/

```swift
public enum SelectionHandle: CaseIterable, Sendable, Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    public var movesLeftEdge: Bool; public var movesRightEdge: Bool
    public var movesTopEdge: Bool;  public var movesBottomEdge: Bool
    public func center(in rect: CGRect) -> CGPoint
}

public enum SelectionHitRegion: Equatable, Sendable {
    case handle(SelectionHandle)
    case inside
    case outside
}

public enum NudgeDirection: Sendable { case up, down, left, right
    public var vector: CGVector }

public enum SelectionGeometry {
    public static let minSize = CGSize(width: 4, height: 4)
    public static let dragThreshold: CGFloat = 4
    /// 拖拽归一化；constrainSquare = ⇧，fromCenter = ⌥；结果夹紧到 bounds
    public static func normalized(from anchor: CGPoint, to point: CGPoint,
                                  constrainSquare: Bool, fromCenter: Bool, bounds: CGRect) -> CGRect
    /// 按手柄缩放，对边固定；不小于 minSize；不出 bounds
    public static func resizing(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint,
                                constrainSquare: Bool, minSize: CGSize = minSize, bounds: CGRect) -> CGRect
    public static func moved(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect
    public static func nudged(_ rect: CGRect, _ direction: NudgeDirection, step: CGFloat, bounds: CGRect) -> CGRect
    public static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect
    /// 手柄中心 ±handleTolerance 优先，其次边带 edgeBand，再判断内 / 外
    public static func hitRegion(at point: CGPoint, in rect: CGRect,
                                 handleTolerance: CGFloat = 8, edgeBand: CGFloat = 6) -> SelectionHitRegion
    /// 小选区退化：返回应绘制的手柄集合（<16 pt 空集，<40 pt 只有四角）
    public static func visibleHandles(for rect: CGRect) -> [SelectionHandle]
}
```

#### 3.3.3 Layout/

```swift
public enum ToolbarSide: Equatable, Sendable { case below, above, inside }
public struct ToolbarLayout: Equatable, Sendable {
    public let toolbar: CGRect
    public let styleBar: CGRect?      // 与工具栏同侧、更远离选区
    public let side: ToolbarSide
}
public enum ToolbarPlacement {
    public static func layout(toolbarSize: CGSize, styleBarSize: CGSize?, selection: CGRect,
                              screen: CGRect, gap: CGFloat = 8, inset: CGFloat = 8) -> ToolbarLayout
}

public enum MagnifierPlacement {
    /// 光标右下偏移 offset；溢出则分别翻转 x / y；结果完整在 screen 内
    public static func frame(size: CGSize, cursor: CGPoint, screen: CGRect, offset: CGFloat = 20) -> CGRect
}

public enum SizeLabelSide: Equatable, Sendable { case aboveOutside, belowOutside, inside }
public struct SizeLabelLayout: Equatable, Sendable { public let frame: CGRect; public let side: SizeLabelSide }
public enum SizeLabelPlacement {
    public static func layout(labelSize: CGSize, selection: CGRect, screen: CGRect, gap: CGFloat = 6) -> SizeLabelLayout
    /// "1280 × 720"（像素 = 点 × scale，四舍五入）
    public static func text(for selection: CGRect, scale: CGFloat) -> String
}
```

#### 3.3.4 Windows/

```swift
public enum HoverTarget: Equatable, Sendable {
    case window(WindowCandidate, screen: CaptureScreen)
    case screen(CaptureScreen)
    /// 窗口 ∩ 屏幕；整屏则为屏幕 frame
    public var selectionRect: CGRect
    public var screen: CaptureScreen
}
public enum WindowHitTester {
    /// 第一个满足 layer == 0、alpha > 0、宽高 ≥ 2、ownerPID != excludingPID 且包含 point 的窗口
    public static func topmost(at point: CGPoint, in windows: [WindowCandidate], excludingPID: pid_t) -> WindowCandidate?
    public static func hoverTarget(at point: CGPoint, topology: ScreenTopology) -> HoverTarget?
}
```

#### 3.3.5 Annotation/ —— 样式与工具

```swift
public enum AnnotationColor: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, black, white
    public var rgba: RGBAColor          // §2.6 的 sRGB 值
    public var hex: String              // "#FF3B30"
}
public enum StrokeWeight: String, Codable, CaseIterable, Sendable { case light, regular, heavy }

public struct AnnotationStyle: Codable, Hashable, Sendable {
    public let color: AnnotationColor
    public let weight: StrokeWeight
    public init(color: AnnotationColor, weight: StrokeWeight)
    public func withColor(_ color: AnnotationColor) -> AnnotationStyle
    public func withWeight(_ weight: StrokeWeight) -> AnnotationStyle
}

public enum ScreenshotTool: String, Codable, CaseIterable, Sendable {
    case pointer, rectangle, ellipse, arrow, pen, highlighter, mosaic, text, number
    public var shortcutCharacter: Character?     // "v" "r" "o" "a" "p" "h" "m" "t" "n"
    public var symbolName: String
    public var displayName: String               // String(localized:)
    public var usesColor: Bool                   // mosaic / pointer = false
    public var defaultStyle: AnnotationStyle     // highlighter 默认黄，其余红 / regular
    public func strokeWidth(for weight: StrokeWeight) -> CGFloat   // 按 §2.6 表
    public func fontSize(for weight: StrokeWeight) -> CGFloat      // text: 14 / 20 / 28
    public func brushWidth(for weight: StrokeWeight) -> CGFloat    // mosaic: 12 / 24 / 40, highlighter: 12 / 18 / 26
    public func badgeDiameter(for weight: StrokeWeight) -> CGFloat // number: 20 / 26 / 32
}

/// 每个工具的样式记忆；JSON 持久化在 AppSettings.annotationStyles
public struct ToolStyles: Codable, Equatable, Sendable {
    public static let `default`: ToolStyles
    public func style(for tool: ScreenshotTool) -> AnnotationStyle
    public func setting(_ style: AnnotationStyle, for tool: ScreenshotTool) -> ToolStyles
    public static func decode(_ data: Data?) -> ToolStyles       // 失败 / nil → default，未知工具键忽略
    public func encoded() -> Data
}
```

#### 3.3.6 Annotation/ —— 标注与文档

```swift
public struct AnnotationID: Hashable, Sendable, Codable { public init(); public let rawValue: UUID }

public enum AnnotationShape: Equatable, Sendable {
    case rectangle(CGRect)
    case ellipse(CGRect)
    case arrow(from: CGPoint, to: CGPoint)
    case pen([CGPoint])                 // 已抽稀的原始点，渲染时平滑
    case highlighter([CGPoint])
    case mosaic([CGPoint])
    case text(String, origin: CGPoint, maxWidth: CGFloat)
    case number(center: CGPoint)        // 编号由文档顺序推导
}

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: AnnotationID
    public let shape: AnnotationShape
    public let style: AnnotationStyle
    public init(id: AnnotationID = AnnotationID(), shape: AnnotationShape, style: AnnotationStyle)
    public var tool: ScreenshotTool
    /// 几何外接矩形 + 线宽 / 笔刷 / 徽标半径的外扩
    public var bounds: CGRect
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool   // 线条按到线距离，填充类按区域
    public func translated(by delta: CGVector) -> Annotation
    public func withStyle(_ style: AnnotationStyle) -> Annotation
    public func withText(_ text: String) -> Annotation                  // 非 text 返回自身
}

/// 不可变文档：每个变更返回新值；撤销 / 重做栈上限 100
public struct AnnotationDocument: Equatable, Sendable {
    public static let empty: AnnotationDocument
    public let annotations: [Annotation]        // 绘制顺序，先画在下
    public var canUndo: Bool
    public var canRedo: Bool
    public func adding(_ annotation: Annotation) -> AnnotationDocument
    public func removing(id: AnnotationID) -> AnnotationDocument
    public func replacing(_ annotation: Annotation) -> AnnotationDocument     // 同 id 替换；不存在则原样返回
    public func undone() -> AnnotationDocument
    public func redone() -> AnnotationDocument
    public func annotation(id: AnnotationID) -> Annotation?
    public func topmost(at point: CGPoint, tolerance: CGFloat) -> Annotation?
    /// 序号标注的显示编号（1 起）；非序号返回 nil
    public func numberLabel(for id: AnnotationID) -> Int?
    public var nextNumber: Int
}

public enum ArrowGeometry {
    public static func taperedPath(from tail: CGPoint, to head: CGPoint, lineWidth: CGFloat) -> CGPath
    public static func snapped45(from anchor: CGPoint, to point: CGPoint) -> CGPoint
}
public enum StrokeSmoothing {
    public static func thinned(_ points: [CGPoint], minDistance: CGFloat = 1.5) -> [CGPoint]
    public static func path(through points: [CGPoint], tension: CGFloat = 0.5) -> CGPath   // < 2 点 → 单点圆
}
```

#### 3.3.7 Rendering/

```swift
public enum Pixelator {
    /// CPU 实现：缩小到 1/blockSize 再最近邻放大；blockSize ≥ 1；失败返回 nil
    public static func pixelated(_ image: CGImage, blockSize: Int) -> CGImage?
    public static func blockSize(forBrushWidth width: CGFloat, scale: CGFloat) -> Int   // max(6, width × scale / 2)
}

public enum TextLayout {
    public static func font(size: CGFloat) -> CTFont                 // 系统 semibold
    public static func size(of text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize
    public static func draw(_ text: String, at origin: CGPoint, fontSize: CGFloat, maxWidth: CGFloat,
                            color: RGBAColor, in context: CGContext)   // 左上原点、y 向下的 context
}

/// 渲染环境：把全局点映射到目标位图像素
public struct RenderEnvironment: @unchecked Sendable {
    public let origin: CGPoint            // 目标位图左上角对应的全局点
    public let scale: CGFloat             // 点 → 像素
    public let targetPixelSize: CGSize
    /// 马赛克用：整帧像素化副本及其左上角全局点（nil 时马赛克画半透明灰块占位）
    public let pixelatedFrame: CGImage?
    public let frameOrigin: CGPoint
    public init(origin: CGPoint, scale: CGFloat, targetPixelSize: CGSize, pixelatedFrame: CGImage?, frameOrigin: CGPoint)
}

public enum AnnotationRenderer {
    /// context 为 CoreGraphics 默认（左下原点）；内部翻转、缩放、平移后按文档顺序绘制
    public static func draw(_ document: AnnotationDocument, in context: CGContext, environment: RenderEnvironment)
    public static func draw(_ annotation: Annotation, numberLabel: Int?, in context: CGContext, environment: RenderEnvironment)
    /// 选中框（虚线）供覆盖层复用
    public static func drawSelectionOutline(for annotation: Annotation, in context: CGContext, environment: RenderEnvironment)
}
```

#### 3.3.8 Export/ 与 Clipboard/

```swift
public struct ScreenshotExport: @unchecked Sendable {
    public let image: CGImage
    public let png: Data
    public let pixelSize: CGSize
    public let selection: CGRect            // 全局点
    public let screen: CaptureScreen
}
public enum ScreenshotExportError: Error, Equatable, Sendable { case emptySelection, contextUnavailable, encodingFailed }

public enum ScreenshotExporter {
    /// 裁剪 + 标注 → 原生像素 PNG；PNG 写入 DPI = 72 × scale
    public static func export(frame: FrozenFrame, selection: CGRect, document: AnnotationDocument,
                              pixelatedFrame: CGImage?) throws(ScreenshotExportError) -> ScreenshotExport
    /// 仅裁剪（供 OCR）
    public static func crop(frame: FrozenFrame, selection: CGRect) throws(ScreenshotExportError) -> CGImage
    public static func pngData(_ image: CGImage, scale: CGFloat) -> Data?
}

public enum ScreenshotFileNaming {
    /// "Cubby 2026-09-27 01.23.45.png"；固定 24 小时制，不随地区变化
    public static func fileName(date: Date, timeZone: TimeZone = .current) -> String
    /// 存在则追加 " 2"、" 3"…（exists 注入便于测试）
    public static func uniqueURL(in directory: URL, fileName: String, exists: (URL) -> Bool) -> URL
}

public enum ScreenshotSaveLocation {
    /// preferred 非 nil 用之；否则读 systemDefaults["location"]（~ 展开）；否则 home/Desktop
    public static func resolve(preferred: URL?, systemDefaults: UserDefaults?, homeDirectory: URL) -> URL
}

public enum ScreenshotPasteboard {
    /// PNG + TIFF（部分老应用只认 TIFF）+ markerType；PNG 解码失败抛 PasteboardWriteError.imageUnavailable
    public static func write(png: Data, to pasteboard: NSPasteboard) throws
    public static func write(text: String, to pasteboard: NSPasteboard)
}
```

#### 3.3.9 Magnifier/

```swift
public struct PixelGrid: Equatable, Sendable {
    public let radius: Int                 // 8 → 17×17
    public let colors: [RGBAColor?]        // 行优先；nil = 帧外
    public var side: Int
    public var center: RGBAColor?
    public func color(dx: Int, dy: Int) -> RGBAColor?
}
public enum MagnifierSampler {
    /// centerPixel 为帧内像素坐标（左上原点）
    public static func sample(frame: CGImage, centerPixel: CGPoint, radius: Int) -> PixelGrid
}
public enum ColorFormat: Equatable, Sendable { case hex, rgb }
public enum ColorFormatter {
    public static func string(_ color: RGBAColor, format: ColorFormat) -> String   // "#FF8800" / "255, 136, 0"
}
```

#### 3.3.10 Session/ —— 状态机

```swift
public enum ScreenshotPhase: Equatable, Sendable { case hovering, selecting, adjusting, annotating, editingText }

public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public static let shift, option, command, space: KeyModifiers
}

public enum DragState: Equatable, Sendable {
    case none
    case creatingSelection(anchor: CGPoint, previous: CGRect?)   // previous：Esc 时恢复
    case movingSelection(last: CGPoint)
    case resizing(SelectionHandle)
    case drawing(Annotation)
    case movingAnnotation(AnnotationID, last: CGPoint)
}

public struct TextEditingState: Equatable, Sendable {
    public let origin: CGPoint
    public let existing: AnnotationID?       // 重新编辑已有文字
}

public struct ScreenshotSession: Equatable, Sendable {
    public let phase: ScreenshotPhase
    public let screenID: UInt32?             // 选区所在屏
    public let selection: CGRect?
    public let hover: HoverTarget?
    public let cursor: CGPoint
    public let modifiers: KeyModifiers
    public let tool: ScreenshotTool          // pointer = 无工具
    public let styles: ToolStyles
    public let document: AnnotationDocument
    public let selectedAnnotation: AnnotationID?
    public let drag: DragState
    public let textEditing: TextEditingState?
    public let colorFormat: ColorFormat      // ⇧ 按住时 .rgb
    public static func initial(styles: ToolStyles, cursor: CGPoint) -> ScreenshotSession
    public var isMagnifierVisible: Bool      // hovering / selecting / resizing
    public var isToolbarVisible: Bool        // 有选区且 drag == .none
    public var highlightedRect: CGRect?      // 去遮罩区域：选区，或悬停目标
}

public enum ScreenshotOutcome: Equatable, Sendable {
    case copy, save, pin, extractText
    case copyColor(String)
    case cancel
}

public enum ScreenshotEvent: Equatable, Sendable {
    case mouseMoved(CGPoint)
    case mouseDown(CGPoint, clickCount: Int)
    case mouseDragged(CGPoint)
    case mouseUp(CGPoint)
    case rightMouseDown(CGPoint)
    case modifiersChanged(KeyModifiers)
    case command(ScreenshotCommand)
    case styleChanged(AnnotationStyle)             // 样式条点击
    case textCommitted(String?)                    // nil / 空白 = 丢弃
    case toolbarAction(ScreenshotOutcome)          // 工具栏按钮
}

public enum ScreenshotEffect: Equatable, Sendable {
    case finish(ScreenshotOutcome)
    case beginTextEditing(TextEditingState, initialText: String)
    case endTextEditing
    case stylesChanged(ToolStyles)
}

public enum ScreenshotReducer {
    /// 纯函数：所有阶段转换、选区几何、标注增删改、撤销 / 重做都在这里
    public static func reduce(_ session: ScreenshotSession, event: ScreenshotEvent,
                              topology: ScreenTopology) -> (session: ScreenshotSession, effects: [ScreenshotEffect])
}

public enum ScreenshotCommand: Equatable, Sendable {
    case escape, confirm, save, pin, extractText, selectAll, undo, redo, copyColor
    case selectTool(ScreenshotTool)
    case nudge(NudgeDirection, large: Bool)
    case deleteAnnotation
    case commitText
    /// 按阶段解释按键（editingText 只识别 escape / commitText）；字母按字符匹配
    public static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?,
                            phase: ScreenshotPhase) -> ScreenshotCommand?
}

public enum ScreenshotDebugScenario {
    /// "hovering" / "selecting" / "adjusting" / "annotating" / "annotating:<tool>" / "text" / "tiny" / "edge" / "fullscreen"
    /// （"pin" / "permission" 不是会话预置，由 ScreenshotCoordinator 直接处理）
    public static func session(named name: String, topology: ScreenTopology, styles: ToolStyles) -> ScreenshotSession?
}
```

### 3.4 App 层接口契约

#### 3.4.1 B 提供、C 依赖的协议（`ScreenshotOverlayPresenting.swift`，B 第一天就要交付）

```swift
/// 覆盖层的结果：C 产出，B 消费
enum ScreenshotResult {
    case copy(ScreenshotExport)
    case save(ScreenshotExport)
    case pin(ScreenshotExport)
    case extractText(ScreenshotExport, clean: CGImage)   // clean = 无标注裁剪，供 OCR
    case copyColor(String)
    case cancel
    case failed(ScreenshotFailure)
}
enum ScreenshotFailure: Equatable { case exportFailed, noScreen }

@MainActor
protocol ScreenshotOverlayDelegate: AnyObject {
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didFinishWith result: ScreenshotResult)
    func overlay(_ overlay: any ScreenshotOverlayPresenting, didChangeStyles styles: ToolStyles)
}

@MainActor
protocol ScreenshotOverlayPresenting: AnyObject {
    /// capture：帧与拓扑；initial：起始会话（正常为 .initial，调试场景为预置值）
    init(capture: CaptureSession, initial: ScreenshotSession, delegate: any ScreenshotOverlayDelegate)
    func present()
    /// 外部取消（快捷键再按、显示器变化）；必须回调 didFinishWith(.cancel)
    func cancel()
    /// 当前阶段（协调器判断「再按快捷键」是否允许取消）
    var phase: ScreenshotPhase { get }
    var hasAnnotations: Bool { get }
}

/// B 的默认实现，在 C 交付前让协调器可编译、场景可跑：present() 立即回调 .cancel
@MainActor final class NoOverlay: ScreenshotOverlayPresenting { … }
```

#### 3.4.2 B：采集与权限

```swift
@MainActor
enum ScreenRecordingAuthorization {
    enum Status: String { case granted, denied }
    static var status: Status                         // CGPreflightScreenCaptureAccess()
    /// 首次调用触发系统弹窗；返回是否已授权
    @discardableResult static func request() -> Bool  // CGRequestScreenCaptureAccess()
    static func openSettings()                        // Privacy_ScreenCapture
}

/// NSScreen → CaptureScreen，以及 AppKit ↔ 全局点换算（App 层唯一换算点）
@MainActor
enum ScreenTopologyProvider {
    static func screens() -> [CaptureScreen]          // CGDirectDisplayID 取自 NSScreen.deviceDescription["NSScreenNumber"]
    static func toGlobal(_ appKitPoint: CGPoint) -> CGPoint
    static func toGlobal(_ appKitRect: CGRect) -> CGRect
    static func toAppKit(_ globalPoint: CGPoint) -> CGPoint
    static func toAppKit(_ globalRect: CGRect) -> CGRect
    static func nsScreen(for screen: CaptureScreen) -> NSScreen?
}

/// 帧来源：真实采集或调试夹具
protocol FrameSource: Sendable {
    /// 采集所有屏幕；excludingPID 的窗口不出现在帧里（贴图窗口除外，用 exceptWindowIDs 传入）
    func capture(excludingPID: pid_t, exceptWindowIDs: Set<UInt32>, timeout: Duration) async throws -> CaptureSession
}
enum FrameCaptureError: Error { case notAuthorized, timedOut, noDisplays, underlying(Error) }

/// ScreenCaptureKit 实现：SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
/// → 每个 SCDisplay 一个 SCContentFilter(display:excludingApplications:[cubby] exceptingWindows:[pins])
/// → SCScreenshotManager.captureImage，各屏并行；SCStreamConfiguration：width/height = 像素尺寸、
///   captureResolution = .best、showsCursor = false、colorSpaceName = kCGColorSpaceSRGB、
///   pixelFormat = BGRA；窗口列表由同一份 SCShareableContent.windows 转成 WindowCandidate（frame 已是全局点）
struct FrozenFrameCapturer: FrameSource { … }

#if DEBUG
/// 合成一张「桌面」：渐变背景 + 3 个色块「窗口」（带标题栏与文字）+ 网格标尺；
/// 窗口列表与色块一致，因此悬停识别可用；不需要任何权限
struct FixtureFrameSource: FrameSource { init(screens: [CaptureScreen]) }
#endif
```

#### 3.4.3 B：协调器与输出

```swift
enum ScreenshotTrigger { case hotKey, menu, panelButton, debugScenario(String) }

@MainActor
final class ScreenshotCoordinator {
    typealias OverlayFactory = @MainActor (CaptureSession, ScreenshotSession, any ScreenshotOverlayDelegate)
        -> any ScreenshotOverlayPresenting

    init(settings: AppSettings, store: ClipStore, frameSource: any FrameSource,
         overlayFactory: @escaping OverlayFactory, pins: PinnedImageController,
         beforeCapture: @escaping @MainActor () -> Void)      // 隐藏面板等
    var isActive: Bool
    /// 入口：权限检查 → beforeCapture → 采集（2 s 超时）→ 覆盖层
    func start(_ trigger: ScreenshotTrigger)
    /// 快捷键再按：按 §2.1 规则决定取消或忽略
    func hotKeyPressedWhileActive()
    /// 显示器变化：取消
    func screenParametersDidChange()
}
// 实现 ScreenshotOverlayDelegate：结果交给 ScreenshotOutputService；styles 写回 settings.annotationStyles

@MainActor
struct ScreenshotOutputService {
    init(settings: AppSettings, store: ClipStore, recognizer: TextRecognizer, pins: PinnedImageController)
    func copy(_ export: ScreenshotExport)                    // 剪贴板 + 历史 + HUD
    func save(_ export: ScreenshotExport)                    // 文件 + 历史 + HUD
    func pin(_ export: ScreenshotExport)                     // 贴图 + 历史
    func extractText(from image: CGImage, anchor: CGPoint)   // 异步 OCR → 剪贴板 + 历史 + HUD
    func copyColor(_ text: String, anchor: CGPoint)
    static var screenshotSource: SourceApp                   // bundleID = 自身，name = "Screenshot"
}

enum ScreenshotFileSaver {
    /// 目录不可写时回退桌面；设置 kMDItemIsScreenCapture xattr；返回实际写入 URL
    static func save(_ png: Data, to directory: URL, date: Date) throws -> URL
}

struct TextRecognizer: Sendable {
    /// VNRecognizeTextRequest .accurate, ["zh-Hans", "en-US"]；按阅读顺序换行；空 → ""
    func recognize(_ image: CGImage) async throws -> String
}

@MainActor
final class PinnedImageController {
    func pin(_ export: ScreenshotExport)                     // 原位 1:1
    func pin(image: CGImage, pixelSize: CGSize, scale: CGFloat, at appKitCenter: CGPoint)   // 阶段 2：从历史贴图
    var windowIDs: Set<UInt32>                               // 采集时保留
    func closeAll()
}
final class PinnedImageWindow: NSPanel { … }                 // §2.9
```

#### 3.4.4 B：基础设施改动

```swift
// HotKeyManager：单热键 → 多热键。EventHotKeyID.id 区分动作；回调里用
// GetEventParameter(kEventParamDirectObject, typeEventHotKeyID) 取出 id
enum HotKeyAction: UInt32 { case togglePanel = 1, screenshot = 2 }
@MainActor final class HotKeyManager {
    @discardableResult func register(_ hotKey: HotKey, for action: HotKeyAction, handler: @escaping () -> Void) -> Bool
    func unregister(_ action: HotKeyAction)
    func suspend()      // 全部暂停（录制期间）
    @discardableResult func resume() -> Bool
}

// HotKey.swift
public extension HotKey { static let screenshotDefault: HotKey /* ⇧⌘2 */ }

// AppSettings.swift（settingsVersion 保持 1：新增键都是可选 / 有默认值，无需迁移）
public var screenshotHotKey: HotKey?          // Keys.screenshotHotKey（Data）+ Keys.screenshotHotKeyDisabled（Bool）
public var screenshotSaveDirectory: URL?      // Keys.screenshotSaveDirectory（path String）
public var annotationStyles: ToolStyles       // Keys.annotationStyles（Data，ToolStyles.decode 容错）

// PanelCommand.swift
case takeScreenshot                            // 面板内 ⇧⌘2 不会到这里（Carbon 热键先吃掉）；预留给相机按钮与菜单
```

`AppDelegate` 新增：`screenshots = ScreenshotCoordinator(...)`；`registerHotKeys()` 注册两个动作；`observeSettings` 增加 `screenshotHotKey`；`applyDebugScenario` 增加 `screenshot:*` 分支（`FixtureFrameSource` + `ScreenshotDebugScenario.session(named:)`）；订阅 `NSApplication.didChangeScreenParametersNotification`。

`PanelChrome.makeContainer(for:cornerRadius:)`：现有调用不变（默认 `Radius.panel`），C 传 `Radius.card`。

#### 3.4.5 C：覆盖层内部约定

- `ScreenshotOverlayController` 实现 `ScreenshotOverlayPresenting`；持有唯一的 `ScreenshotSession`，每个 `NSEvent` 翻译成 `ScreenshotEvent` 交给 `ScreenshotReducer.reduce`，用返回的新 session 驱动所有视图（单向数据流）；effects 中 `.finish` 时调用 `ScreenshotExporter` 生成 `ScreenshotExport` 再回调委托。
- 每个 `CaptureScreen` 一个 `OverlayWindow`（`NSPanel`，`[.borderless, .nonactivatingPanel]`，`level = .statusBar`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，`canBecomeKey = true`，`acceptsMouseMovedEvents = true`，`hasShadow = false`，`isOpaque = true`，`backgroundColor = .black`）；`present()` 对所有窗口 `orderFrontRegardless()`，光标所在屏的窗口 `makeKey()`；鼠标进入另一屏的窗口时把 key 移过去。
- `resignKey` 不关闭覆盖层（§2.12）。
- `OverlayCanvasView` 分层：`frameLayer`（`contents = CGImage`，`contentsScale = scale`）→ `dimLayer`（`CAShapeLayer`，evenOdd：屏幕 − highlightedRect）→ `annotationLayer`（`draw(in:)` 调 `AnnotationRenderer`，只在文档变化时 `setNeedsDisplay`）→ `liveLayer`（拖拽中的几何）→ `chromeLayer`（选区描边、手柄、悬停描边）；工具栏、样式条、尺寸标签、放大镜、文本编辑器是 `NSView` 子视图，位置来自 Core 摆放算法（全局点 → 窗口坐标：`local = global − screen.frame.origin`，再翻转 y）。
- 像素化副本：第一次选马赛克工具时在 `Task.detached` 里对当前屏幕的帧调用 `Pixelator.pixelated`，完成前马赛克画半透明灰块占位（`RenderEnvironment.pixelatedFrame == nil`）。
- 键盘：`OverlayKeyboard` = `NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])`，只处理 `event.window` 是覆盖层窗口的事件；`editingText` 阶段且 `hasMarkedText()` 时一律放行。

### 3.5 一次「完成」的数据流

```
⇧⌘2 ─▶ AppDelegate ─▶ coordinator.start(.hotKey)
   ├─ ScreenRecordingAuthorization.status == denied ─▶ 引导窗口，结束
   ├─ beforeCapture()：panel.hide(animated: false)
   ├─ await frameSource.capture(excludingPID: own, exceptWindowIDs: pins.windowIDs, timeout: 2s)
   │      ScreenCaptureKit ─▶ CaptureSession { topology, frames }
   ├─ overlay = overlayFactory(capture, .initial(styles: settings.annotationStyles, cursor: 当前光标全局点), self)
   └─ overlay.present()
          用户操作 ─▶ NSEvent ─▶ ScreenshotEvent ─▶ ScreenshotReducer ─▶ session' ─▶ 视图更新
          ↩ ─▶ .command(.confirm) ─▶ effect .finish(.copy)
          ─▶ ScreenshotExporter.export(frame, selection, document, pixelated) ─▶ ScreenshotExport
          ─▶ delegate.overlay(_, didFinishWith: .copy(export))
coordinator ─▶ overlay 窗口 orderOut ─▶ ScreenshotOutputService.copy(export)
   ├─ ScreenshotPasteboard.write(png:)   （PNG + TIFF + marker）
   ├─ settings.isPaused ? skip : store.record(.image(png:width:height:), source: .screenshot)
   └─ HUDToast.show("Copied to clipboard", at: toAppKit(selection.center))
```

## 4. 并行分工

### 4.1 三条线与依赖

```
第 0 天   B：协议文件 + PanelChrome 参数 + HotKey.screenshotDefault + AppSettings 新键（先于一切）
          A：Core 全部（可独立开工，只依赖已有的 RGBAColor / HexColor / PasteboardReader.markerType）
第 1–4 天 A ∥ B（B 继续：热键、权限、采集、输出、贴图、设置、诊断、协调器、夹具帧、场景分支）
第 5 天起 C 开工（条件见 4.3）；B 转入联调与文案
最后     翻译环节统一补 zh-Hans；B 做集成提交（overlayFactory 换成 C 的控制器，≤ 5 行）
```

A 与 B 完全并行；C 依赖 A 的全部 Core 类型和 B 的协议文件。为了让 C 尽早开工，A 按下面顺序交付并逐个合入：① Capture + Selection + Layout（第 1 天）② Annotation 模型 + Document（第 2 天）③ Session reducer + Command（第 3 天）④ Renderer + Export + Magnifier + Pixelator（第 4 天）。C 可以在 ③ 合入后开始窗口、事件与选区部分，④ 合入后再做标注渲染与导出。

### 4.2 文件所有权（互不重叠）

| 实现者 | 新建 | 修改既有 | 禁止 |
| --- | --- | --- | --- |
| **A** Core 逻辑与测试 | `Sources/CubbyCore/Screenshot/**`、`Tests/CubbyCoreTests/Screenshot/**` | 无 | 任何 `Sources/Cubby/**`、`AppSettings.swift`、`HotKey.swift` |
| **B** 基础设施与输出 | `Sources/Cubby/Screenshot/ScreenshotCoordinator.swift`、`ScreenshotOverlayPresenting.swift`、`Capture/**`、`Output/**`、`Tests/CubbyCoreTests/AppSettingsScreenshotTests.swift`、`HotKeyScreenshotDefaultTests.swift` | §3.1 列出的既有文件、`PRIVACY.md`、`CONTRIBUTING.md`、`CHANGELOG.md` | `Sources/CubbyCore/Screenshot/**`、`Sources/Cubby/Screenshot/Overlay/**` |
| **C** 覆盖层 UI | `Sources/Cubby/Screenshot/Overlay/**` | 无 | 其余一切；需要 B 的改动时提 issue 给 B |

共享文件规则：

- `Resources/Localizable.xcstrings`：三人都**不改**。源码只写英文 key（`String(localized:comment:)` / SwiftUI 字面量，comment 说明出现位置）；最后由翻译环节运行 `make strings` 提取并补 zh-Hans，`make check-strings` 通过后合并。附录 A 预列了全部 key，避免三人各起一套措辞。
- `AppDelegate.swift`：只有 B 改。C 需要的入口（调试场景）通过 B 的 `ScreenshotCoordinator.start(.debugScenario(name))` 暴露。
- `docs/SCREENSHOT-DESIGN.md`：契约变更需三方同意后由提出者改，并在 PR 里链接。
- 正在进行的国际化改造会触碰 `Sources/` 里的 `String(localized:)`，B 修改既有文件前先同步主干，只做最小 diff。

### 4.3 C 开工时需要的产物

来自 A（已合入主干、`make test` 绿）：`CaptureScreen`、`FrozenFrame`、`ScreenTopology`、`CaptureSession`、`SelectionGeometry`、`SelectionHandle`、三个 Placement、`WindowHitTester`、`Annotation*`、`AnnotationDocument`、`ScreenshotTool`、`ToolStyles`、`ScreenshotSession`、`ScreenshotEvent`、`ScreenshotReducer`、`ScreenshotCommand`、`AnnotationRenderer`、`ScreenshotExporter`、`MagnifierSampler`、`Pixelator`、`ScreenshotDebugScenario`。

来自 B：`ScreenshotOverlayPresenting.swift`（协议、委托、结果类型、`NoOverlay`）、`PanelChrome.makeContainer(for:cornerRadius:)`、`ScreenTopologyProvider`、`FixtureFrameSource` 与 `--scenario screenshot:*` 分支（C 用它验证自己的 UI）。

### 4.4 构建隔离

三人在同一台机器或 CI 上并行构建时各用独立的 scratch 目录，避免 `.build` 锁冲突与产物互相覆盖：

```sh
swift build --scratch-path .build-a   &&  swift test --scratch-path .build-a     # A
swift build --scratch-path .build-b   &&  swift test --scratch-path .build-b     # B
swift build --scratch-path .build-c                                              # C
CUBBY_DATA_DIR=/tmp/cubby-c .build-c/debug/Cubby --scenario screenshot:annotating --light
```

`.gitignore` 已含 `.build`；三个变体目录由 B 在第 0 天追加为 `.build-*`。`make coverage` 只在合并前由 A 用默认目录跑一次。

### 4.5 完成定义（每个实现者）

- A：`make test` 绿、`make coverage` ≥ 95%（Core 整体）、`make lint`、`make check-cjk` 通过；每个 public 类型有 `///` 注释（中文）；无 `@unchecked Sendable` 缺注释。
- B：以上 + `make run` 后真实设备走 §7.1 M1/M3 验收；`--scenario screenshot:hovering` 在无权限账户可运行；`PRIVACY.md` 补屏幕录制段落。
- C：`make lint` / `check-cjk` 通过；§5.2 全部场景在深 / 浅色、macOS 14 与 26 上截图并附在 PR；QA 清单 §7.1 M2 全过。

## 5. 测试计划

### 5.1 Core（Swift Testing，`Tests/CubbyCoreTests/Screenshot/`）

沿用现有风格：`@Suite("中文说明")`、`@Test("中文说明", arguments:)` 参数化、固定时间与坐标、不碰真实偏好与文件（`withIsolatedDefaults`、`TempDirectory`、`withTemporaryPasteboard`）。新增夹具 `Tests/CubbyCoreTests/Screenshot/Support/ScreenshotFixtures.swift`：

- `ScreenshotFixtures.topology(twoScreens:)`：主屏 1440×900 @2x 于 (0,0)，外接 1920×1080 @1x 于 (1440, −180)；3 个窗口（含一个跨屏、一个 layer 25 的菜单栏、一个属于 ownPID 的）。
- `ScreenshotFixtures.frame(width:height:scale:pattern:)`：程序生成 CGImage（纯色、棋盘、渐变），供渲染与采样测试。
- `BitmapProbe`：把 CGImage 读进 `[UInt8]`，提供 `color(x:y:) -> RGBAColor` 与 `assertColor(x:y:expected:tolerance:)`。

| 类型 | 必测用例（每条一个 `@Test`） |
| --- | --- |
| `CaptureScreen` | 点 → 局部 / 像素换算（1x、2x、负坐标屏）；`pixelRect` 取整且不超帧；`contains` 边界（右 / 下边缘不含）。 |
| `ScreenTopology` | `screen(containing:)` 在空隙返回 nil；重叠时取第一个。 |
| `SelectionGeometry.normalized` | 四个象限归一化；⇧ 正方形四象限；⌥ 中心扩展；⇧+⌥；夹紧到 bounds 后仍是正方形（取较小边）。 |
| `SelectionGeometry.resizing` | 8 个手柄各一例（参数化）；越过对边时不翻转而是停在 minSize；⇧ 时角手柄等比；bounds 夹紧。 |
| `moved` / `nudged` / `clamped` | 出界夹紧；比屏幕大的矩形夹到左上；四方向 1 / 10。 |
| `hitRegion` | 手柄优先于边带；边带优先于内部；容差边界值；小选区 `visibleHandles` 三档。 |
| `ToolbarPlacement` | below / above / inside 三档；右对齐；左溢出右推；样式条同侧且更远；选区 = 整屏 → inside 右下。 |
| `MagnifierPlacement` | 四角翻转；屏幕比放大镜还小时夹紧。 |
| `SizeLabelPlacement` | 三档；`text` 在 2x 屏为像素值、四舍五入。 |
| `WindowHitTester` | z 序取最前；过滤 layer ≠ 0、alpha 0、1×1、ownPID；跨屏窗口 `selectionRect` = 交集；无窗口 → `.screen`。 |
| `AnnotationColor` / `ToolStyles` | 8 色 hex 往返；`decode(nil)` = default；未知键忽略；每个工具默认样式；编码可回读。 |
| `Annotation` | `bounds` 含线宽外扩（每种 shape）；`hitTest`：线条按距离、矩形按描边环（内部空白不命中）、填充类按区域、文字按排版框；`translated` 全部 shape。 |
| `AnnotationDocument` | 增删改各入一步；undo / redo 往返；新操作清空 redo；100 步上限丢最早；`numberLabel` 删除中间后补位；`topmost` 取最后画的。 |
| `ArrowGeometry` | 路径 boundingBox 包含两端；头部三角包含 `to`；长度 < 头长时仍有路径；`snapped45` 8 个方向。 |
| `StrokeSmoothing` | 抽稀阈值；0 / 1 / 2 点退化；曲线经过（近似）所有控制点。 |
| `Pixelator` | 棋盘图按 blockSize 取块平均；blockSize 1 = 原图；不整除边缘；`blockSize(forBrushWidth:)` 下限 6。 |
| `TextLayout` | `size(of:)` 随 maxWidth 换行变高；空串为零；中英混排不崩。 |
| `AnnotationRenderer`（像素级） | 方法：建 RGBA 8 位 `CGContext`（已知尺寸、白底），调用 `draw`，用 `BitmapProbe` 断言。用例：矩形四边中点像素 = 颜色、内部仍白；椭圆中心白、边缘有色；箭头头部像素有色；画笔起点有色；荧光笔叠加后底色变暗但非纯色（multiply）；马赛克区域像素等于像素化副本对应像素、区域外等于原图；文字框内出现非白像素；序号中心非白、边缘外白；`scale = 2` 时线宽像素翻倍（沿法线数有色像素）；`origin` 平移后同一标注落点偏移正确。 |
| `ScreenshotExporter` | 裁剪像素尺寸 = 选区 × scale；越界选区被截；空选区抛错；PNG 可被 `NSBitmapImageRep` 解回且尺寸一致；DPI 元数据 = 144 @2x；带标注导出与 `crop` 的差异只在标注像素。 |
| `ScreenshotFileNaming` | 固定日期 → 精确文件名；时区注入；`uniqueURL` 冲突 1 次 / 3 次。 |
| `ScreenshotSaveLocation` | preferred 优先；系统 defaults 有 `location`（含 `~`）；两者皆无 → Desktop。 |
| `ScreenshotPasteboard` | PNG + TIFF + marker 都在；`shouldIgnore` 为真；`PasteboardReader.read` 读回 `.image` 且尺寸正确；坏 PNG 抛错；文本写入带 marker。 |
| `MagnifierSampler` / `ColorFormatter` | 帧内 / 边缘（nil 填充）/ 帧外中心；`center` 正确；hex 大写、rgb 格式。 |
| `ScreenshotCommand.from` | 每个阶段 × 每个按键的真值表（参数化，含 editingText 只认两个键、Dvorak 字符匹配、⇧⌘Z 是 redo）。 |
| `ScreenshotReducer` | 每条 §2.3 表格一行至少一个用例：hovering 单击窗口 / 屏幕 / 跨屏；拖拽阈值；selecting 松开成 adjusting；Esc 恢复 previous；⇧ / ⌥ / 空格；adjusting 拖手柄 / 移动 / 选区外新建保留标注；双击 → `.finish(.copy)`；工具切换与再按取消；文字单击 → `.beginTextEditing`；`textCommitted(nil)` 丢弃；序号单击直接入栈；样式条改选中标注并产生 `.stylesChanged`；方向键作用对象切换；右键清选区保留文档；`copyColor` 只在放大镜可见时；显示器 / 屏幕 id 一致性；`isMagnifierVisible` / `isToolbarVisible` / `highlightedRect` 派生值。 |
| `ScreenshotDebugScenario` | 每个名字返回非 nil 且 `phase` 符合；未知名 nil。 |

覆盖率：Core 整体 ≥ 95%（`make coverage`），新目录单独看也应 ≥ 95%（`COVERAGE_TARGET=Sources/CubbyCore/Screenshot ./scripts/check-coverage.sh --skip-tests`）。

### 5.2 App 层（DEBUG `--scenario`）

无 UI 测试框架（ROADMAP 决策），靠可复现的截图场景 + `docs/QA-CHECKLIST.md` 新增章节人工走查。`AppDelegate.applyDebugScenario` 新增前缀 `screenshot:`，由 `ScreenshotCoordinator.start(.debugScenario(name))` 处理：用 `FixtureFrameSource`（合成桌面，**不需要屏幕录制权限，不会截到真实屏幕**）在主屏生成 `CaptureSession`，用 `ScreenshotDebugScenario.session(named:)` 取预置会话，交给覆盖层。

| 场景 | 预置状态 | 走查点 |
| --- | --- | --- |
| `screenshot:hovering` | 光标在假窗口 B 上 | 遮罩 40%、窗口去遮罩 + 描边、放大镜位置与读数、十字光标 |
| `screenshot:selecting` | 拖拽进行中 (200,150)→(760,520) | 尺寸标签、放大镜、无手柄、无工具栏 |
| `screenshot:adjusting` | 选区 (200,150,560,370) | 8 手柄、工具栏在下方右对齐、标签在左上外侧 |
| `screenshot:annotating` | 同上 + 每种工具各一个标注 + 选中箭头 | 8 种标注渲染、选中虚线框、样式条显示箭头样式、序号 1–3 |
| `screenshot:annotating:<tool>` | 同上，激活指定工具 | 样式条按工具切换（马赛克无颜色、文字为字号） |
| `screenshot:text` | 文本框编辑中，预填 "Hello 你好" | 虚线框、字体、光标；手动测输入法 |
| `screenshot:tiny` | 选区 12×10 | 无手柄、标签与工具栏在外侧 |
| `screenshot:edge` | 选区贴屏幕右下角 | 工具栏翻到上方、放大镜翻转、标签翻转 |
| `screenshot:fullscreen` | 选区 = 整屏 | 工具栏 inside、标签 inside |
| `screenshot:pin` | 直接生成一张贴图于屏幕中央 | 阴影圆角、拖动、缩放、右键菜单、Esc |
| `screenshot:permission` | 显示权限引导窗口 | 文案、按钮、深浅色 |

截图命令（与现有流程一致）：`CUBBY_DATA_DIR=/tmp/cubby-demo .build-c/debug/Cubby --scenario screenshot:annotating --light`，然后 `screencapture -x -l <windowID>` 或整屏截图。每个场景出深 / 浅色 × macOS 14 / 26 四张，附在 PR。

真机（`make run`，需要权限）的人工用例写入 `QA-CHECKLIST.md` 新章节「Screenshots · 截图」（B 负责补，见 §7.1 验收标准）。

## 6. 风险与对策

| # | 风险 | 影响 | 对策 |
| --- | --- | --- | --- |
| R1 | **屏幕录制权限**：`CGRequestScreenCaptureAccess` 只在第一次弹窗；授权后 macOS 常要求重启应用；ad-hoc 签名的开发版每次构建签名不同，授权失效（与辅助功能同病） | 首次体验断裂；开发期反复授权 | 引导窗口明说「可能需要退出重开」；1.5 s 轮询状态；开发者按 CONTRIBUTING 用固定证书 `SIGN_IDENTITY="Cubby Local"`；裸可执行文件的权限会算到终端头上，权限相关测试一律 `make run` |
| R2 | **macOS 15+ 周期性确认**：系统会定期（15.0 每周、15.1 起每月）弹「Cubby 请求绕过系统窗口选择器…」，弹窗期间采集调用挂起或失败 | 用户按快捷键后「没反应」 | 采集 2 s 超时 → 取消并橙色 HUD「Couldn't capture the screen. Check the permission prompt.」；覆盖层永远在帧到达后才显示，不会留下黑屏；诊断信息含权限状态 |
| R3 | **采集延迟**：`SCShareableContent` + 每屏 `captureImage` 在多屏 / 5K 上可能 150–300 ms | 达不到 150 ms 目标 | 各屏并行、`onScreenWindowsOnly: true`、sRGB/BGRA 直出；用 `OSSignposter` 打点，M1 单屏必须 ≤ 150 ms；仍超标时阶段 2 评估 macOS 14 上用 `CGDisplayCreateImage`（已弃用但可用）做快路径 |
| R4 | **覆盖层层级与 key**：层级过高压住输入法候选框、tooltip、右键菜单；非激活面板成为 key 的行为在全屏 Space 上可能异常 | 中文输入不可用；快捷键失灵 | 层级定为 `.statusBar`（§2.10 理由）；`orderFrontRegardless` + `makeKey`；resignKey 不关闭；QA 清单含「全屏 Safari 上截图并输入中文」 |
| R5 | **坐标系混用**：AppKit 左下 / CG 左上 / 点 / 像素 / 多屏负坐标 | 选区偏移、导出错位、放大镜取错像素 | §3.2 单一约定；App 层只在 `ScreenTopologyProvider` 换算；Core 测试覆盖负坐标外接屏；`screenshot:edge` 场景在双屏走查 |
| R6 | **内存与性能**：6K 帧 81 MB/屏，像素化副本再翻倍；放大镜每次移动采样；标注层全量重绘 | 卡顿、内存峰值数百 MB | 帧只保留 CGImage（IOSurface 背书，不复制）；像素化惰性 + 按 blockSize 缓存 + 后台线程；放大镜用 `CGImage.cropping` 取 17×17 再绘制；标注层只在文档变化时重绘，拖拽走 `liveLayer`；会话结束即释放全部位图 |
| R7 | **中文输入法**：候选窗层级、组字中的 Esc / ↩、`NSTextView` 在非激活应用中的行为 | 文字工具不可用 | R4 层级；`hasMarkedText()` 放行；`screenshot:text` 场景专门测拼音；PanelController 已验证非激活面板可组字 |
| R8 | **CoreText 与 NSTextView 排版不一致** | 提交后文字位置 / 换行跳动 | 两者同字体、同 `maxWidth`、同内边距；`TextLayout.size(of:)` 与编辑器 `fittingSize` 在测试图上对比，差异 ≤ 1 pt 才合入 |
| R9 | **安全键盘输入**：终端 / 密码框开启 `EnableSecureEventInput` 时，第三方热键行为不一 | 快捷键失效 | 实现后实测 Carbon 热键；失效则 HUD 引导用菜单栏；诊断信息加 `Secure input`；不用事件 tap / 全局监听 |
| R10 | **权限相互独立**：用户以为给了辅助功能就能截图；或以为截图权限能让粘贴工作 | 困惑、误报 issue | 隐私页三行分别说明用途；截图失败的 HUD 明确写 Screen Recording；诊断信息三项分列 |
| R11 | **Swift 6 并发**：`CGImage`、`SCShareableContent` 回调非隔离；`@unchecked Sendable` 滥用 | 编译失败或数据竞争 | 只有 `FrozenFrame` / `CaptureSession` / `ScreenshotExport` / `RenderEnvironment` 允许 `@unchecked`（都只含不可变引用）；`FrameSource` 用 `async throws`，内部 `withCheckedThrowingContinuation` 包 SCK |
| R12 | **API 可用性**：`NSCursor.frameResize` 15+；Vision Swift 化 API 15+；`NSGlassEffectView` 26+ | macOS 14 编译 / 运行差异 | 全部 `#available` 分支 + 回退（§2.5、§2.6、§2.8）；CI 用 macOS 26 SDK 构建、QA 在 macOS 14 跑清单 |
| R13 | **历史体积**：全屏 PNG 10–40 MB，多次截图迅速占满 `historyLimit` 与磁盘 | 用户抱怨 | 超 `maxImageBytes` 不入历史并提示；ROADMAP 自动清理（v0.3）覆盖；阶段 2 评估截图缩略 / 上限设置 |
| R14 | **贴图被再次截取 / 排除逻辑错** | 帧里出现 Cubby 面板残影 | `excludingApplications:[self] exceptingWindows: pins`；面板先隐藏再采集，采集前 `await Task.yield()` 等窗口服务器生效；`screenshot:*` 场景断言帧中无面板（人工） |
| R15 | **三人并行的契约漂移** | 集成时对不上 | §3.3 / §3.4 签名冻结；变更走文档 PR；A 的 public API 先合入再由 C 使用 |

## 7. 分阶段交付

### 7.1 阶段 1：可装给用户试用的完整截图 + 标注（一个版本，三个里程碑）

**M1 · 截得到**（A ①③④ + B 采集 / 热键 / 权限 / 复制 / 设置 + C 窗口 / 选区 / 放大镜）

验收：
- [ ] 任意应用中按 `⇧⌘2`，M1 Mac 单屏 150 ms 内画面冻结（signpost 日志 P50 ≤ 150 ms，P95 ≤ 300 ms）；面板打开时先消失。
- [ ] 悬停窗口高亮，单击选中；桌面单击选整屏；拖拽创建，⇧ / ⌥ / 空格 三个修饰手势可用。
- [ ] 8 手柄、边带、选区内拖动、方向键 1 / 10 pt；尺寸标签像素值正确（2x 屏为 2 倍）。
- [ ] 放大镜 15×15、读数 HEX / RGB（⇧，CSS `rgb()`）、`C` 复制后历史出现颜色卡并 HUD。
- [ ] `↩` / 双击 / ⌘C 完成：前台应用不变，立即 ⌘V 能贴出原生像素 PNG；历史出现来源「Screenshot」的图片卡；暂停记录时不入历史。
- [ ] 双屏（一屏 2x 一屏 1x，外接屏在左上负坐标）：两屏都冻结，选区不跨屏，导出尺寸与像素正确。
- [ ] 全屏 Safari 之上可截图；Esc / 右键 / 再按快捷键行为符合 §2.1 / §2.3。
- [ ] 无权限：只出现 Cubby 引导窗 + 系统弹窗，授权后引导窗自动关闭；隐私页显示状态；诊断信息三行齐全。
- [ ] 显示器插拔时会话取消并 HUD。
- [ ] 设置：快捷键可改、可关闭、与面板快捷键冲突被拒；`make test`、`make coverage`、`make lint`、`make check-cjk` 绿。

**M2 · 画得好**（A ② + C 工具栏 / 样式条 / 8 工具 / 文本编辑 / 撤销）

验收：
- [ ] 工具栏三档位置正确，玻璃（26）/ 材质（14）无直角投影；tooltip 显示快捷键。
- [ ] 8 种工具按 §2.7 渲染：锥形箭头、平滑画笔、multiply 荧光笔、马赛克只糊冻结帧、文字支持拼音输入与换行、序号自动补位。
- [ ] 每工具样式独立记忆，重启后仍在；选中标注可拖、删、改色、方向键微移。
- [ ] 撤销 / 重做 100 步；右键清选区后标注仍在，重新框选后对齐。
- [ ] 标注画到选区外：显示不裁、导出裁掉；调整选区后导出正确。
- [ ] `--scenario screenshot:*` 全部场景四张截图附 PR。

**M3 · 出得去**（B 保存 / 贴图 / OCR / 文案 / 文档）

验收：
- [ ] `⌘S` 保存到系统截图目录（改过 `defaults write com.apple.screencapture location` 也跟随）或自定义目录；文件名格式正确、重名不覆盖；访达按「截图」归类；目录不可写回退桌面并提示。
- [ ] `⌘P` 贴图原位 1:1，拖动 / 滚轮与捏合缩放 / 不透明度 / 右键菜单 / ⌘C / 双击与 Esc 关闭；再次截图时贴图出现在帧里而面板不出现。
- [ ] `⌘T` 对中英混排截图 1 秒内（M1、1080p 区域）出结果并入历史；无文字时橙色 HUD。
- [ ] 所有新字符串有 zh-Hans，`make check-strings` 绿；`PRIVACY.md`、`CONTRIBUTING.md` 场景表、`CHANGELOG.md` 已更新；`QA-CHECKLIST.md` 新增「Screenshots」章节并在 macOS 14 与 26 各跑一遍。

### 7.2 阶段 2：更远的想法（逐项评估）

| 想法 | 评估 | 建议 | 复杂度 |
| --- | --- | --- | --- |
| OCR 文本索引搜索 | **已提前到 v0.2 实现**：`ClipItem.recognizedText: String?`（可选字段，缺失解码为 nil，nil 不编码，**schema 不升级**——升 v2 会让旧版把文件判为「更新版本」而只读，为派生数据不值得）；`ImageTextIndexer`（Core，并发 1、utility 队列，新图即时识别，启动 10 s 后间隔 2 s 回填，> 4K 面积先缩放，每 8 条或空闲时合并写盘，暂停记录时不识别）；`SecretDetector` 过滤；预折叠搜索索引纳入 recognizedText，排序低于正文命中；设置 › 历史「搜索图片中的文字」默认开，关闭即清除全部识别结果。面板卡片「含文字」角标暂未做 | 已完成（v0.2） | M |
| 辅助功能元素级识别 | `AXUIElementCreateSystemWide()` + `AXUIElementCopyElementAtPosition` 取元素 `kAXPosition/Size`（已是 CG 全局坐标）；需要辅助功能权限（Cubby 多数用户已授）；风险：无响应应用可阻塞 → `AXUIElementSetMessagingTimeout(0.1)` 并在后台线程查询；Electron / 网页元素粒度不稳 | **做**，按住 `⌥` 悬停切换到元素模式（不改默认行为）；未授权时 ⌥ 无效果并在 tooltip 说明 | S–M |
| 从历史贴图 | `PinnedImageController.pin(image:…)` 已预留；预览面板与卡片右键加「Pin to Screen」（⌘⇧P），位置 = 屏幕中央 | **做**，工作量小、价值高 | S |
| 记住上次选区 | 会话内存变量（按屏幕 id + 拓扑签名），`hovering` 阶段 `⌘Z` 恢复并显示虚线幽灵框；应用重启不保留 | **做**，键位已在 §2.11 预留 | S |
| 长截图（滚动拼接） | 需要合成滚动事件（辅助功能权限）+ 图像拼接（特征匹配、处理固定页眉 / 懒加载 / 弹性回弹），Electron 与 WKWebView 行为各异；失败模式多、维护成本高 | **暂不做**；先观察需求量；若做，作为独立「Capture Window Content」工具并限制在可 AX 滚动的 `NSScrollView` | L |
| 其他候选 | `⌘1/2/3` 切档、`⌘`+数字选色；标注旋转 / 缩放；贴图悬停关闭点；截图完成音（可选）；图片标注（再编辑历史里的图片） | 视反馈 | S–M |

### 7.3 阶段 3（视反馈）

标注再编辑（历史图片右键「Annotate」复用覆盖层）、URL Scheme `cubby://screenshot`、AppIntents「Take Screenshot」。

## 8. 需要 PM 拍板的开放问题

| # | 问题 | 文档当前取值 | 备选 |
| --- | --- | --- | --- |
| Q1 | Esc 在有标注时是否直接退出（丢弃标注）？ | 直接退出，不确认（快、可预期；右键提供「退一步」） | 有标注时先 HUD「Press Esc again to discard」再退出 |
| Q2 | 会话中再按快捷键 | 无标注时取消，有标注时忽略 | 一律忽略 / 一律取消 |
| Q3 | ⇧ 拖拽的语义 | 正方形（PM 草案） | 与 macOS `⇧⌘4` 一致：锁定单轴（正方形改为 ⇧⌥？） |
| Q4 | 覆盖层层级 `.statusBar`(25) 是否可接受其他应用的弹出窗（101）盖在上面？ | 接受（换取输入法候选、tooltip、菜单可用） | 用 `.popUpMenu` 并在编辑文字时临时降级（更复杂） |
| Q5 | 放大镜按 `C` 复制的是当前显示格式（RGB 形式进历史为文本卡） | 是 | 始终复制 HEX（保证进颜色卡） |
| Q6 | 文字标注是否加对比描边 / 阴影提升可读性 | 不加（与微信、系统标记一致） | 按底色亮度自动加 1 pt 黑 / 白描边 |
| Q7 | 阶段 2 OCR 索引默认开还是关（隐私优先 vs 开箱即用） | **已定：默认开，可关**（本机识别、不上传、关闭即清除） | 默认关 |
| Q8 | 取色后是否结束会话 | 结束（微信行为） | 不结束，允许连续取色 |
| Q9 | 是否播放系统截图声 | 不播放 | 设置项默认关 |
| Q10 | `⌘P` 贴图、`⌘T` 提取文字的键位 | 如上 | `F3` 贴图（Snipaste 习惯）；`⌘⇧T` |
| Q11 | 保存后是否同时复制到剪贴板 | 不复制（保存与复制是两个明确出口） | 同时复制（微信行为） |
| Q12 | 贴图是否出现在后续截图的冻结帧中 | 出现 | 排除 |

## 附录 A · 本地化 key 清单（英文 key，翻译环节补 zh-Hans）

实现者按此表原样使用，避免措辞分叉。`comment` 用于说明出现位置。

| Key | 出现位置 | 建议中文 |
| --- | --- | --- |
| `Take Screenshot` | 状态栏菜单、面板按钮 tooltip（后接快捷键） | 截图 |
| `Screenshot` | 历史来源名 | 截图 |
| `Screenshots` | 设置 › 通用 分组标题 | 截图 |
| `Screenshot shortcut` | 设置行 | 截图快捷键 |
| `Off` | 快捷键清空按钮 / 状态 | 关闭 |
| `Already used to open the panel` | 录制器拒绝 | 已用于打开面板 |
| `Already used for screenshots` | 录制器拒绝 | 已用于截图 |
| `Save screenshots to` | 设置行 | 截图保存到 |
| `Same as macOS screenshots` | 目录选项 | 与系统截图相同 |
| `Choose Folder…` | 按钮 | 选择文件夹… |
| `Screen Recording` | 隐私页权限行标题 | 屏幕录制 |
| `Not granted. Only needed for screenshots.` | 权限状态 | 未授权。仅截图需要。 |
| `Granted` | 权限状态（已有 key，复用） | 已授权 |
| `Screen Recording is only used when you take a screenshot.` | 隐私页脚注 | 屏幕录制仅在截图时使用。 |
| `Allow Screen Recording to take screenshots` | 引导窗标题 | 允许屏幕录制以进行截图 |
| `Cubby needs Screen Recording to capture your screen. It only captures when you take a screenshot, and frames stay in memory until you copy, save or pin them.` | 引导窗正文 | （整句翻译） |
| `macOS may ask you to quit and reopen Cubby after granting access.` | 引导窗脚注 | 授权后 macOS 可能要求退出并重新打开 Cubby。 |
| `Open System Settings` / `Not Now` | 引导窗按钮（前者已有） | 打开系统设置 / 稍后 |
| `Press ⇧⌘2 to take a screenshot` | 授权后 HUD（快捷键插值） | 按 %@ 截图 |
| `Copied to clipboard` | HUD（已有 key） | 已拷贝到剪贴板 |
| `Copied %@` | 取色 HUD | 已拷贝 %@ |
| `Saved to %@` | 保存 HUD（目录名） | 已存储到 %@ |
| `Saved to Desktop (folder unavailable)` | 保存回退 HUD | 已存储到桌面（文件夹不可用） |
| `Couldn't save the screenshot` | 保存失败 HUD | 无法存储截图 |
| `Recognizing text…` / `Text copied` / `No text found` | OCR HUD | 正在识别文字… / 已拷贝文字 / 未找到文字 |
| `Couldn't capture the screen. Check the permission prompt.` | 采集失败 HUD | 无法捕捉屏幕，请查看权限提示。 |
| `Screen layout changed` | 显示器变化 HUD | 屏幕布局已变化 |
| `Too large for history` | 超限 HUD 附注 | 超出历史大小限制 |
| `Pointer (V)`、`Rectangle (R)`、`Ellipse (O)`、`Arrow (A)`、`Pen (P)`、`Highlighter (H)`、`Mosaic (M)`、`Text (T)`、`Number (N)` | 工具 tooltip | 指针 / 矩形 / 椭圆 / 箭头 / 画笔 / 荧光笔 / 马赛克 / 文字 / 序号 |
| `Undo (⌘Z)`、`Redo (⇧⌘Z)`、`Extract Text (⌘T)`、`Pin to Screen (⌘P)`、`Save (⌘S)`、`Cancel (esc)`、`Done (↩)` | 工具栏 tooltip | 撤销 / 重做 / 提取文字 / 贴到屏幕 / 存储 / 取消 / 完成 |
| `Thin` / `Regular` / `Thick`、`Small` / `Medium` / `Large` | 样式条 tooltip | 细 / 中 / 粗、小 / 中 / 大 |
| `Red`…`White` | 色块 accessibilityLabel | 红…白 |
| `Copy`、`Save…`、`Opacity`、`Close`、`100%`… | 贴图右键菜单（`Copy` 用 `menu.edit.copy` 同款独立 key：`pin.copy`） | 拷贝 / 存储… / 不透明度 / 关闭 |
| `Screen recording: %@`、`Screenshot shortcut: %@, save location: %@`、`Secure input: %@` | 诊断信息 | （整句） |
| `Screenshots · 截图` | QA 清单章节（文档，非源码） | — |

## 9. PM 追加决定（第一阶段纳入）

### 9.1 Q1 改判：有标注时 Esc 需按两次

document 非空时，第一次 Esc 不退出：session 进入 `isDiscardArmed = true`，发出 `.showHint(.pressEscapeAgainToDiscard)`（覆盖层显示提示「Press Esc again to discard」）；再按一次 Esc 才 `finish(.cancel)`；期间任何其他事件先解除待确认再照常处理。无标注时行为不变。理由：标注是用户投入的劳动，误触一次 Esc 全部丢失的代价远高于多按一次。

补充（PM 决定）：hovering 阶段（右键清除选区后）且 document 非空时，右键与 Esc 相同——第一次进入待确认并显示同一提示，再按一次右键或 Esc 才取消；无标注时右键仍直接取消。

### 9.2 重叠窗口逐层切换（Tab / 滚轮）

- `WindowHitTester.candidates(at:in:)`：光标下全部合格窗口（z 序前 → 后）+ 整屏兜底。
- `ScreenshotSession.hoverDepth`：当前悬停目标为 `candidates[min(hoverDepth, count − 1)]`。
- hovering 阶段：Tab / 滚轮向下 → 更深一层（止于整屏，不循环）；⇧Tab / 滚轮向上 → 更浅一层（止于 0）。候选列表（窗口 id 序列）变化时 depth 归零；同一叠内移动保持 depth。
- 滚轮有累积阈值，防止触控板惯性连续跳层。
- 单击 / ↩ / 双击作用于当前 depth 的目标。
- 理由：被遮挡、只露一角的窗口也能一键选中；微信只能选最上层。

### 9.3 纯净窗口截图（空格，与系统 ⌘⇧4 空格一致）

- hovering 且目标为窗口时，空格切换 `isWindowCaptureMode`；目标为整屏时空格无效。
- 该模式下：隐藏放大镜，高亮换成「窗口模式」样式；单击 / ↩ → `finish(.captureWindow(windowID:includeShadow:))`，⌥ + 单击不带阴影；再按空格退出；Esc 取消会话；Tab / 滚轮切到整屏时自动退出。
- 采集（实现者 B 第二段）：ScreenCaptureKit `SCContentFilter(desktopIndependentWindow:)` + `SCScreenshotManager`，按原生像素、保留圆角外透明；`includeShadow` 为 false 时不带阴影。结果直接复制并入历史（不进入标注）。
- 理由：写文档、做演示需要不受遮挡、带透明圆角的干净窗口图，这是系统截图的招牌能力，微信没有。
- 调试场景：`screenshot:hover-cycle`（depth = 1）、`screenshot:window-mode`。

### 9.4 存储前选择位置（⌘S / 工具栏「存储」）

- 设置「每次存储前询问位置」（`AppSettings.asksWhereToSaveScreenshots`，默认开启）。关闭时 ⌘S 直接写入默认文件夹（§2.8 原行为）。
- 开启时：覆盖层先**隐藏但保留会话**（窗口、选区、标注、撤销栈），后台导出；随后通过委托 `overlay(_:didRequestSave:)` 交给协调器，由 `SaveDestinationPrompting` 选择位置（正式实现 `ScreenshotSavePrompt`：`NSSavePanel` + `begin(completionHandler:)`，不用 `runModal()`，否则剪贴板监听的计时器会暂停）。Cubby 是 accessory 应用，先 `NSApp.activate()` 对话框才能成为 key；对话框出现在选区所在的屏幕上。
- 确认：`ScreenshotFileSaver.write(..., overwrite: true)` 写入所选 URL，入历史（暂停记录时除外），HUD「Saved to <文件夹>」，所选文件夹写回 `screenshotSaveDirectory` 作为下次的起始目录；协调器调用 `overlay.dismiss()` 释放覆盖层，并把前台还给截图前的应用。
- 取消：协调器调用 `overlay.resume()`，覆盖层带着点「存储」之前的会话重新上屏，可以继续编辑或改走复制、贴图等出口；Cubby 保持在前台以便覆盖层接收键盘，会话结束时再归还前台。
- 对话框打开期间再按截图快捷键：把对话框提到前面（不开始新截图、不取消）。理由：用户已经确认要存储、截图正在等位置，多半是对话框被其他窗口挡住了；开始新截图会把对话框截进去，取消又会丢掉标注。
- 对话框打开期间显示器布局变化：照常存储；若用户取消，则不再恢复覆盖层（冻结帧与新布局对不上），结束会话并提示「Screen layout changed」。
- 导出阶段仍受 `isFinishing` 保护：再按快捷键、显示器变化都不打断导出。
- 贴图右键菜单的「存储…」与 ⌘S 共用 `ScreenshotSavePrompt`（同一个对话框组件、同样记住文件夹）。

- 暂停 / 恢复机制已泛化（截图翻译）：协调器状态为 `.suspended(Presentation, .saving | .resolvingTranslation)`。翻译失败后的「去设置」「下载语言」同样先暂停覆盖层（隐藏但保留会话），`await provider.resolve(failure)` 返回后 `overlay.resumeAfterResolving(retry:)`；期间再按截图快捷键既不开始新截图也不取消（把设置 / 下载界面提到前面是 provider 的事），屏幕布局变化则在返回时结束会话。

### 9.5 截图翻译在会话里的实现（v0.3，详见 [`TRANSLATION-DESIGN.md`](TRANSLATION-DESIGN.md)）

- **译文层放在文档旁边，由文档引用**：`AnnotationDocument` 的撤销快照多记一个 `translation: TranslationRunID?`；每次翻译运行（`TranslationRun`：识别出的块、送去翻译的块、排好版的译文、阶段、语言、引擎）放在会话的 `translationRuns` 里按 id 原地更新。理由：流式到达的块不能占撤销步，而翻译进行中用户可以照常画标注——若把译文内容放进快照，后到的译文要么覆盖掉期间画的标注（按下快照重建），要么在撤销栈里留下半截译文。
- **撤销**：「应用翻译」「换语言重译」「选区变化后重新翻译」各是一次 `applyingTranslation`（一步撤销）；流式到达只更新会话里的运行内容。翻译进行中撤销 / 重做不可用。
- **Esc 取消**：`purgingTranslation(run, restoring: parent)` 把整条历史（撤销栈、当前、重做栈）里指向该运行的快照改指上一次译文（或 nil），再合并变得相同的相邻快照——那一步撤销像没发生过，期间画的标注保留；按下鼠标时的文档快照一并处理。
- **查看状态**：「原文 | 译文」开关 `showsTranslation` 决定导出（`exportedTranslation`）；按住空格（`KeyModifiers.space`，adjusting / annotating）与卷帘（`isWipeEnabled` / `wipePosition`）只影响 `translationDisplay`。选区或译文层变化时分隔线复位，译文被撤销后卷帘关闭。
- **流水线**（App）：reducer 发 `.translation(.recognize / .translate / .retry / .cancel)`，`ScreenshotTranslationPipeline` 识别 → 过滤 → 语言 → 引擎流 → 后台逐块排版 → 以 `TranslationEvent` 回报；reducer 只接受进行中那次运行、阶段对得上的回报。
- **导出层级**：冻结帧 → 译文层（`TranslationPainter`）→ 标注（`ScreenshotExporter.export(…translation:…)`）；覆盖层里译文层在遮罩之下，每块一个小图层，只重绘变化的那块。
