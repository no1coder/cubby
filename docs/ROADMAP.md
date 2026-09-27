# Cubby 项目任务分解规划：功能路线图与分发安装方案

> 范围：Cubby（原 Zhantie）v0.2 开源首发 → v0.3 → v1.0。原则 KISS / YAGNI：首发只做「让陌生人装得上、用得明白、敢提 PR」的事，功能冻结。
> 复杂度：S ≤ 1 人日，M 2–4 人日，L ≥ 5 人日。路径均相对仓库根目录。

## 已明确的决策

> **2026-09-27 维护者决策**（均采纳推荐方案）：
> 1. 自动更新：v0.2 自研手动「检查更新」（默认不联网），v1.0 再评估 Sparkle。
> 2. iCloud 同步：1.0 之前不做。
> 3. 最低系统版本：保持 macOS 14。
> 4. 存储引擎：继续 JSON + 版本号，按 T1.0-08 性能指标触发迁移。
> 5. Mac App Store：1.0 前不上架。
> 6. 应用层测试：拆出 library target `CubbyUI`（随 T0.3-09 实施）。


- 名称 Cubby（小格子），bundle ID `io.github.no1coder.Cubby`，仓库 `github.com/no1coder/cubby`，MIT 许可证。
- Swift 6 严格并发 + SwiftUI/AppKit，SPM 构建，应用本体零第三方依赖，macOS 14+，Universal（arm64 + x86_64）。
- 发布产物统一用 `Developer ID Application`（Team `69A75B6U2B`）签名，全部公证并 staple；不接任何第三方统计或崩溃上报。
- 开发语言改为英文 `en`，首发提供英文 + 简体中文；README 以英文为主，另附 `README.zh-Hans.md`。
- 渠道顺序：GitHub Releases（DMG + zip）→ 自有 tap `no1coder/homebrew-tap` → 满足门槛后进官方 homebrew-cask。
- 首发不改存储引擎（JSON + 合并保存），先补版本号与迁移框架。
- 功能冻结的唯一例外：「截图与标注」第一阶段随 v0.2 首发（T0.2-11，设计、分工与验收见 `docs/SCREENSHOT-DESIGN.md`）；第二阶段放 v1.0（T1.0-09）。

## 整体规划概述

### 项目目标

陌生用户 2 分钟内通过 `brew install --cask` 或 DMG 完成安装与授权；贡献者 `git clone && make test` 即可参与；之后两个版本补齐与 PasteNow / Paste 的核心效率差距。

### 技术栈

Swift 6.2 / Xcode 26（CI 必须有 macOS 26 SDK：`Sources/Cubby/Panel/PanelChrome.swift` 使用 `NSGlassEffectView`）、Swift Testing、String Catalog（`xcrun xcstringstool`）、`codesign` / `notarytool` / `stapler` / `hdiutil`、GitHub Actions、Homebrew Cask。截图（v0.2）：ScreenCaptureKit、Vision（本机 OCR）。按需：QuickLookUI、AppIntents、系统 `SQLite3`、Sparkle 2。

### 主要阶段

1. **v0.2 开源首发**（约 13 人日，另加截图第一阶段）：改名收尾、国际化、数据版本号、授权修复引导、诊断信息、CI、签名公证发布流水线、Homebrew tap、社区文档；截图与标注第一阶段（T0.2-11）。
2. **v0.3 效率补齐**（约 18 人日）：自动清理、多选合并、粘贴队列、⌘K 动作与文本转换、编辑后粘贴、Quick Look、导入导出、应用层单测（VoiceOver 基线已在 v0.2 完成）。
3. **v1.0 组织与集成**（约 22 人日，另加截图第二阶段）：自定义 / 智能列表、OCR 搜索（含截图）、截图第二阶段、片段模板、URL Scheme + AppIntents、Raycast/Alfred、链接标题（可选）、官方 homebrew-cask。

## 一、功能差距分析

对标 PasteNow / Paste / Maccy / Raycast Clipboard History。「版本」列即建议落地版本。

| 功能（参考产品） | 用户价值 | 实现要点（模块 / API） | 复杂度 | 风险 | 版本 |
| --- | --- | --- | --- | --- | --- |
| 授权修复引导（自身问题） | 消除「开关已开却无效」这一头号困惑 | `PermissionState` 现只有 ok / warning 两态，新增第三态 `.stale`：记录「曾授权成功」与当时签名 Team ID / cdhash（`SecCodeCopySigningInformation`），`AXIsProcessTrusted()==false` 且曾授权 → 修复流程（在列表中「−」删除旧条目后重新开启），`PermissionMonitor` 1.5 秒轮询自动确认 | M | 无法读 TCC.db，只能启发式判断 | v0.2 |
| 多语言 | 开源受众 | String Catalog，见 §二.1；后续语言由社区 PR | M | 字符串遗漏、英文溢出 | v0.2 |
| 截图与标注（微信截图、Snipaste、系统 ⇧⌘4） | 截完直接进剪贴板历史，之后可搜可贴；标注、贴图、提取文字、取色一步完成 | ScreenCaptureKit 冻结帧 + 每屏一个覆盖层；Core `ScreenshotSession` / `ScreenshotReducer` 纯状态机；Vision 本机 OCR；见 `docs/SCREENSHOT-DESIGN.md` | L | 屏幕录制权限（授权后常需重开应用）、多屏坐标、中文输入法 | v0.2（第一阶段） |
| 按时间自动清理（Maccy） | 隐私、控制体积 | Core 纯函数 `ClipHistory.removingOlder(than:)`；设置 `retention`；启动时 + 每小时执行；收藏除外；复用 BlobStore 孤儿清理 | S | 误删 → 仅作用于非收藏并明示 | v0.3 |
| 多选合并粘贴（Paste） | 一次拼接多段 | Core `ClipSelection`（有序 ID，不可变）+ `ClipMerger.merge(_:separator:)`；文本按分隔符拼接，文件合并为多个 URL，图片不参与 | M | 混合类型语义 | v0.3 |
| 粘贴队列（Paste Stack） | 表单、批量填写 | Core `PasteQueue` 值类型；全局热键「粘贴下一条」；写剪贴板时带自有 marker 类型，`ClipboardMonitor` 跳过自写入 | M | 目标应用读取时序竞态 | v0.3 |
| 编辑后粘贴（Paste、PasteNow） | 改几个字无需切应用 | 面板内浮层 `TextEditor`（禁用 sheet）；默认生成新条目、原条目不动；富文本降级纯文本 | M | 焦点与 esc 层级 | v0.3 |
| 粘贴时文本转换（Raycast） | 去格式、大小写、去空行、去 URL 跟踪参数、JSON 格式化、Base64 / URL 编解码 | Core `TextTransform` 枚举 + 纯函数，面板 `⌘K` 动作浮层调用 | S–M | 低 | v0.3 |
| Quick Look（Paste） | 预览 PDF / Office / 视频 | 在现有预览面板嵌入 `QLPreviewView`（QuickLookUI）；不用 `QLPreviewPanel`（会成为 key，违反 DESIGN.md） | S | 大文件卡顿 | v0.3 |
| 导入导出 | 换机、备份（历史默认排除 Time Machine） | 导出 `history.json` + `Images/` 目录，用 `NSFileCoordinator` 的 `.forUploading` 打成 zip（零依赖）；导入按 `contentHash` 合并 | M | 导出文件含敏感数据 → 导出前警示 | v0.3 |
| 辅助功能 VoiceOver | 可达性 | 卡片 `accessibilityLabel` + `accessibilityAction(named:)`；HUD 用 `AccessibilityNotification.Announcement`；尊重 `accessibilityReduceMotion` | M | 非激活面板在 VoiceOver 下需实测 | **v0.2 已完成基线** / v1.0 审计 |
| Vim 键位 | 键盘党 | 不引入模式：增加 `⌃J` / `⌃K`（与现有 `⌃N` / `⌃P` 并列）；`j` / `k` 与「直接输入即搜索」冲突，不做 | S | 低 | v0.3 |
| 自定义 / 智能列表（Paste Pinboards、PasteNow） | 分组管理常用内容 | Core `ClipList { id, name, color, rule? }`；手动列表在条目上存 `listIDs`；智能列表规则复用 `ClipFilter`（类型 / 来源应用 / 关键词 / 时间） | L | 需 schema v2；分类栏宽度 | v1.0 |
| 图片 OCR 搜索（Raycast） | 截图里的文字可搜 | 捕获后低优先级串行 `Task` 执行 `VNRecognizeTextRequest`（`.accurate`，zh-Hans + en-US）；结果存可选字段 `ClipItem.recognizedText`（schema 不升级），纳入预折叠搜索索引（排序低于正文命中）；截图与普通剪贴板图片都会索引 | M | CPU / 电量 → 并发 1、低优先级、> 4K 面积先缩放、可关闭 | **v0.2（已提前完成）** |
| 截图：按住 ⌥ 识别 UI 元素（Snipaste） | 精确截取按钮、列表项等控件 | `AXUIElementCopyElementAtPosition` 取元素边框（需辅助功能权限），`AXUIElementSetMessagingTimeout(0.1)` + 后台线程查询 | S–M | 无响应应用阻塞；Electron / 网页元素粒度不稳 | v1.0 |
| 截图：从历史贴图 | 把历史里的图片贴到屏幕上对照 | 卡片右键「Pin to Screen」（`⇧⌘P`），复用 `PinnedImageController` | S | 低 | **v0.2 已完成** |
| 截图：恢复上次选区 | 反复截同一区域 | 会话内存记忆（按屏幕与屏幕布局），hovering 时 `⌘Z` 恢复并显示虚线框；重启不保留 | S | 低 | v1.0 |
| 长截图 / 滚动拼接（CleanShot X） | 截取超出一屏的长页面 | 合成滚动事件（需辅助功能权限）+ 图像拼接（特征匹配） | L | 固定页眉、懒加载、弹性回弹；Electron 与 WKWebView 行为各异，失败模式多 | 暂不做（见 T1.0-09） |
| 片段模板（Raycast Snippets） | 常用回复、带日期 | 列表条目支持 `{date}` `{time}` `{clipboard}` `{cursor}`，Core `TemplateRenderer` 纯函数；不做缩写自动展开（需输入监控权限） | M | 与隐私定位冲突的部分坚决不做 | v1.0 |
| URL Scheme / AppIntents / 快捷指令 | 自动化 | `CFBundleURLTypes` 注册 `cubby://open`、`search?q=`、`pause`、`resume`；AppIntents：`GetRecentClips`、`CopyClip`、`PauseRecording` | M–L | 纯 `swift build` 不生成 AppIntents 元数据（`Metadata.appintents`），需 spike；URL 不返回历史内容 | v1.0 |
| Raycast / Alfred 集成 | 已有工作流用户 | 只调用 `cubby://`：Alfred Workflow、Raycast 扩展放独立仓库，不读数据文件 | S | 外部仓库维护 | v1.0 |
| 链接标题（可选） | 链接卡片易辨认 | `LPMetadataProvider`，默认关闭；仅 http(s)，排除 localhost / 内网 IP / 带 token 类参数，5 秒超时 | S–M | 访问 URL 会消耗一次性登录链接并暴露访问行为 | v1.0 opt-in |
| 音效 | 操作反馈 | `NSSound(named: "Pop")`，默认关闭 | S | 低 | v1.0 |
| 存储迁移到 SQLite + FTS5 | 大历史检索、增量写 | 系统 `import SQLite3`（仍零第三方）；FTS5 `tokenize='trigram'` 支持中文子串（≥3 字，1–2 字回退 `instr`）；`HistoryPersisting` 改为增量接口 | L | 迁移丢数据 → 先备份 JSON、单向迁移 | 指标触发（问题 4） |
| iCloud 同步（Paste、PasteNow） | 多设备 | `CKSyncEngine`（macOS 14+）+ 私有库，正文放 `encryptedValues`，图片 `CKAsset`；需 iCloud entitlement + 嵌入 provisioning profile | L | 敏感数据上云、冲突合并、贡献者无法本地构建同步版 | 待决策（问题 2） |

## 二、开源前必须完成的工程项（v0.2）

### 1. 国际化（String Catalog，en 为开发语言）

现状：`Sources/` 约 66 个文件、~250 处中文字面量（`CubbyCore` 约 23 处，如 `ClipItem.title` 的「图片 w×h」、`ClipKind.displayName`）；`Package.swift` 与 `Info.plist` 开发语言为 `zh-Hans`。

- 源码改为英文键：SwiftUI `Text("Paste to \(app)")` 自动本地化；AppKit 与 Core 用 `String(localized:comment:)`（默认 `bundle: .main`，Core 编进可执行文件后运行时解析到 .app）。
- Catalog 放 `Resources/Localizable.xcstrings`，**不作为 SPM resource**（避开 `Bundle.module` 在 .app 中的路径与签名问题），由 `scripts/build-app.sh` 编译进 .app：
  `xcrun xcstringstool compile Resources/Localizable.xcstrings -o "$APP_DIR/Contents/Resources"`
- 提取脚本 `scripts/sync-strings.sh`（spike 验证 `.stringsdata` 输出位置；不行则用 Xcode 打开 `Package.swift` 维护）：
  `swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc .build/strings && xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata .build/strings/*.stringsdata`
- `Package.swift` `defaultLocalization: "en"`；`Info.plist` `CFBundleDevelopmentRegion=en`，新增 `CFBundleLocalizations = (en, zh-Hans)`。复数用 catalog variations（`%lld items`）。
- 守卫 `scripts/check-no-cjk.sh`（CI 运行，macOS 自带 grep 不支持 `-P`，用 perl）：
  `perl -CSD -ne 'print "$ARGV:$.: $_" if /"[^"]*\p{Han}/ && !m{^\s*//}; close ARGV if eof' $(find Sources -name '*.swift')`，有输出即失败。
- 布局验证：`open build/Cubby.app --args -AppleLanguages '(en)' -NSDoubleLocalizedStrings YES`（伪本地化加长文本）与 `-NSShowNonLocalizedStrings YES`（未翻译项报警）。

### 2. 其余工程项

| 项 | 具体做法 | 涉及文件 | 验收 |
| --- | --- | --- | --- |
| 数据格式版本号与迁移 | `history.json` 增加 `schemaVersion`（缺失视为 v0，与现格式兼容）；`HistoryMigrator` 纯函数链；迁移前备份 `history.v<N>.bak.json`（0600）；**版本高于当前 → 抛 `unsupportedVersion`，只读模式，绝不覆盖**（防降级丢数据）；新字段一律 Optional + `decodeIfPresent`；UserDefaults 加 `settingsVersion` | `Sources/CubbyCore/Storage/HistoryStorage.swift`、新 `HistoryMigrator.swift`、`Tests/CubbyCoreTests/Fixtures/history-v0.json` | v0 fixture 无损加载；v99 文件不被改写 |
| CI（GitHub Actions） | `.github/workflows/ci.yml`：push / PR → `macos-26`（不可用时 `macos-15` + `sudo xcode-select -s /Applications/Xcode_26.x.app`）→ `swift format lint --strict --recursive Sources Tests`（工具链自带，零依赖，配 `.swift-format`）→ `check-no-cjk.sh` → `swift build -c release --arch arm64 --arch x86_64` → `swift test --enable-code-coverage` + 覆盖率门槛 95%（`xcrun llvm-cov report`）→ `SIGN_IDENTITY=- ./scripts/build-app.sh` 验证打包；action 固定到 commit SHA | `.github/workflows/ci.yml`、`.swift-format`、`scripts/check-coverage.sh`、`Makefile`（`make lint`） | PR 15 分钟内全绿 |
| Release 流水线 | 见 §三.7 | `scripts/*.sh`、`.github/workflows/release.yml`、`publish.yml` | 打 tag 自动产出已公证 draft release |
| 社区文件 | `LICENSE`（MIT，`Copyright (c) 2026 no1coder`）；`CONTRIBUTING.md`（Xcode 26、`make test`、Conventional Commits、新增字符串流程、本地签名见 §三.5）；`CODE_OF_CONDUCT.md`（Contributor Covenant 2.1）；`SECURITY.md`（启用 GitHub Private Vulnerability Reporting；范围：数据泄露、误粘贴、权限）；`.github/ISSUE_TEMPLATE/{bug_report.yml,feature_request.yml,config.yml}`（bug 必填版本、macOS、芯片、安装方式、「复制诊断信息」内容）；`.github/PULL_REQUEST_TEMPLATE.md`；`.github/dependabot.yml`（仅 github-actions）；`CHANGELOG.md`（Keep a Changelog） | 仓库根目录、`.github/` | GitHub Community Standards 100% |
| README 截图与 GIF | 英文 `README.md` + `README.zh-Hans.md`：顶部 GIF（呼出 → 搜索 → 粘贴，≤ 8 秒、≤ 5 MB）、深 / 浅色截图、安装（brew / DMG / 源码）、权限说明、隐私、快捷键、FAQ（授权失效）；素材放 `docs/assets/`，用演示数据目录录制 | `README*.md`、`docs/assets/` | 首屏 5 秒内看懂用途与安装 |
| 应用层测试策略 | Core 保持 Swift Testing + 95% 门槛；ViewModel：spike `@testable import Cubby`（SPM 支持测试可执行 target，需验证 `main.swift` + `@MainActor`），失败则拆出 library target `CubbyUI` 承载 `Panel/`、`Settings/` 的 ViewModel，可执行 target 只留 `main.swift`；XCUITest 需要 Xcode 工程与 UI test bundle，纯 SPM 不支持 → 不做，改为 `docs/QA-CHECKLIST.md` 双语手工冒烟清单；不做像素快照（跨系统版本不稳定） | `Package.swift`、`Tests/CubbyTests/`、`docs/QA-CHECKLIST.md` | v0.2 有清单；v0.3 ViewModel ≥ 30 个用例 |
| 崩溃与诊断 | v0.2：关于页「复制诊断信息」→ 纯文本：版本 / 构建号、macOS、芯片、安装路径（标记 `/AppTranslocation/`、`/Volumes/`）、签名 Team ID / 是否 ad-hoc、两项权限状态、条目数与数据目录大小。**绝不含剪贴板内容**。v0.3：「导出诊断包」zip = 上述文本 + 本次运行日志（`OSLogStore(scope: .currentProcessIdentifier)`，只能取当前进程）+ 用户确认后附最近 5 个 `~/Library/Logs/DiagnosticReports/Cubby-*.ips`。`Logger` 中内容类插值一律 `.private` | `Sources/Cubby/Settings/AboutSettingsPane.swift`、新 `Services/Diagnostics.swift` | 输出中 grep 不到任何条目正文 |
| 隐私声明 | `PRIVACY.md` + README 段落 + 关于页一句话：默认不联网、无统计、无崩溃上报、数据位置与彻底删除命令（`rm -rf ~/Library/Application\ Support/Cubby && defaults delete io.github.no1coder.Cubby && tccutil reset All io.github.no1coder.Cubby`）。CI 守卫：`URLSession` / `LPMetadataProvider` 只允许出现在白名单文件（如 `UpdateChecker.swift`） | `PRIVACY.md`、`scripts/check-network.sh` | 声明与代码一致，可被守卫验证 |

## 三、分发与安装方案

### 3.1 签名、公证、staple

一次性准备：App Store Connect → 用户和访问 → 集成 → 团队密钥，生成 API Key（角色 Developer），保存 `AuthKey_<KEYID>.p8`、Key ID、Issuer ID；本机 `xcrun notarytool store-credentials cubby-notary --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER_ID>`。

`scripts/build-app.sh` 必改：`--timestamp=none` → `--timestamp`（公证强制要求安全时间戳，可用 `TIMESTAMP` 变量让开发构建保留 none）；保留 `--options runtime`；无需 entitlements 文件（非沙盒、无 JIT / Apple Events）；新增用 `PlistBuddy` 注入 `CFBundleShortVersionString=$VERSION`、`CFBundleVersion=$(git rev-list --count HEAD)`（单调递增）。嵌套代码（如日后引入 Sparkle）按由内到外逐个签名，禁止 `--deep` 签名。

发布脚本 `scripts/notarize.sh` + `scripts/make-dmg.sh`（`make release VERSION=x.y.z` 调用，本地与 CI 共用）：

```bash
ID="Developer ID Application: <Name> (69A75B6U2B)"; V=0.2.0; mkdir -p dist
SIGN_IDENTITY="$ID" ./scripts/build-app.sh
codesign -dvv build/Cubby.app 2>&1 | grep -E 'TeamIdentifier|flags|Timestamp'   # 确认 runtime 与时间戳
# 1) 公证 .app 并 staple（离线首启也能通过 Gatekeeper）
ditto -c -k --keepParent build/Cubby.app build/notarize.zip
xcrun notarytool submit build/notarize.zip --keychain-profile cubby-notary --wait
xcrun stapler staple build/Cubby.app
# 2) DMG：放入已 staple 的 .app，签名 → 公证 → staple
rm -rf build/dmg && mkdir build/dmg && cp -R build/Cubby.app build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname Cubby -srcfolder build/dmg -ov -format ULFO "dist/Cubby-$V.dmg"
codesign --sign "$ID" --timestamp "dist/Cubby-$V.dmg"
xcrun notarytool submit "dist/Cubby-$V.dmg" --keychain-profile cubby-notary --wait
xcrun stapler staple "dist/Cubby-$V.dmg"
# 3) zip（Homebrew / 更新检查用）与校验和
ditto -c -k --sequesterRsrc --keepParent build/Cubby.app "dist/Cubby-$V.zip"
(cd dist && shasum -a 256 "Cubby-$V.dmg" "Cubby-$V.zip" > SHA256SUMS.txt)
# 4) 验证
spctl -a -vvv -t exec build/Cubby.app                                   # 期望 source=Notarized Developer ID
spctl -a -vvv -t open --context context:primary-signature "dist/Cubby-$V.dmg"
xcrun stapler validate "dist/Cubby-$V.dmg"
```

公证失败：`xcrun notarytool log <submission-id> --keychain-profile cubby-notary`。CI 中把 `--keychain-profile` 换成 `--key "$RUNNER_TEMP/AuthKey.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"`。

| DMG 方式 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| `hdiutil`（系统自带） | 零依赖、CI 稳定、脚本约 10 行 | 无背景图与图标布局（仅 app + Applications 链接） | **首发采用** |
| `create-dmg`（`brew install create-dmg`，shell） | 背景图、图标坐标、窗口尺寸 | 通过 AppleScript 驱动 Finder，headless CI 偶发超时；多一个构建依赖 | v1.0 视需要 |
| `sindresorhus/create-dmg`（npm） | 一条命令、自动签名 | 引入 Node 工具链，外观固定 | 不采用 |

### 3.2 GitHub Releases

- 资产：`Cubby-X.Y.Z.dmg`（主推）、`Cubby-X.Y.Z.zip`、`SHA256SUMS.txt`；说明取自 `CHANGELOG.md` 对应段落。
- 先 `gh release create vX.Y.Z dist/* --draft --verify-tag --notes-file dist/NOTES.md`，在干净用户账户冒烟后再 Publish（Publish 事件触发 tap 更新）。
- 可选供应链证明：`actions/attest-build-provenance`，用户可 `gh attestation verify Cubby-X.Y.Z.dmg -R no1coder/cubby`。
- SemVer；`-beta.N` 标记 prerelease，tap 与更新检查忽略。

### 3.3 Homebrew

自有 tap：仓库 `no1coder/homebrew-tap`，文件 `Casks/cubby.rb`，用户执行 `brew install --cask no1coder/tap/cubby`。

```ruby
cask "cubby" do
  version "0.2.0"
  sha256 "<SHA256SUMS.txt 中 dmg 的值>"

  url "https://github.com/no1coder/cubby/releases/download/v#{version}/Cubby-#{version}.dmg"
  name "Cubby"
  desc "Keyboard-first clipboard history manager"
  homepage "https://github.com/no1coder/cubby"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Cubby.app"

  uninstall quit: "io.github.no1coder.Cubby"

  zap trash: [
    "~/Library/Application Support/Cubby",
    "~/Library/Caches/io.github.no1coder.Cubby",
    "~/Library/HTTPStorages/io.github.no1coder.Cubby",
    "~/Library/Preferences/io.github.no1coder.Cubby.plist",
    "~/Library/Saved Application State/io.github.no1coder.Cubby.savedState",
  ]
end
```

- 引入 Sparkle 后才加 `auto_updates true`（否则 `brew upgrade` 负责升级）。不推荐用户使用 `--no-quarantine`（Homebrew 正在淘汰该参数与未签名 cask，以官方公告为准）。
- 进官方 homebrew-cask：硬性要求已签名 + 公证、稳定版、官方下载地址可 livecheck；另有 GitHub star / fork / watcher 的 notability 门槛（作者自提交更高，以 docs.brew.sh「Acceptable Casks」当时为准）。时机：v1.0 且达到门槛。流程：`brew audit --new --cask cubby` + `brew style` 通过后向 `Homebrew/homebrew-cask` 提 PR；合并后在自有 tap 加 `tap_migrations.json`：`{ "cubby": "homebrew/cask" }` 并删除自有 cask；后续版本由 autobump 或 `brew bump-cask-pr` 更新。

### 3.4 自动更新

| 方案 | 做法 | 优点 | 缺点 |
| --- | --- | --- | --- |
| Sparkle 2 | SPM 依赖 `https://github.com/sparkle-project/Sparkle`（2.x）；`build-app.sh` 复制 `Sparkle.framework` 到 `Contents/Frameworks`，链接加 `-Xlinker -rpath -Xlinker @executable_path/../Frameworks`；非沙盒可删除 XPCServices；`generate_keys` 生成 EdDSA 密钥，公钥写 `SUPublicEDKey`，私钥 `generate_keys -x` 导出为 CI secret；`sign_update Cubby-X.Y.Z.zip --ed-key-file <key>` 得到签名写入 `appcast.xml`；托管在 GitHub Pages `https://no1coder.github.io/cubby/appcast.xml`（`SUFeedURL`） | 行业标准、自动下载安装重启、EdDSA 防篡改、可做增量 | 打破「零依赖」、约 3 MB 二进制、打包与签名脚本复杂度翻倍、多一个密钥要保管 |
| 自研检查 | `Sources/Cubby/Services/UpdateChecker.swift`：`URLSession` 请求 `https://api.github.com/repos/no1coder/cubby/releases/latest`（未认证 60 次 / 小时，足够）；Core 新增 `SemanticVersion` 纯函数比较 `tag_name`；有新版则提示并打开 Release 页或提示 `brew upgrade --cask cubby`；不下载、不替换 app | 零依赖、约 1 人日、可完整单测 | 用户需手动下载替换 |

**推荐**：v0.2 采用自研「检查更新」——关于页按钮 + 菜单项手动触发，「每周自动检查」开关默认关闭，守住「默认不联网」；Homebrew 用户走 `brew upgrade`。v1.0 时若 DMG 用户占比高、Issue 频繁出现旧版本问题，再引入 Sparkle 2。无论哪种方案，更新前后必须保持同一 Team ID 与 bundle ID，否则辅助功能授权会失效。

### 3.5 从源码构建

```bash
git clone https://github.com/no1coder/cubby && cd cubby
make test && make install        # 签名：SIGN_IDENTITY → 首个 Apple Development 证书 → ad-hoc（-）
```

- ad-hoc 签名的 designated requirement 就是 cdhash，每次重建都会变化 → 系统设置里旧条目「看起来开启但实际无效」（TCC 日志报 `Failed to match existing code requirement`）。
- 推荐贡献者一次性创建自签名代码签名证书：钥匙串访问 → 证书助理 → 创建证书 → 类型选「代码签名」，命名 `Cubby Local`，之后 `SIGN_IDENTITY="Cubby Local" make install`；此后要求绑定证书而非 cdhash，重建后授权保持有效。
- 否则每次重建后执行 `tccutil reset Accessibility io.github.no1coder.Cubby`，再打开 Cubby 重新授权。
- 与正式版共存：`build-app.sh` 支持 `BUNDLE_ID` 覆盖，`make run` 默认使用 `io.github.no1coder.Cubby.dev` + `CUBBY_DATA_DIR`，隔离授权、偏好与数据。

### 3.6 Mac App Store 可行性

- 技术上可行：沙盒应用仍可通过 `AXIsProcessTrustedWithOptions` 申请辅助功能，授权后 `CGEvent.post` 可用；Maccy、Paste 等同类应用已在 MAS 上架并支持直接粘贴。Carbon `RegisterEventHotKey`、`SMAppService`、`NSPasteboard` 在沙盒内可用。
- 代价：数据路径变为 `~/Library/Containers/io.github.no1coder.Cubby/Data/...`，需要迁移；文件条目的打开、在访达中显示、Quick Look 访问沙盒外路径需 security-scoped bookmark；审核要解释辅助功能用途，存在被拒风险；需要 provisioning profile 与 `productbuild` 打包；应用内不能自更新。
- **结论：v1.0 前不上架**。1.0 之后可评估「开源免费 + MAS 付费支持」模式（Maccy 即如此），以 `CUBBY_MAS` 编译条件隔离差异（见问题 5）。

### 3.7 GitHub Actions 发布流水线

| Secret（绑定 Environment `release`，需维护者审批） | 内容 / 获取方式 |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | 钥匙串导出 Developer ID Application 证书 + 私钥为 .p12，`base64 -i cubby.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | 导出 p12 时设置的密码 |
| `NOTARY_KEY_P8_BASE64` / `NOTARY_KEY_ID` / `NOTARY_ISSUER_ID` | App Store Connect API Key（§3.1；以 docs/RELEASING.md 为准） |
| `TAP_GITHUB_TOKEN` | fine-grained PAT，仅授权 `no1coder/homebrew-tap` 的 Contents: Read and write |
| `SPARKLE_ED_PRIVATE_KEY` | 仅在引入 Sparkle 后需要 |

非机密放 Variables：`SIGN_IDENTITY`。临时钥匙串密码运行时 `openssl rand -base64 24` 生成。PR 工作流不引用任何 secret；第三方 action 固定 commit SHA。

**`release.yml`**（`on: push: tags: ['v*']`，`environment: release`）：

1. checkout（`fetch-depth: 0`）→ 选择 Xcode 26 → `swift test`（门禁）。
2. 导入证书到临时钥匙串：
   `security create-keychain -p "$KC_PW" build.keychain && security set-keychain-settings -lut 21600 build.keychain && security unlock-keychain -p "$KC_PW" build.keychain && security import cert.p12 -k build.keychain -P "$P12_PW" -T /usr/bin/codesign && security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PW" build.keychain && security list-keychains -d user -s build.keychain login.keychain`
3. 写出 `$RUNNER_TEMP/AuthKey.p8` → `make release VERSION=${GITHUB_REF_NAME#v}`（§3.1 同一脚本）。
4. `gh release create "$GITHUB_REF_NAME" dist/* --draft --verify-tag --notes-file dist/NOTES.md`。
5. `if: always()`：`security delete-keychain build.keychain`，删除 p12 / p8。

**`publish.yml`**（`on: release: types: [published]`，跳过 prerelease）：draft 资产不可公开下载，所以 tap 与 appcast 只能在 Publish 后更新。

1. 下载 `SHA256SUMS.txt` → `scripts/update-tap.sh "$VERSION" "$SHA256"`：用 `TAP_GITHUB_TOKEN` 克隆 tap，替换 `Casks/cubby.rb` 中 `version` / `sha256`，`brew style Casks/cubby.rb`，提交 `cubby X.Y.Z` 并 push。
2. （引入 Sparkle 后）`sign_update` 生成新 `<item>` 追加到 `gh-pages` 分支的 `appcast.xml`。

### 3.8 首次安装体验

| 环节 | 体验 | 措施 |
| --- | --- | --- |
| 下载 DMG | 窗口内只有 Cubby 与「应用程序」快捷方式 | hdiutil 方案已满足 |
| 首次打开 | 已公证 + staple：只出现一次「从互联网下载」确认，离线也可 | §3.1；不再需要「右键打开」或 `xattr` |
| 在 DMG / 下载目录直接运行 | App Translocation 会让登录启动、更新检查异常 | 检测路径含 `/AppTranslocation/` 或 `/Volumes/` → 提示先移动到「应用程序」 |
| 授权引导 | 剪贴板读取（macOS 15.4+）+ 辅助功能 | 现有引导 + T0.2-04 修复分支 |
| 首次截图 | 屏幕录制不在首次启动引导中；第一次截图时出现系统弹窗 + Cubby 引导窗，授权后 macOS 可能要求重开 Cubby | 引导窗脚注明说可能需要重开；1.5 秒轮询，授权后提示「按 ⇧⌘2 截图」；见 `docs/SCREENSHOT-DESIGN.md` §2.13 |
| Homebrew | 与 DMG 相同的 Gatekeeper 流程 | 不需要 `--no-quarantine` |
| 从 Zhantie 迁移（仅维护者本人，一次性，不写进应用） | — | 见下方命令 |

```bash
pkill -x Zhantie; rm -rf /Applications/Zhantie.app
mv ~/Library/Application\ Support/Zhantie ~/Library/Application\ Support/Cubby
defaults export app.zhantie.Zhantie - | defaults import io.github.no1coder.Cubby -
tccutil reset Accessibility app.zhantie.Zhantie
```

## 四、详细任务分解（分阶段计划）

### 阶段 v0.2：开源首发（约 13 人日）

- [ ] **T0.2-01 改名收尾**（0.5d，前置）：`grep -rni zhantie --exclude-dir=.build --exclude-dir=build .` 只剩迁移说明；`Makefile`、`build-app.sh`、`Info.plist`、Logger subsystem、`CUBBY_DATA_DIR`、README 一致。
- [ ] **T0.2-02 国际化**（3d，依赖 01）：输出 `Resources/Localizable.xcstrings`（en / zh-Hans 100%）、`scripts/sync-strings.sh`、`scripts/check-no-cjk.sh`；涉及 `Package.swift`、`Resources/Info.plist`、`scripts/build-app.sh`、`Sources/Cubby/**`、`Sources/CubbyCore/Models/{ClipItem,ClipKind}.swift`、`Sources/CubbyCore/History/ClipFilter.swift`（分类名）及断言中文的测试。
  - UI 要点：英文分类栏约 388pt，超出可用的 356pt → `PanelHeader.swift` 用 `ViewThatFits(in: .horizontal)` 四级降级（全文字 → 收紧 padding → 「收藏」改 `star.fill` → 全部 SF Symbol + `.help`），不用横向滚动；单个标签 ≤ 9 字符。`PanelFooter.swift` 保留优先级 `↩ Paste to App` > 帮助 > 计数 > `⇧↩` 提示，App 名 maxWidth 90、尾部截断。禁止拼接字符串，改用整句格式串（`"Paste to %@"`、`"No %@ items"`，中文引号放进译文），计数用复数变体。相对时间用 `RelativeDateTimeFormatter` 的 `.abbreviated`。设置表单标签不定宽。
- [ ] **T0.2-03 数据版本号与迁移**（1d，依赖 01）：见 §二.2；涉及 `Sources/CubbyCore/Storage/`、新增 fixture 测试。
- [ ] **T0.2-04 授权修复引导 + 安装位置检查**（2d，依赖 01，文案走 02 流程）：新增 `Sources/Cubby/Services/SigningInfo.swift`（读 Team ID / ad-hoc）；修改 `Settings/PermissionMonitor.swift`、`Settings/PermissionRow.swift`、`Onboarding/OnboardingView.swift`、`Panel/PanelWarning.swift`。
  - UI 要点：`.stale` 用橙色 warning 而非红色。标题「辅助功能授权已失效 / Accessibility access needs to be renewed」，说明「更新后旧开关可能仍显示开启但已失效，请选中 Cubby 点 − 移除后重新开启」。只放一个主按钮「打开辅助功能设置」，`.stale` 态下不调用 `requestTrust()`，避免系统弹窗和设置窗口叠在一起。次级入口用 `DisclosureGroup("仍然无效？")` 展示三步清单，外加 `tccutil reset Accessibility io.github.no1coder.Cubby` 与「复制命令」按钮：命令只复制、不由应用代为执行，复制后行内提示 2 秒。面板横幅「直接粘贴已失效」附「修复…」按钮，打开设置的隐私页并自动展开步骤。恢复后图标变绿并显示「已恢复，可直接粘贴」；60 秒仍未恢复则出现「重新启动 Cubby」。
- [ ] **T0.2-05 诊断信息 + 隐私声明**（1d）：`Services/Diagnostics.swift`、`AboutSettingsPane.swift`、`PRIVACY.md`、`scripts/check-network.sh`。
- [ ] **T0.2-06 CI + lint**（1d，依赖 01）：`.github/workflows/ci.yml`、`.swift-format`、`scripts/check-coverage.sh`、`make lint`。
- [ ] **T0.2-07 签名公证与 release 流水线**（2d，依赖 06）：`scripts/{notarize,make-dmg}.sh`、`build-app.sh`（时间戳、版本注入、`BUNDLE_ID`）、`Makefile`（`dmg` / `release`）、`.github/workflows/release.yml`；先本地跑通一次完整公证再上 CI。
- [ ] **T0.2-08 Homebrew tap + publish 流水线**（0.5d，依赖 07）：新仓库 `no1coder/homebrew-tap`、`Casks/cubby.rb`、`scripts/update-tap.sh`、`.github/workflows/publish.yml`。
- [ ] **T0.2-09 社区文件 + README + 截图**（1.5d，依赖 02 的英文界面）：见 §二.2；同步把 DESIGN.md 与帮助浮层中遗漏的 `⌘Y`（预览）补上。
  - 截图清单：主面板 hero（六类卡片）、空格预览、搜索高亮 + 分类、引导窗口、History / Privacy 设置页、截图标注（README「Screenshots」小节引用 `docs/assets/screenshots/screenshot-annotate-dark.png`，可用 DEBUG 构建 `--scenario screenshot:annotating` 在合成桌面上摆拍），每张出深 / 浅色、中 / 英文版本，2x 截取（单面板 760×1240 px），README 用 `<picture>` + `prefers-color-scheme` 切换。GIF：呼出 → ↓↓ → ↩ 粘贴，≤ 8 秒，`gifski --fps 15 --width 800`。窗口截图用 `screencapture -o -l <windowID>`。隐私方面：在新建的 demo 用户下，用种子脚本 + `CUBBY_DATA_DIR` 生成假数据；文件卡片会显示 `/Users/<用户名>/` 完整路径，画面里不能出现真实账号、token。
- [ ] **T0.2-10 检查更新（手动）**（0.5d，取决于问题 1）：`Services/UpdateChecker.swift`、Core `SemanticVersion` + 单测。
- [ ] **T0.2-11 截图与标注 · 第一阶段**（功能冻结的例外，不计入 13 人日；A Core / B 基础设施与输出 / C 覆盖层三人并行，契约、文件所有权与完成定义见 `docs/SCREENSHOT-DESIGN.md` §3–§4；依赖 01，文案走 02 流程，最后统一 `make strings` 补 zh-Hans）：一个版本、三个里程碑，逐项验收以设计文档 §7.1 为准。
  - **M1 截得到**：`⇧⌘2`（可改、可关闭，与面板快捷键互斥）、菜单栏「Take Screenshot」、面板相机按钮三个入口；ScreenCaptureKit 冻结帧，M1 单屏 P50 ≤ 150 ms；悬停识别窗口、拖拽选区（⇧ 正方形 / ⌥ 中心扩展 / 空格平移）、8 个手柄与方向键精修、放大镜取色（`C`）；`↩` / `⌘C` / 双击完成 → 写剪贴板并入历史（来源「Screenshot」，暂停记录时不入历史）；多屏不同缩放、全屏应用、显示器插拔时取消；屏幕录制权限在首次截图时才申请并显示引导窗，隐私页权限行，诊断信息三行。
  - **M2 画得好**：工具栏 / 样式条（macOS 26 玻璃无直角投影）；矩形、椭圆、箭头、画笔、荧光笔、马赛克、文字（支持拼音输入）、序号 8 种标注；选中后可拖动、微移、改色、删除；撤销 / 重做；每个工具的样式跨会话记忆。
  - **M3 出得去**：`⌘S` 保存 PNG（跟随系统截图目录或自选目录）、`⌘P` 贴图、`⌘T` 本机 Vision 提取文字；新文案 zh-Hans 齐全（`make check-strings` 绿）；`PRIVACY.md`、`CONTRIBUTING.md`、`CHANGELOG.md`、README、`docs/QA-CHECKLIST.md`「截图」章节。
  - **PM 追加（设计文档 §9）**：有标注时 Esc 需按两次；Tab / 滚轮在重叠窗口间逐层切换；空格进入纯净窗口截图（⌥ 单击不带阴影）。

**v0.2 验收标准**

- [ ] 全新 macOS 14 与 macOS 26 用户账户：brew 与 DMG 两种方式均只出现一次 Gatekeeper 确认，5 分钟内完成授权并成功直接粘贴。
- [ ] `spctl` 显示 `source=Notarized Developer ID`，`xcrun stapler validate` 通过；`lipo -archs build/Cubby.app/Contents/MacOS/Cubby` 为 `x86_64 arm64`。
- [ ] 系统语言分别为英文 / 简体中文时跑完 `docs/QA-CHECKLIST.md`：无中文残留、无截断；`check-no-cjk.sh` 通过。
- [ ] 旧 `history.json`（无版本号）无损加载；高版本文件不被覆盖。
- [ ] 用 ad-hoc 与 Developer ID 交替安装后，应用能识别失效授权并引导修复成功。
- [ ] CI 全绿、Core 覆盖率 ≥ 95%；打 tag 后自动产出 draft release，Publish 后 tap 自动更新。
- [ ] GitHub Community Standards 100%；README 中英文齐全。
- [ ] 截图第一阶段通过 `docs/SCREENSHOT-DESIGN.md` §7.1（M1–M3）与 §9 的全部验收项；`docs/QA-CHECKLIST.md`「截图」一节在 macOS 14 与 macOS 26 各跑一遍。

**依赖与并行**

```
T01 ─┬─ T02 国际化 ───────────────┬─ T09 README/截图 ─┐
     ├─ T03 数据版本号             │                   │
     ├─ T04 授权修复（文案按 T02）─┘                   ├─ v0.2 发布
     ├─ T05 诊断 / 隐私、T10 检查更新                  │
     ├─ T11 截图与标注 M1 → M2 → M3（文案按 T02）      │
     └─ T06 CI ── T07 签名公证流水线 ── T08 tap ───────┘
```

T02–T06、T10、T11 可并行；关键路径 T01 → T06 → T07 → T08（首次公证调试不确定性最大，应最早启动）。T11 由三人并行推进、工作量不计入 13 人日，需单独跟踪；它的 README 配图并入 T09。

### 阶段 v0.3：效率补齐（约 18 人日）

交互约定：所有新 UI 都是面板内浮层；⌥ 系列表示「变体 / 批量」；⌘A / C / V / X 留给搜索框。esc 新顺序：浮层 → 预览 → 多选 → 搜索 → 关闭面板。有未保存修改的状态要按两次 esc 才退出，队列不会被 esc 清掉，底栏始终显示当前这一层 esc 会做什么。

- [ ] **T0.3-01 按时间自动清理**（1d）：Core `removingOlder(than:)`。`HistorySettingsPane.swift` 首个 Section 放 `Picker("Keep history for")`（`.menu` 样式，选项 1 天 / 7 天 / 30 天 / 90 天 / 1 年 / 永久，默认「永久」，保证升级后不静默删数据）；footer 注明「与数量上限任一达到即清理，收藏不受影响」；改短会立即删除记录时，弹 `confirmationDialog` 显示将删除的条数，取消则回滚选项。
- [ ] **T0.3-02 多选 + 合并粘贴**（2.5d）：Core `ClipSelection`、`ClipMerger`；`PanelViewModel.swift`、`ClipCardView.swift`、`PanelFooter.swift`。`⇧↑` / `⇧↓` 扩选，⌘ 点击切换单项；卡片显示序号徽章，序号即合并顺序；底栏显示「已选 3 项 · ↩ 合并粘贴 · ⌥↩ 加入队列」。含图片时禁用合并并说明原因；分隔符在通用设置里选。
- [ ] **T0.3-03 粘贴队列**（2.5d，依赖 02）：Core `PasteQueue`；`PasteService.swift`、`ClipboardMonitor.swift`（跳过自写入）、`HotKeyManager.swift`。`⌥↩` 入队、`⌥⌫` 清空，列表顶部固定「队列 2/5」条带，再次呼出面板时自动选中队首；「粘贴下一项」全局热键可选，默认不绑定；菜单栏图标显示剩余数。
- [ ] **T0.3-04 ⌘K 动作浮层 + 文本转换**（2d）：Core `TextTransform`；新 `Views/ActionMenuOverlay.swift`（可输入过滤，↑↓↩ 选择）。动作列表与卡片右键菜单共用同一数据源。
- [ ] **T0.3-05 编辑后粘贴**（2d，复用 04 的浮层框架）：新 `Views/EditOverlay.swift`。`⌘E` 打开，占据列表区域；编辑区内 ↩ 换行，`⌘↩` 粘贴编辑结果，`⌘S` 另存为新条目、原条目不动。
- [ ] **T0.3-06 Quick Look**（1d）：`ClipPreviewView.swift` 嵌入 `QLPreviewView`。
- [ ] **T0.3-07 导入导出**（2d，依赖 T0.2-03）：Core `HistoryArchive`；`HistorySettingsPane.swift`。
- [x] **T0.3-08 VoiceOver 基线 + 显示偏好适配**（已在 v0.2 完成：卡片可访问元素与动作、减弱动态效果、增强对比度；动态字号仍待做）：`ClipCardView.swift`、`HUDToast.swift`、`PanelView.swift`、`PanelChrome.swift`。
  - 卡片用 `.accessibilityElement(children: .ignore)`，标签为「类型，摘要，来自 App，3 分钟前，已收藏」，选中时加 `.isSelected`；焦点留在搜索框，所以 ↑↓ 切换时用 `AccessibilityNotification.Announcement` 播报（防抖 150ms）；纯图标按钮与键帽补上标签。
  - 降低动态效果：面板改为只淡入。降低透明度：玻璃背景回退为 `windowBackgroundColor`。增强对比度：描边 0.06 → 0.25，选中描边 2pt → 3pt。
  - 颜色卡和代码卡的选中态改为外环 2pt 强调色 + 内环 1pt 黑 / 白双描边，否则底色接近强调色时看不出选中。
  - 验收：Accessibility Inspector 的 Audit 无警告。
- [ ] **T0.3-09 应用层 ViewModel 单测**（2d）：`Tests/CubbyTests/`（或拆 `CubbyUI` target，见问题 6）。
- [ ] **T0.3-10 ⌃J / ⌃K、诊断包 zip**（1d）：`Sources/CubbyCore/Panel/PanelCommand.swift`、`Services/Diagnostics.swift`。

验收：连续粘贴 10 条到 TextEdit、备忘录、Chrome 表单顺序正确无丢失；VoiceOver 可独立完成「搜索 → 选择 → 粘贴」；ViewModel 测试 ≥ 30 个；新增 Core 逻辑覆盖率 ≥ 95%。
并行：01、04、06、07、08 相互独立；02 → 03；04 → 05；09 可与全部并行。

### 阶段 v1.0：组织与集成（约 22 人日）

- [ ] **T1.0-01 自定义 / 智能列表**（5d，需 schema v2）：Core `ClipList`、`ClipFilter` 扩展。`PanelHeader.swift` 分类栏最左侧加列表胶囊「全部历史 ▾」：`⌘L` 打开列表切换浮层，`⌘D` 加入列表，`⌘0` 回到全部。「收藏」改为内置列表，⌘P 不变。智能列表规则在设置窗口新增的「列表」页编辑，面板内不放表单。
- [x] **T1.0-02 OCR 搜索**（已提前到 v0.2 完成，未升级 schema）：`ClipItem.recognizedText` + `ImageTextIndexer`（Core）+ 预折叠搜索索引；设置 › 历史「搜索图片中的文字」默认开，关闭即清除。卡片「含文字」角标留待后续。
- [ ] **T1.0-03 片段模板**（3d，依赖 01）：Core `TemplateRenderer`。
- [ ] **T1.0-04 URL Scheme**（1d）+ **AppIntents spike**（2d）：`Info.plist` `CFBundleURLTypes`、`AppDelegate.swift`、新 `Intents/`。
- [ ] **T1.0-05 Raycast / Alfred**（1d，依赖 04）：独立仓库或 `integrations/`。
- [ ] **T1.0-06 链接标题 opt-in**（1.5d）、**音效**（0.25d）、**VoiceOver 审计**（1d）。
- [ ] **T1.0-07 进官方 homebrew-cask**（0.5d，达到门槛后）；**Sparkle 2**（2d，取决于问题 1）。
- [ ] **T1.0-08 SQLite + FTS5 迁移**（L，**仅当**触发条件成立：5000 条历史时逐字搜索 > 50 ms，或单次保存 > 100 ms）。
- [ ] **T1.0-09 截图第二阶段**（依赖 T0.2-11；逐项评估见 `docs/SCREENSHOT-DESIGN.md` §7.2，复杂度沿用该表，不计入 22 人日）：
  - ~~**OCR 文字索引**~~：已提前到 v0.2 完成（见 T1.0-02）；剩余「含文字」角标。
  - **按住 ⌥ 识别 UI 元素**（S–M）：hovering 时按住 `⌥` 切换到元素模式，截取按钮、列表项等控件的边框；需要辅助功能权限，未授权时 ⌥ 无效果并在 tooltip 说明；默认行为不变。
  - ~~**从历史贴图**~~：已在 v0.2 完成（卡片右键「Pin to Screen」，`⇧⌘P`）。
  - **恢复上次选区**（S）：hovering 阶段 `⌘Z` 恢复本次运行中上一次的选区，重启后不保留；键位已在第一阶段预留。
  - **长截图（滚动拼接）暂不做**（L）：需要借助辅助功能权限合成滚动事件，再做图像拼接，要处理固定页眉、懒加载、弹性回弹，Electron 与 WKWebView 的行为又各不相同，失败模式多、维护成本高。先观察需求量；如果要做，作为独立的「Capture Window Content」工具，只支持可通过辅助功能滚动的 `NSScrollView`。

验收：Shortcuts 应用中可见并运行 3 个 Intents（或记录不可行结论并以 URL Scheme 替代）；OCR 在 M1 上单张 4K 截图 < 1 秒且可关闭；在历史中输入截图里的文字能搜到该截图，未授权辅助功能时按住 ⌥ 不影响默认的窗口识别；连续 2 周无 P0 / P1 未关闭 Issue；官方 cask 合并或已记录未达门槛。

## 五、风险与缓解

| 风险 | 影响 | 概率 | 缓解 |
| --- | --- | --- | --- |
| 签名或 bundle ID 变化导致辅助功能「假开启」（改名 + 切换到 Developer ID 必然发生一次） | 高 | 高 | 发布始终同一 Team 的 Developer ID（其 designated requirement 绑定 Team ID，证书续期不影响）；T0.2-04；dev 构建用 `.dev` bundle ID；README FAQ |
| 公开仓库发布流水线的密钥泄露或被 PR 滥用 | 高 | 低 | Environment 审批 + 仅 `v*` tag；PR 不接触 secrets；action 固定 SHA；PAT 最小权限 |
| 公证失败阻塞首发（时间戳、hardened runtime、嵌套代码） | 中 | 中 | 先本地跑通；`notarytool log`；保留本地 `make release` 兜底 |
| 国际化大改（~250 处）引入回归、残留中文、英文溢出；catalog 未拷入 .app 时英文系统仍显示中文 | 中 | 中 | CJK 守卫、`build-app.sh` 编译 catalog、伪本地化、在英文系统跑 QA 清单 |
| v0.3 浮层叠加后连按 esc 丢失编辑内容或多选顺序 | 中 | 中 | 有破坏性的状态需按两次 esc；队列只能显式清空；底栏提示当前 esc 的作用 |
| JSON 无版本号导致未来降级覆盖数据 | 高 | 低 | T0.2-03 版本号 + 拒绝覆盖高版本 |
| CI 依赖 Xcode 26 SDK，runner 镜像变动 | 中 | 中 | 固定镜像与 Xcode 路径 |
| AppIntents 在纯 SPM 构建下不生效 | 中 | 高 | v1.0 前 spike；兜底 URL Scheme |
| 链接标题 / OCR / 同步与「隐私优先」定位冲突 | 高 | 中 | 默认关闭、本地处理、`PRIVACY.md` 明示、网络白名单守卫 |
| 屏幕录制权限体验：授权后常需重开应用；ad-hoc 构建每次重建授权失效；macOS 15+ 周期性确认弹窗期间采集挂起 | 中 | 高 | 首次截图时才申请，引导窗明说可能需要重开；1.5 秒轮询状态；采集 2 秒超时并用 HUD 说明原因；贡献者用固定的自签名证书；详见 `docs/SCREENSHOT-DESIGN.md` §6 |
| 单人维护、开源后 Issue 激增 | 中 | 中 | Issue 模板强制诊断信息；Discussions 分流；README 写明「不做」清单 |

## 需要进一步明确的问题

### 问题 1：自动更新方案

- 方案 A（推荐）：v0.2 自研手动检查更新（默认不联网），v1.0 再评估 Sparkle。优点：零依赖、约 1 人日；缺点：需手动替换 app。
- 方案 B：首发即集成 Sparkle 2。优点：体验最好；缺点：打破零依赖，首发多约 2 人日，多一个密钥。
- 方案 C：不做，只靠 Homebrew 与 GitHub Watch。优点：最简单；缺点：DMG 用户长期停留旧版本。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 方案 C
[ ] 其他方案：______________
```

### 问题 2：是否做 iCloud 同步

- 方案 A（推荐）：1.0 之前不做，之后按需求再议。优点：守住本地隐私定位、避免 L 级工作量；缺点：与 Paste / PasteNow 有功能差距。
- 方案 B：v1.x 用 `CKSyncEngine` + `encryptedValues` 实现。优点：多设备；缺点：需 provisioning profile，贡献者无法本地构建同步版，冲突与配额问题。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 其他方案：______________
```

### 问题 3：最低系统版本

- 方案 A（推荐）：保持 macOS 14。优点：覆盖面广，`CKSyncEngine` 等已可用；缺点：Vision 需用旧 `VNRecognizeTextRequest`。
- 方案 B：提升到 macOS 15。优点：可用 Swift 化 Vision `RecognizeTextRequest`、减少 `#available`；缺点：丢失 Sonoma 用户。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 其他方案：______________
```

### 问题 4：存储引擎

- 方案 A（推荐）：继续 JSON + 版本号，按 T1.0-08 的性能指标触发迁移。优点：KISS；缺点：大历史下整体重写成本随条数增长。
- 方案 B：v1.0 直接迁移 SQLite + FTS5。优点：为列表 / OCR 打好基础；缺点：L 级、迁移风险、`ClipHistory` 不可变值模型需改为仓储模式。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 其他方案：______________
```

### 问题 5：是否上架 Mac App Store

- 方案 A（推荐）：1.0 前不上架。
- 方案 B：1.0 后作为付费支持渠道（开源免费 + MAS 付费），`CUBBY_MAS` 条件编译。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 其他方案：______________
```

### 问题 6：应用层测试的代码组织

- 方案 A：保持单一可执行 target，测试用 `@testable import Cubby`。优点：改动最小；缺点：依赖 SPM 对可执行 target 的测试支持，需 spike。
- 方案 B（推荐）：拆出 library target `CubbyUI`（ViewModel 与服务），可执行 target 只留 `main.swift`。优点：边界清晰、测试稳定；缺点：一次性移动文件约 0.5 人日。

```
请选择您偏好的方案，或提供其他建议：
[ ] 方案 A
[ ] 方案 B
[ ] 其他方案：______________
```

## 用户反馈区域

请在此区域补充您对整体规划的意见和建议：

```
用户补充内容：

---

---

---

```
