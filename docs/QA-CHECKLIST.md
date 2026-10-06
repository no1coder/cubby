# Release QA Checklist · 发版冒烟清单

Manual smoke test to run before publishing a release draft. Copy this checklist into the release tracking issue and tick items off there.<br>
发布 Release 草稿前执行的手工冒烟测试。请把本清单复制到发版跟踪 Issue 中逐项勾选。

**Rules · 规则**

- Use a **fresh macOS user account** and **demo data only**. Never use real history or real secrets in screenshots or bug reports.<br>
  使用**新建的 macOS 用户账户**，只用**演示数据**。截图和问题报告中不得出现真实历史或真实密钥。
- Run the full list on **macOS 14** and **macOS 26**, on both **Apple silicon** and **Intel** if available.<br>
  在 **macOS 14** 与 **macOS 26** 上各跑一遍；条件允许时覆盖 **Apple 芯片**与 **Intel**。
- Any failure blocks the release until it is fixed or explicitly accepted by the maintainer.<br>
  任一项失败都会阻塞发布，除非修复或由维护者明确接受。

| Field · 字段 | Value · 值 |
| --- | --- |
| Version / build · 版本 / 构建号 | |
| macOS · 系统版本 | |
| Chip · 芯片 | |
| Tester · 测试人 | |
| Date · 日期 | |

## 1. Release artifacts · 发布产物

- [ ] `spctl -a -vvv -t exec build/Cubby.app` reports `source=Notarized Developer ID`.<br>
  `spctl` 输出 `source=Notarized Developer ID`。
- [ ] `xcrun stapler validate dist/Cubby-X.Y.Z.dmg` succeeds.<br>
  `stapler validate` 校验 DMG 通过。
- [ ] `lipo -archs build/Cubby.app/Contents/MacOS/Cubby` prints `x86_64 arm64`.<br>
  `lipo -archs` 输出 `x86_64 arm64`。
- [ ] `SHA256SUMS.txt` matches the DMG and zip (`shasum -a 256 -c SHA256SUMS.txt`).<br>
  `SHA256SUMS.txt` 与 DMG、zip 一致。
- [ ] The release notes match the `## [X.Y.Z]` section of `CHANGELOG.md`, and the version in Settings › About matches the tag.<br>
  Release 说明与 `CHANGELOG.md` 对应段落一致；「设置 › 关于」中的版本号与 tag 一致。

## 2. Installation and Gatekeeper · 安装与 Gatekeeper

- [ ] **Homebrew:** `brew install --cask no1coder/tap/cubby` succeeds and installs `/Applications/Cubby.app`.<br>
  **Homebrew：** 命令成功，`/Applications/Cubby.app` 已安装。
- [ ] **DMG:** the disk image shows only Cubby and an Applications shortcut; dragging Cubby to Applications works.<br>
  **DMG：** 磁盘映像中只有 Cubby 与「应用程序」快捷方式，拖入「应用程序」正常。
- [ ] First launch shows exactly one "downloaded from the Internet" confirmation, with no "damaged" or "unidentified developer" warning. Test once with Wi-Fi off as well.<br>
  首次打开只出现一次「从互联网下载」确认，无「已损坏」「无法验证开发者」提示；断网状态下再验证一次。
- [ ] No Dock icon; the menu bar icon appears.<br>
  不显示 Dock 图标；菜单栏图标出现。

## 3. First launch and permissions · 首次启动与权限

- [ ] The first-launch guide opens automatically with four cards: panel shortcut, clipboard access, Accessibility, and **Take and pin screenshots**. The two permission cards show live status.<br>
  首次启动自动打开引导窗口，共四张卡片：呼出快捷键、读取剪贴板、辅助功能、「截图与贴图」；两张权限卡片实时显示状态。
- [ ] **Take and pin screenshots** card: it shows the current screenshot shortcut (<kbd>⇧⌘2</kbd> by default) in a recorder that can't be turned off; a newly recorded shortcut works right away and also appears in Settings › Screenshots. The card says Screen Recording is asked for at the first screenshot, has no permission button, and the guide never triggers the Screen Recording prompt.<br>
  「截图与贴图」卡片：显示当前截图快捷键（默认 <kbd>⇧⌘2</kbd>），录制框不能设为关闭；新录制的快捷键立即生效，并同步显示在「设置 › 截图」中。卡片说明首次截图时才申请屏幕录制，没有授权按钮，引导窗口也不会触发屏幕录制的系统询问。
- [ ] macOS 15.4 and later, **not yet asked** (fresh account): the clipboard card says "Not allowed yet. Choose “Allow Paste” when asked." with a **Grant Access** button. With something on the clipboard, clicking it shows the macOS prompt right over the guide. With an empty clipboard no prompt appears, and the card says "Copy something first, then click Grant Access again."<br>
  macOS 15.4 及以上，**尚未询问**（新账户）：剪贴板卡片显示「尚未授权，系统询问时请选择“允许粘贴”」和「去授权」按钮。剪贴板有内容时，点击后系统询问直接弹在引导窗口上；剪贴板为空时不弹询问，卡片提示「请先复制任意内容，再点一次“去授权”」。
- [ ] **Ask:** after choosing **Allow Paste** in the prompt, the card updates without a restart to "Set to “Ask”, so macOS will keep asking when you copy", and the button becomes **Open System Settings**. It opens Privacy & Security › Paste from Other Apps (Paste before macOS 26) with Cubby in the list. Meanwhile the panel shows the "Clipboard access isn't allowed" banner and the menu bar icon's menu shows **Allow Clipboard Access…**.<br>
  **询问：** 在系统询问中选择「允许粘贴」后，卡片无需重启即变为「当前为「询问」，复制时会反复弹窗」，按钮变为「打开系统设置」，点击后跳转到「隐私与安全性 › 从其他 App 粘贴」（macOS 26 之前为「粘贴」），列表中有 Cubby。此时面板显示「未允许读取剪贴板」横幅，菜单栏图标菜单中出现「允许读取剪贴板…」。
- [ ] **Allowed:** after setting Cubby to **Allow** there, the guide and Settings › Privacy show "Allowed" without a restart and the button disappears; copying no longer triggers a system prompt; the panel banner and the menu item are gone.<br>
  **允许：** 在该页面将 Cubby 设为「允许」后，引导窗口与「设置 › 隐私」无需重启即显示「已授权」，按钮消失；复制时不再弹出系统询问；面板横幅与菜单项随之消失。
- [ ] Granting Accessibility updates the guide without a restart.<br>
  授予辅助功能后，引导窗口无需重启即更新状态。
- [ ] With Accessibility denied, choosing an item only copies it, and the app explains why.<br>
  未授予辅助功能时，选中条目只复制，且应用给出原因说明。
- [ ] Wording is the same in the guide, Settings › Privacy, panel banners and the Screen Recording window: **Grant Access** only where macOS can ask directly, **Open System Settings** where the change must be made there, and status reads **Allowed** / **Not allowed**.<br>
  引导窗口、「设置 › 隐私」、面板横幅与屏幕录制引导窗口用词一致：只有系统能直接询问时按钮才叫「去授权」，必须到系统设置修改时叫「打开系统设置」；状态为「已授权」/「未授权」。
- [ ] After finishing the guide it does not reappear on the next launch, and it can be reopened with **Setup Guide…** in the menu bar icon's right-click menu.<br>
  完成引导后下次启动不再自动出现，并可从菜单栏图标右键菜单的「设置向导…」重新打开。
- [ ] Under **Launch at login**, the guide shows **Remind me about new versions** ("Reads the latest version number from GitHub once a day"), ticked on a fresh account. Unticking it turns off Settings › General › **Check for updates automatically**, and ticking it turns it back on. While the guide is open, `lsof -i -a -p $(pgrep -x Cubby)` shows no connection to `api.github.com`. Reopening the guide with **Setup Guide…** shows the current setting and doesn't change it.<br>
  引导窗口「登录时自动启动」下方显示「有新版本时提醒我」（每天从 GitHub 读取一次最新版本号），新账户默认勾选。取消勾选后「设置 › 通用 › 自动检查更新」随之关闭，重新勾选则打开。引导窗口打开期间 `lsof -i` 看不到到 `api.github.com` 的连接。用「设置向导…」重新打开时显示当前设置，不会改动它。

## 4. Capturing content · 记录各类内容

- [ ] Plain text from TextEdit, Notes and Terminal.<br>
  来自文本编辑、备忘录、终端的纯文本。
- [ ] Rich text from TextEdit or Pages, and HTML from Safari: pasting keeps the formatting.<br>
  来自文本编辑 / Pages 的富文本与来自 Safari 的 HTML：粘贴后保留格式。
- [ ] A link shows as a link card; <kbd>⌘O</kbd> opens it in the default browser.<br>
  链接显示为链接卡片；<kbd>⌘O</kbd> 用默认浏览器打开。
- [ ] HEX colors such as `#FF8800` and `#abc` show as color cards.<br>
  `#FF8800`、`#abc` 等 HEX 颜色显示为颜色卡。
- [ ] A code snippet shows as a monospaced code card.<br>
  代码片段显示为等宽代码卡。
- [ ] A screenshot copied to the clipboard (<kbd>⌃⇧⌘4</kbd>) shows as an image card with a thumbnail.<br>
  截图到剪贴板（<kbd>⌃⇧⌘4</kbd>）后显示为带缩略图的图片卡。
- [ ] One and several files copied in Finder show as file cards; <kbd>⌘O</kbd> opens them.<br>
  在访达中复制单个与多个文件均显示为文件卡；<kbd>⌘O</kbd> 可打开。
- [ ] Copying the same content again moves it to the top without a duplicate.<br>
  重复复制相同内容时移到最前，不产生重复条目。
- [ ] Each card shows the correct source app icon and relative time.<br>
  卡片显示正确的来源应用图标与相对时间。

## 5. Opening the panel · 呼出面板

- [ ] The default shortcut <kbd>⇧⌘V</kbd> opens the panel and pressing it again closes it.<br>
  默认快捷键 <kbd>⇧⌘V</kbd> 打开面板，再按一次关闭。
- [ ] A shortcut recorded in Settings › General works immediately; if another app already uses it, Cubby shows a message and reverts to the previous shortcut.<br>
  在「设置 › 通用」中录制的新快捷键立即生效；若已被其他应用占用，Cubby 给出提示并恢复为之前的快捷键。
- [ ] Clicking the menu bar icon opens the panel below the icon; right-click and Control-click show the menu.<br>
  左键点击菜单栏图标在图标下方打开面板；右键或 Control 点按显示菜单。
- [ ] Each panel position setting (next to the pointer, below the menu bar icon, center of the screen) places the panel correctly.<br>
  面板位置「鼠标旁」「菜单栏图标下方」「屏幕中央」三种设置均定位正确。
- [ ] The panel opens over a full-screen app, and closes on <kbd>esc</kbd> or a click outside.<br>
  在全屏应用上方也能呼出；按 <kbd>esc</kbd> 或点击面板外关闭。
- [ ] macOS 26 shows the Liquid Glass background; macOS 14 shows the translucent fallback.<br>
  macOS 26 显示 Liquid Glass 背景；macOS 14 显示半透明回退效果。

## 6. Using the panel · 面板操作

- [ ] Typing searches immediately; matches are highlighted; several words must all match; file paths and source app names match too.<br>
  直接输入即搜索；命中高亮；多个关键词需全部命中；文件路径和来源应用名也能搜到。
- [ ] **Search ranking:** copy, in this order, `Notes: the cache hit rate dropped`, then `cache miss, then a hit`, then a line that starts with more than 60 characters of other text and only then contains `hit` and `cache`. Searching `cache hit` lists them in the order copied (exact phrase → first word near the start → the rest), even though the last one is the newest. An image that matches only through its recognized text comes after all text matches.<br>
  **搜索排序：** 依次复制 `Notes: the cache hit rate dropped`、`cache miss, then a hit`，再复制一行开头有 60 个以上其他字符、之后才出现 `hit` 和 `cache` 的文本。搜索 `cache hit` 时按复制顺序排列（整句命中 → 首个关键词靠前 → 其余），尽管最后一条最新。只靠图中识别文字命中的图片排在所有文本命中之后。
- [ ] **Jump and page:** <kbd>⌥↑</kbd> or <kbd>Home</kbd> selects the first item and <kbd>⌥↓</kbd> or <kbd>End</kbd> the last; <kbd>Page Up</kbd> / <kbd>Page Down</kbd> (<kbd>fn↑</kbd> / <kbd>fn↓</kbd> on a laptop keyboard) move 5 items and stop at the first or last item without wrapping. The selected card always scrolls into view.<br>
  **跳首尾与翻页：** <kbd>⌥↑</kbd> 或 <kbd>Home</kbd> 选中第一条，<kbd>⌥↓</kbd> 或 <kbd>End</kbd> 选中最后一条；<kbd>Page Up</kbd> / <kbd>Page Down</kbd>（笔记本键盘为 <kbd>fn↑</kbd> / <kbd>fn↓</kbd>）移动 5 条，到首尾停住，不循环。选中的卡片始终滚动到可见区域。
- [ ] **Pin to screen:** select an image card and press <kbd>⇧⌘P</kbd>. The panel closes and the image appears in the middle of that display at its natural size (large images shrink to fit within 80 % of the screen). It behaves like a pinned screenshot: drag, zoom, opacity, <kbd>⌘C</kbd>, <kbd>⌘S</kbd>, <kbd>esc</kbd>. **Pin to Screen** in the card's right-click menu and in the preview do the same, and no extra history item is added. On a non-image item <kbd>⇧⌘P</kbd> only beeps; if the image file is missing, an "Image file is missing" HUD appears.<br>
  **贴到屏幕：** 选中图片卡按 <kbd>⇧⌘P</kbd>：面板收起，图片以原始大小出现在该显示器中央（大图等比缩小到屏幕的 80 % 以内）。其行为与截图贴图一致：可拖动、缩放、调整不透明度，支持 <kbd>⌘C</kbd>、<kbd>⌘S</kbd>、<kbd>esc</kbd>。卡片右键菜单和预览中的「贴图」效果相同，且不会新增历史条目。对非图片条目按 <kbd>⇧⌘P</kbd> 只发出提示音；图片文件已丢失时显示「图片文件已丢失」HUD。
- [ ] Right-clicking a card shows the shortcut next to each item (Paste ↩, the other format ⇧↩, Copy Only ⌘↩, Preview Space, Open ⌘O, Pin to Screen ⇧⌘P for images, Favorite ⌘P, Delete ⌘⌫), matching the <kbd>?</kbd> help overlay.<br>
  右键点按卡片，每一项右侧显示键位（粘贴 ↩、另一种格式 ⇧↩、仅复制 ⌘↩、预览 空格、打开 ⌘O、图片的贴图 ⇧⌘P、收藏 ⌘P、删除 ⌘⌫），与 <kbd>?</kbd> 帮助浮层一致。
- [ ] Choose **Images**, close the panel and reopen it within 30 seconds: it is still on Images and the search field is empty. Reopening after more than 30 seconds starts on **All**.<br>
  选择「图片」分类后关闭面板，30 秒内再次呼出仍停在「图片」，搜索框为空；超过 30 秒后再呼出回到「全部」。
- [ ] **Previews:** a file card whose file was deleted shows the name struck through with "File no longer exists", and Open / Show in Finder are disabled. A wide image's preview has no large empty bands above and below it; a tall one is capped at the panel height. A color preview footer shows "Opaque", or "Opacity 50%" for `rgba(255, 0, 0, 0.5)`. A link preview footer shows the scheme, the domain and the length, e.g. "https · example.com · 19 characters".<br>
  **预览：** 文件已被删除的文件卡，文件名加删除线并显示「文件已不存在」，「打开」「在访达中显示」置灰。宽图预览上下没有大片留白，竖长图的预览高度以面板高度为上限。颜色预览页脚显示「不透明」，`rgba(255, 0, 0, 0.5)` 显示「不透明度 50%」。链接预览页脚显示协议、域名与长度，例如「https · example.com · 19 个字符」。
- [ ] <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> cycle through the categories; each shows only its type; an empty category shows an empty state.<br>
  <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> 循环切换分类，各分类只显示对应类型，空分类显示空状态。
- [ ] <kbd>Space</kbd> (empty search) and <kbd>⌘Y</kbd> (with search text) toggle the side preview; it follows the selection and never takes keyboard focus.<br>
  <kbd>空格</kbd>（搜索框为空）与 <kbd>⌘Y</kbd>（有搜索词）切换侧边预览；预览随选中项更新，且不抢键盘焦点。
- [ ] <kbd>↩</kbd> pastes into TextEdit, and the footer named TextEdit as the target beforehand.<br>
  <kbd>↩</kbd> 粘贴到文本编辑，且底栏事先显示目标应用为文本编辑。
- [ ] <kbd>⇧↩</kbd> pastes in the other format (rich text becomes plain text, and vice versa after changing the default in Settings).<br>
  <kbd>⇧↩</kbd> 以另一种格式粘贴（富文本变纯文本；在设置中切换默认格式后反之亦然）。
- [ ] <kbd>⌘↩</kbd> copies without pasting.<br>
  <kbd>⌘↩</kbd> 只复制不粘贴。
- [ ] <kbd>⌘1</kbd> – <kbd>⌘9</kbd> paste the matching item; double-click pastes; single click only selects.<br>
  <kbd>⌘1</kbd> – <kbd>⌘9</kbd> 粘贴对应条目；双击粘贴；单击仅选中。
- [ ] Dragging a text, image and file card into TextEdit or Finder works.<br>
  文本、图片、文件卡片均可拖入文本编辑或访达。
- [ ] Switching to another app between opening the panel and pasting does not paste into the wrong app.<br>
  呼出面板后切换到其他应用，不会误粘贴到错误的应用。
- [ ] <kbd>⌘⌫</kbd> deletes the item; the footer offers undo; <kbd>⌘Z</kbd> restores it in the same position.<br>
  <kbd>⌘⌫</kbd> 删除条目，底栏出现撤销提示，<kbd>⌘Z</kbd> 恢复到原位置。
- [ ] <kbd>⌘P</kbd> toggles favorite; favorites appear in the Favorites category and survive the history limit and Clear History.<br>
  <kbd>⌘P</kbd> 切换收藏；收藏出现在「收藏」分类，不受历史上限与清空历史影响。
- [ ] <kbd>esc</kbd> steps back: help → translation card → Pick Words card → preview → search → close. The help overlay (the keyboard button in the footer) lists every shortcut.<br>
  <kbd>esc</kbd> 逐层退出：帮助 → 翻译卡 → 拆词卡 → 预览 → 搜索 → 关闭。<kbd>?</kbd> 帮助浮层列出全部快捷键。
- [ ] <kbd>⌘,</kbd> opens Settings.<br>
  <kbd>⌘,</kbd> 打开设置。
- [ ] **Pick Words:** copy a long message with an address, a phone number, an email and a link. <kbd>⌘B</kbd> opens the card next to the panel (again closes it); pressing and holding the card for half a second and **Pick Words** in its right-click menu do the same, while a single click still only selects, a double-click still pastes and dragging the card out still works. The phone number, the email and the link are single chips. Click, drag across chips (dragging back shrinks the run) and <kbd>⇧</kbd>-click to pick; <kbd>⌘A</kbd> selects all and again clears. <kbd>↩</kbd> pastes the picked words into TextEdit, <kbd>⌘C</kbd> copies them with a "Copied …" toast, and neither adds a history item. On a link, color or file <kbd>⌘B</kbd> beeps with "This item has no text to pick"; with the card open, moving to such an item shows the same message and moving back shows the chips again. <kbd>esc</kbd> closes the card (back to the preview if it was opened from there).<br>
  **拆词：** 复制一段含地址、电话、邮箱与网址的长消息。<kbd>⌘B</kbd> 在面板旁打开拆词卡（再按关闭）；在卡片上按住半秒、右键菜单「拆词」效果相同，同时单击仍只是选中、双击仍粘贴、拖出卡片仍可用。电话、邮箱与网址各是一整块。单击、拖过（往回拖收缩）、<kbd>⇧</kbd> 单击都能选取；<kbd>⌘A</kbd> 全选，再按清空。<kbd>↩</kbd> 把所选粘贴到文本编辑，<kbd>⌘C</kbd> 复制并提示「已复制 …」，二者都不新增历史条目。对链接、颜色、文件按 <kbd>⌘B</kbd> 发出提示音并提示「这个条目没有可拆分的文字」；拆词卡打开时移到这类条目显示同一句话，移回来恢复词块。<kbd>esc</kbd> 关闭拆词卡（从预览切来的回到预览）。

## 7. Settings · 设置

- [ ] **General:** shortcut, panel position, paste behavior (paste directly / copy only) and default paste format take effect immediately. The four groups have titles: Shortcut & Panel, Pasting, Screenshots, Startup & Updates.<br>
  **通用：** 快捷键、面板位置、选中后行为（直接粘贴 / 仅复制）、默认粘贴格式均立即生效。四组各有标题：快捷键与面板、粘贴、截图、启动与更新。
- [ ] **General:** Launch at login starts Cubby after logging out and back in.<br>
  **通用：** 开启登录时启动后，注销再登录 Cubby 自动运行。
- [ ] **History:** lowering the limit trims the oldest non-favorite items; the data folder button reveals the folder in Finder; Clear History asks for confirmation and keeps favorites.<br>
  **历史：** 调低上限会删除最早的非收藏条目；数据目录按钮在访达中显示目录；清空历史需确认且保留收藏。
- [ ] **History › Search text in images, on (default):** take a screenshot of TextEdit showing `QA-OCR-7431`, or copy an image containing it. Within a few seconds, searching `7431` finds the image card. Images already in the history before launch are indexed in the background, starting about 10 seconds after launch. `lsof -i -a -p $(pgrep -x Cubby)` shows no connection during recognition.<br>
  **历史 › 搜索图片中的文字，开启（默认）：** 截取显示 `QA-OCR-7431` 的文本编辑窗口，或复制含这段文字的图片。几秒内搜索 `7431` 即可找到该图片卡。启动前已有的图片在启动约 10 秒后开始在后台识别。识别期间 `lsof -i` 看不到任何连接。
- [ ] **Search text in images, off:** turning it off clears the recognized text: searching `7431` no longer finds the image, and after a few seconds `grep -c '"recognizedText"' ~/Library/Application\ Support/Cubby/history.json` prints `0`. Turning it back on indexes the images again and the search works again. While recording is paused, no new images are recognized.<br>
  **搜索图片中的文字，关闭：** 关闭后清除已识别的文字：搜索 `7431` 不再找到该图片，几秒后 `grep -c '"recognizedText"' ~/Library/Application\ Support/Cubby/history.json` 输出 `0`。重新开启后图片会被重新识别，搜索恢复。暂停记录期间不识别新图片。
- [ ] **Privacy:** permission rows show live status and open the right System Settings page.<br>
  **隐私：** 权限行实时显示状态，并能跳转到正确的系统设置页面。
- [ ] **About:** version is correct; **Check for Updates** reports "up to date" or offers the new release; **Copy Diagnostic Info** output contains no clipboard content.<br>
  **关于：** 版本正确；「检查更新」提示已是最新或给出新版本；「复制诊断信息」的输出不含任何剪贴板内容。
- [ ] **General › Startup & Updates:** the switch reads **Check for updates automatically**, with "Reads the latest version number from GitHub once a day and never uploads any data". On a fresh account it matches the welcome-screen checkbox: on unless you unticked it there.<br>
  **通用 › 启动与更新：** 开关名为「自动检查更新」，说明为「每天从 GitHub 读取一次最新版本号，不上传任何数据」。新账户上与欢迎页的勾选项一致：没有在欢迎页取消勾选即为开启。
- [ ] The Settings window does not scroll and nothing is clipped on any pane.<br>
  设置窗口各页不滚动，内容无截断。

## 8. Privacy · 隐私

- [ ] **Pause** from the menu bar: the icon changes, copies are not recorded; resuming records again. Same from Settings › Privacy.<br>
  从菜单栏**暂停记录**：图标变化，复制内容不被记录；恢复后重新记录。在「设置 › 隐私」中操作同样有效。
- [ ] **Paused banner:** while paused, the panel shows a "Recording paused" banner below the search field, after any permission banners, with **Resume** and no **Not Now**. **Resume** restarts recording and the banner disappears at once; resuming from the menu bar hides it too.<br>
  **暂停横幅：** 暂停期间，面板在搜索框下方显示「已暂停记录」横幅（排在权限类横幅之后），只有「恢复」按钮，没有「稍后」。点「恢复」后立即恢复记录、横幅随即消失；从菜单栏恢复同样会隐藏横幅。
- [ ] **Ignored Apps:** add TextEdit; text copied there is not recorded; remove it and recording resumes.<br>
  **排除应用：** 添加文本编辑后，在其中复制的内容不被记录；移除后恢复记录。
- [ ] **Password managers:** copying a password from the Passwords app (or 1Password / Bitwarden, if installed) is not recorded.<br>
  **密码管理器：** 从「密码」应用（或已安装的 1Password / Bitwarden）复制密码不被记录。
- [ ] **Secret filter:** fake secrets are not recorded, e.g. a line starting with `-----BEGIN PRIVATE KEY-----`, or `ghp_` followed by 36 letters and digits (see `Tests/CubbyCoreTests/Support/FakeSecrets.swift`). With the filter off, they are recorded.<br>
  **密钥过滤：** 伪造的密钥不被记录，例如以 `-----BEGIN PRIVATE KEY-----` 开头的文本，或 `ghp_` 加 36 位字母数字（参考 `FakeSecrets.swift`）。关闭过滤后会被记录。
- [ ] **File permissions:** `ls -la ~/Library/Application\ Support/Cubby` shows `drwx------` for the folder and `-rw-------` for files.<br>
  **文件权限：** 目录为 `drwx------`，文件为 `-rw-------`。
- [ ] **Time Machine:** `tmutil isexcluded ~/Library/Application\ Support/Cubby` reports `[Excluded]`.<br>
  **Time Machine：** `tmutil isexcluded` 输出 `[Excluded]`。
- [ ] **Network:** with **Check for updates automatically** off, from launch through normal use, `lsof -i -a -p $(pgrep -x Cubby)` shows no connections, and a connection to `api.github.com` appears only after clicking **Check for Updates**. With it on, the only other connection is to `api.github.com` when a check is due: at launch or later, at most once a day (a failed check is retried no sooner than an hour later), and never while the welcome screen is open.<br>
  **网络：** 关闭「自动检查更新」时，从启动到正常使用期间 `lsof -i` 看不到任何连接，只有点击「检查更新」后才出现到 `api.github.com` 的连接。开启时，唯一多出的连接是检查到期时到 `api.github.com` 的连接：启动时或之后，每天最多一次（检查失败至少一小时后才重试），欢迎页打开期间不会出现。

## 9. Screenshots · 截图

Set up overlapping TextEdit, Safari and Finder windows and add a Chinese input method (Pinyin). Start in a user account where Cubby has never been granted Screen Recording.<br>
准备相互重叠的文本编辑、Safari 与访达窗口，并添加中文输入法（拼音）。从未给 Cubby 授予过屏幕录制的用户账户开始。

**Permission · 权限**

- [ ] Launching Cubby and using the panel never asks for Screen Recording, and the first-launch guide only mentions it on the screenshot card, without a status or button. Settings › Privacy shows a **Screen Recording** row: "Not allowed. Only needed for screenshots." with **Grant Access**.<br>
  启动 Cubby、使用面板时都不会申请屏幕录制，首次启动引导只在截图卡片中提及，没有状态和按钮。「设置 › 隐私」显示「屏幕录制」行：「未授权，仅截图时需要」和「去授权」按钮。
- [ ] Not allowed: the first <kbd>⇧⌘2</kbd> shows the macOS permission prompt and Cubby's "Allow Screen Recording to take screenshots" window together, and no overlay appears. Later attempts show only Cubby's window.<br>
  未授权时：第一次按 <kbd>⇧⌘2</kbd> 同时出现系统权限弹窗与 Cubby 的「截图需要屏幕录制权限」窗口，不出现截图覆盖层；之后再按只出现 Cubby 的窗口。
- [ ] **Open System Settings** opens Privacy & Security › Screen & System Audio Recording (Screen Recording on macOS 14) with Cubby in the list; **Not Now** closes the window.<br>
  「打开系统设置」跳转到「隐私与安全性 › 录屏与系统录音」（macOS 14 为「屏幕录制」），列表中有 Cubby；「稍后」关闭窗口。
- [ ] The window says macOS may ask you to quit and reopen Cubby, and its **Quit & Reopen Cubby** link quits Cubby and launches it again; the menu bar icon comes back and history is intact.<br>
  窗口提示 macOS 可能要求退出并重新打开 Cubby；点「退出并重新打开 Cubby」链接后 Cubby 退出并重新启动，菜单栏图标重新出现，历史完好。
- [ ] After turning Cubby on: if Cubby notices the change, its window closes by itself and a HUD says "Press ⇧⌘2 to take a screenshot", without starting a screenshot. If macOS asks to quit and reopen Cubby, do so. Either way, <kbd>⇧⌘2</kbd> then works and Settings › Privacy shows Allowed.<br>
  打开 Cubby 的开关后：若 Cubby 检测到变化，其窗口自动关闭并用 HUD 提示「按 ⇧⌘2 截图」，但不会自动开始截图；若 macOS 要求退出并重新打开 Cubby，照做即可。两种情况下之后 <kbd>⇧⌘2</kbd> 都可用，「设置 › 隐私」显示「已授权」。
- [ ] After turning the permission off again, <kbd>⇧⌘2</kbd> shows Cubby's window again and captures nothing. Clipboard history and direct pasting work whether Screen Recording is granted or not.<br>
  再次关闭权限后，<kbd>⇧⌘2</kbd> 重新显示 Cubby 的引导窗口，不捕捉任何内容。无论是否授予屏幕录制，剪贴板历史与直接粘贴均正常。
- [ ] **Copy Diagnostic Info** includes `Screen recording: granted` or `denied`, the screenshot shortcut and save location, and `Secure input`.<br>
  「复制诊断信息」包含 `屏幕录制: granted` 或 `denied`、截图快捷键与存储位置，以及 `安全键盘输入`。

**Capturing (M1) · 截取**

- [ ] <kbd>⇧⌘2</kbd> in any app freezes the screen with no noticeable delay (target on an M1 Mac with one display: P50 ≤ 150 ms, P95 ≤ 300 ms in the signpost log). If the panel is open, it disappears first and is not in the image. **Take Screenshot** in the menu bar icon's menu (with the shortcut shown next to it) and the camera button in the panel work too.<br>
  在任意应用中按 <kbd>⇧⌘2</kbd>，画面几乎立即冻结（M1 单屏目标：signpost 日志 P50 ≤ 150 ms、P95 ≤ 300 ms）。面板打开时先消失，且不出现在画面中。菜单栏图标菜单中的「截图」（右侧显示快捷键）与面板上的相机按钮同样可用。
- [ ] Hovering highlights the window under the pointer; over the desktop, menu bar or Dock the whole screen is highlighted. A click selects the highlighted window or screen, <kbd>↩</kbd> captures it right away, and <kbd>⌘A</kbd> selects the whole screen.<br>
  悬停时高亮光标下的窗口；在桌面、菜单栏或 Dock 上时高亮整屏。单击选中高亮的窗口或整屏，<kbd>↩</kbd> 直接截取，<kbd>⌘A</kbd> 选中整屏。
- [ ] The outline around a hovered window has rounded corners; the whole-screen outline is square. The hover label shows the app icon, name and pixel size, plus a second line: "Space for clean window" over a single window, "Tab ⇥ cycle · Space clean window" where windows overlap. Over three stacked windows the layer count reads "1 / 3" to "3 / 3" and never counts the whole screen.<br>
  悬停窗口的描边为圆角，整屏描边为直角。悬停标签显示应用图标、名称和像素尺寸，第二行常驻提示：单个窗口为「空格 纯净窗口」，窗口重叠时为「Tab ⇥ 切换层级 · 空格 纯净窗口」。三个窗口叠在一起时层级计数为「1 / 3」到「3 / 3」，不把整屏算作一层。
- [ ] **First-use hint bar:** after `defaults delete io.github.no1coder.Cubby screenshotOnboardingHintCount`, the first three screenshots show "Drag to select · Click for window · Space clean window · Esc to cancel" at the bottom center of the screen; it fades out on the first mouse press. The fourth screenshot doesn't show it.<br>
  **首用引导条：** 执行 `defaults delete io.github.no1coder.Cubby screenshotOnboardingHintCount` 后，前三次截图在屏幕底部居中显示「拖拽框选 · 单击选窗口 · 空格 纯净窗口 · Esc 取消」，第一次按下鼠标后淡出；第四次截图不再显示。
- [ ] Dragging creates a selection; holding <kbd>⇧</kbd> makes it square, <kbd>⌥</kbd> grows it from the center, and <kbd>Space</kbd> moves it.<br>
  拖拽创建选区；按住 <kbd>⇧</kbd> 为正方形，按住 <kbd>⌥</kbd> 从中心扩展，按住 <kbd>空格</kbd> 平移选区。
- [ ] The eight handles and the edges resize the selection, dragging inside moves it, and the arrow keys move it by 1 pt (10 pt with <kbd>⇧</kbd>). The selection never leaves its display. The size label shows pixels (twice the point size on a Retina display).<br>
  8 个手柄和边缘可调整大小，在选区内拖动可移动，方向键移动 1 pt（按住 <kbd>⇧</kbd> 为 10 pt）；选区不会跨出所在显示器。尺寸标签显示像素（Retina 屏为点数的 2 倍）。
- [ ] The magnifier shows a 15 × 15 pixel grid, the position and the HEX color; holding <kbd>⇧</kbd> shows RGB. <kbd>C</kbd> copies the value shown, ends the screenshot and shows a HUD; a HEX color appears in the history as a color card.<br>
  放大镜显示 15 × 15 像素网格、坐标与 HEX 色值；按住 <kbd>⇧</kbd> 显示 RGB。按 <kbd>C</kbd> 复制当前显示的值、结束截图并显示 HUD；HEX 颜色在历史中显示为颜色卡。
- [ ] <kbd>↩</kbd>, <kbd>⌘C</kbd>, a double-click inside the selection and the ✓ button all finish: the frontmost app stays the same, <kbd>⌘V</kbd> right away pastes a PNG at the display's native resolution, and exactly one image card with the source "Screenshot" and the Cubby icon appears in the history.<br>
  <kbd>↩</kbd>、<kbd>⌘C</kbd>、在选区内双击和 ✓ 按钮均可完成：前台应用不变，立即 <kbd>⌘V</kbd> 可粘贴显示器原生分辨率的 PNG；历史中恰好新增一张来源为「截图」、带 Cubby 图标的图片卡。
- [ ] Right-clicking a selection clears it and keeps the annotations; right-clicking with no selection cancels. With nothing drawn, <kbd>esc</kbd> or pressing <kbd>⇧⌘2</kbd> again cancels; once something is drawn, pressing <kbd>⇧⌘2</kbd> again is ignored.<br>
  有选区时右键清除选区、保留标注；无选区时右键取消。未画标注时，<kbd>esc</kbd> 或再按一次 <kbd>⇧⌘2</kbd> 都会取消；画过标注后再按 <kbd>⇧⌘2</kbd> 不起作用。
- [ ] Settings › Screenshots: a new shortcut works immediately; **Off** turns it off (the menu item then shows no shortcut); the panel's shortcut is rejected with "Already used to open the panel", and the screenshot shortcut is rejected for the panel with "Already used for screenshots".<br>
  「设置 › 截图」：新快捷键立即生效；选「关闭」后快捷键失效（菜单项不再显示快捷键）；录制与面板相同的快捷键会被拒绝并提示「已用作呼出快捷键」，为面板录制截图快捷键则提示「已用作截图快捷键」。

**Annotating (M2) · 标注**

- [ ] The toolbar sits below the selection, above it when there's no room, and inside it for a full-screen selection; it never leaves the screen. It uses Liquid Glass on macOS 26 and a translucent material on macOS 14, with no square corners in its shadow. Tooltips show each shortcut. The ✓ Done button is a solid accent-colored button, and the highlight behind the active tool slides to the tool you pick.<br>
  工具栏位于选区下方；下方放不下时在上方，整屏选区时在选区内；始终不超出屏幕。macOS 26 为 Liquid Glass，macOS 14 为半透明材质，投影无直角。tooltip 显示各自的快捷键。✓「完成」为实心强调色按钮；切换工具时，激活底块滑动到新选的工具上。
- [ ] Every tool can be chosen from the toolbar and with <kbd>R</kbd> <kbd>O</kbd> <kbd>A</kbd> <kbd>P</kbd> <kbd>H</kbd> <kbd>M</kbd> <kbd>T</kbd> <kbd>N</kbd>; the same key again or <kbd>V</kbd> returns to the pointer. Check rectangle and ellipse (<kbd>⇧</kbd>: square and circle), the tapered arrow (<kbd>⇧</kbd>: 45° steps), a smooth pen line, a clearly visible highlighter that doesn't get darker where it overlaps itself and leaves the text underneath readable, mosaic that pixelates only the screen image and not other annotations, and numbers with a white outline (visible on dark and colored backgrounds) that count 1, 2, 3 and renumber when one is deleted.<br>
  每个工具都可从工具栏或用 <kbd>R</kbd> <kbd>O</kbd> <kbd>A</kbd> <kbd>P</kbd> <kbd>H</kbd> <kbd>M</kbd> <kbd>T</kbd> <kbd>N</kbd> 选择；再按同一键或按 <kbd>V</kbd> 回到指针。检查矩形与椭圆（<kbd>⇧</kbd>：正方形与圆）、锥形箭头（<kbd>⇧</kbd>：按 45° 吸附）、平滑的画笔线条、醒目且自身重叠处不加深、底下文字仍清晰的荧光笔、只打码屏幕画面而不影响其他标注的马赛克，以及带白色描边（深色、彩色背景上也清晰）、按 1、2、3 编号且删除一个后自动补位的序号。
- [ ] Text tool: typing Chinese with Pinyin works and the candidate window appears above the overlay; <kbd>↩</kbd> adds a line; <kbd>esc</kbd> while composing only closes the candidates; <kbd>esc</kbd>, <kbd>⌘↩</kbd> or a click outside commits the text, and an empty box is discarded; clicking an existing text with the text tool edits it again.<br>
  文字工具：可用拼音输入中文，候选窗显示在覆盖层之上；<kbd>↩</kbd> 换行；组字时按 <kbd>esc</kbd> 只关闭候选窗；<kbd>esc</kbd>、<kbd>⌘↩</kbd> 或点击外部提交文字，空文本框被丢弃；用文字工具点击已有文字可重新编辑。
- [ ] The style bar offers three sizes and eight colors (mosaic has sizes only). Each tool remembers its own style, also after quitting and reopening Cubby.<br>
  样式条提供 3 档大小与 8 种颜色（马赛克只有大小）；每个工具分别记住自己的样式，退出并重新打开 Cubby 后仍保留。
- [ ] In pointer mode, clicking an annotation selects it; it can then be dragged, moved with the arrow keys, recolored or resized from the style bar, and deleted with <kbd>⌫</kbd>.<br>
  指针模式下单击标注即选中，之后可拖动、用方向键微移、在样式条中改色或改大小，按 <kbd>⌫</kbd> 删除。
- [ ] <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> undo and redo annotations (at least 100 steps); dragging an annotation is undone in one step.<br>
  <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> 撤销 / 重做标注（至少 100 步）；拖动一次标注只需撤销一次。
- [ ] Annotations drawn outside the selection stay visible but are cropped from the result. After a right-click clears the selection the annotations stay, and a new selection keeps them in place; the result matches the final selection.<br>
  画到选区外的标注保持显示，但导出时被裁掉。右键清除选区后标注仍在，重新框选后位置不变；导出结果与最终选区一致。

**Saving, pinning and text (M3) · 存储、贴图与文字**

- [ ] <kbd>⌘S</kbd> (and the toolbar's Save button) hides the overlay and opens a save dialog on the display with the selection. It only allows PNG, can create folders, suggests a name like `Cubby 2026-09-27 01.23.45.png` (editable), and starts in the folder used last time (the first time: the folder from Settings, or the macOS screenshot folder). **Save** writes the file (the dialog asks before replacing an existing file), `mdls -name kMDItemIsScreenCapture <file>` reports `1`, the screenshot is added to the history once, a HUD names the folder, the clipboard doesn't change, and the app you were using is in front again. The next dialog starts in that folder, and Settings shows it.<br>
  <kbd>⌘S</kbd>（以及工具栏的「存储」按钮）隐藏覆盖层，并在选区所在的显示器上弹出存储对话框：只允许 PNG，可新建文件夹，建议文件名形如 `Cubby 2026-09-27 01.23.45.png`（可修改），起始目录为上次使用的文件夹（第一次为设置中的文件夹或系统截图文件夹）。点「存储」写入文件（同名文件由对话框确认替换），`mdls -name kMDItemIsScreenCapture <文件>` 输出 `1`，截图加入历史且只有一条，HUD 显示文件夹名，剪贴板不变，截图前的应用回到前台。下次对话框从该文件夹开始，设置中也显示为该文件夹。
- [ ] **Cancel** in the save dialog brings the overlay back exactly as it was: the selection, every annotation and undo / redo. You can keep drawing, then <kbd>↩</kbd> copies as usual. While the dialog is open, the screenshot shortcut brings the dialog to the front instead of starting a new screenshot.<br>
  在存储对话框中点「取消」，覆盖层原样回来：选区、全部标注和撤销 / 重做都在，可以继续标注，按 <kbd>↩</kbd> 照常复制。对话框打开期间按截图快捷键会把对话框提到前面，不会开始新截图。
- [ ] With **Ask where to save each time** turned off in Settings › Screenshots, <kbd>⌘S</kbd> saves straight to the macOS screenshot folder (it follows `defaults write com.apple.screencapture location <folder>`) or the folder chosen in Settings, without a dialog. A name that already exists gets ` 2` instead of being overwritten. If the folder is missing or read-only, the file goes to the Desktop with a notice. The note under the folder row changes with the switch.<br>
  在「设置 › 截图」中关闭「每次存储前询问位置」后，<kbd>⌘S</kbd> 不弹对话框，直接存入系统截图文件夹（跟随 `defaults write com.apple.screencapture location <目录>`）或设置中选择的文件夹；重名时追加 ` 2` 而不覆盖；文件夹不存在或不可写时存储到桌面并提示。文件夹一行下方的说明随开关变化。
- [ ] <kbd>⌘P</kbd> pins the screenshot in place at actual size. The pin can be dragged, zoomed around the pointer with the scroll wheel or a pinch (10% – 400%, <kbd>⌘0</kbd> for 1:1), and set to 100 / 80 / 60 / 40 % opacity from its right-click menu (Copy, Save…, Opacity, Close). <kbd>⌘C</kbd> and <kbd>⌘S</kbd> work; a double-click, <kbd>esc</kbd> or <kbd>⌘W</kbd> closes it. Several pins can be open at once, and they disappear when Cubby quits.<br>
  <kbd>⌘P</kbd> 把截图原位、原尺寸贴在屏幕上。贴图可拖动，可用滚轮或双指捏合以光标为中心缩放（10% – 400%，<kbd>⌘0</kbd> 恢复 1:1），可在右键菜单（拷贝、存储…、不透明度、关闭）中设为 100 / 80 / 60 / 40 % 不透明度。<kbd>⌘C</kbd>、<kbd>⌘S</kbd> 可用；双击、<kbd>esc</kbd> 或 <kbd>⌘W</kbd> 关闭。可同时存在多个贴图，退出 Cubby 后消失。
- [ ] The next screenshot includes pinned windows but never the panel, the Settings window or a HUD.<br>
  下一次截图的画面中包含贴图窗口，但不包含面板、设置窗口或 HUD。
- [ ] <kbd>⌘T</kbd> on mixed Chinese and English text gives a result within about 1 second (a 1080p area on an M1 Mac): the text is copied in reading order and added to the history as a text card, and annotations are not part of the recognition. With no text, an orange "No text found" HUD appears. `lsof -i -a -p $(pgrep -x Cubby)` shows no connection during recognition.<br>
  对中英混排内容按 <kbd>⌘T</kbd>，约 1 秒内出结果（M1、1080p 区域）：文字按阅读顺序复制，并作为文本卡加入历史；标注不参与识别。没有文字时显示橙色 HUD「没有识别到文字」。识别期间 `lsof -i` 看不到任何连接。
- [ ] Saved and pinned screenshots are added to the history too, each exactly once.<br>
  存储和贴图的截图同样加入历史，且各只有一条。

**Added decisions (design §9) · 追加决定**

- [ ] **Esc twice:** with at least one annotation, the first <kbd>esc</kbd> keeps everything and shows "Press Esc again to discard"; the second <kbd>esc</kbd> discards the screenshot. Any other key press or click in between cancels the warning, so the next <kbd>esc</kbd> warns again. Without annotations a single <kbd>esc</kbd> cancels.<br>
  **Esc 按两次：** 至少有一个标注时，第一次 <kbd>esc</kbd> 保留全部内容并提示「再按一次 Esc 放弃截图」，第二次 <kbd>esc</kbd> 才放弃截图；两次之间有任何其他按键或点击都会解除待确认，下一次 <kbd>esc</kbd> 重新提示。没有标注时按一次 <kbd>esc</kbd> 即取消。
- [ ] **Overlapping windows:** with the pointer over several stacked windows, <kbd>⇥</kbd> or scrolling down highlights the next window behind, ending at the whole screen without wrapping around; <kbd>⇧⇥</kbd> or scrolling up goes back, stopping at the frontmost window. Moving the pointer within the same stack keeps the layer; moving to a different stack starts from the top again. A quick trackpad flick doesn't keep skipping layers after your fingers lift. Click, <kbd>↩</kbd> and double-click act on the highlighted layer.<br>
  **重叠窗口：** 光标放在多层窗口重叠处，<kbd>⇥</kbd> 或向下滚动高亮下一层窗口，最深到整屏，不循环；<kbd>⇧⇥</kbd> 或向上滚动返回，最浅到最上层窗口。在同一叠窗口内移动光标保持当前层，移到另一叠时从最上层重新开始。触控板快速轻扫后，松手的惯性不会继续跳层。单击、<kbd>↩</kbd> 与双击作用于当前高亮的那一层。
- [ ] **Clean window capture:** over a window, <kbd>Space</kbd> switches to window mode: the magnifier hides and the highlight changes style. A click or <kbd>↩</kbd> captures only that window, complete even where other windows cover it, with transparent rounded corners and its shadow (paste into Preview to check); <kbd>⌥</kbd>-click captures it without the shadow. The result is copied and added to the history right away, with no annotation step. <kbd>Space</kbd> again leaves window mode, <kbd>Space</kbd> over the whole screen does nothing, stepping to the whole screen with <kbd>⇥</kbd> leaves window mode, and <kbd>esc</kbd> cancels.<br>
  **纯净窗口截图：** 悬停在窗口上按 <kbd>空格</kbd> 进入窗口模式：放大镜隐藏，高亮换成窗口模式样式。单击或 <kbd>↩</kbd> 只截该窗口，被其他窗口遮挡的部分也完整，保留透明圆角与阴影（粘贴到预览中检查）；按住 <kbd>⌥</kbd> 单击则不带阴影。结果直接复制并加入历史，不进入标注。再按 <kbd>空格</kbd> 退出窗口模式；目标为整屏时按 <kbd>空格</kbd> 无效；用 <kbd>⇥</kbd> 切到整屏时自动退出窗口模式；<kbd>esc</kbd> 取消截图。

**Screenshot translation (macOS 26+, docs/TRANSLATION-DESIGN.md) · 截图翻译**

- [ ] On macOS 26 the toolbar has a **Translate** button after Extract Text (tooltip "Translate (⇧⌘T)"); on macOS 14 / 15 there is no button and <kbd>⇧⌘T</kbd> does nothing.<br>
  macOS 26 上工具栏「提取文字」之后有「翻译」按钮（tooltip「翻译 (⇧⌘T)」）；macOS 14 / 15 上没有该按钮，<kbd>⇧⌘T</kbd> 无效。
- [ ] Select a page of English UI text and press <kbd>⇧⌘T</kbd>: the translation bar appears on the far side of the toolbar (6 pt gap, right-aligned) with "Recognizing text…", recognized blocks shimmer, then blocks fade in one by one while the bar counts "Translating 5/14". When done the bar shows the language pair, the engine (a cloud icon for cloud engines), Original | Translation, Compare, Copy Translation and "Hold Space to see the original". With a drawing tool active, the style bar sits after the translation bar.<br>
  框选一屏英文界面按 <kbd>⇧⌘T</kbd>：翻译条出现在工具栏远离选区的一侧（间距 6 pt、右对齐），显示「正在识别文字…」，识别出的块上有流光；随后译文逐块淡入，条内计数「正在翻译 5/14」。完成后显示语言对、引擎（云端引擎带云图标）、「原文 | 译文」、卷帘对比、复制译文与「按住空格看原文」。激活画图工具时样式条排在翻译条之后。
- [ ] Translated blocks replace the original text in place; numbers, code, URLs, text already in the target language and text under a mosaic stay original, and text under a mosaic is never sent (check with the engine's logs or a proxy for a cloud engine).<br>
  译文原位替换原文；数字、代码、URL、已是目标语言的文字与马赛克下的文字保持原样，马赛克下的文字不会发送（大模型引擎可用代理或服务端日志核对）。
- [ ] Holding <kbd>Space</kbd> shows the original with a small "Original · Release Space for the translation" chip; releasing it brings the translation back. Hovering a translated block for 400 ms outlines it and shows its original text in a bubble (up to 6 lines).<br>
  按住 <kbd>空格</kbd> 显示原文并有「原文 · 松开空格回到译文」小标签，松开恢复译文。指针在某块译文上停留 400 ms，该块出现描边并在气泡中显示原文（最多 6 行）。
- [ ] **Compare** shows a white divider with a round handle in the middle of the selection, "Original" on the left and "Translation" on the right. Dragging the handle (the pointer becomes ↔) moves it; after dragging, <kbd>←</kbd> / <kbd>→</kbd> nudge it (<kbd>⇧</kbd> for bigger steps). Moving or resizing the selection puts it back in the middle. VoiceOver reads it as an adjustable slider.<br>
  「卷帘对比」在选区中间显示白色分隔线与圆形拖柄，左侧「原文」、右侧「译文」。拖动拖柄（指针为左右箭头）移动分隔线；拖过之后 <kbd>←</kbd> / <kbd>→</kbd> 微调（<kbd>⇧</kbd> 大步）。移动或缩放选区后分隔线回到中间。VoiceOver 下是可调节的滑块。
- [ ] Done / Save / Pin export the version chosen by Original | Translation (<kbd>⇧⌘T</kbd> also switches it); holding Space and Compare never change the export. With Translation selected, <kbd>⌘T</kbd> copies the translated text instead of running OCR.<br>
  完成 / 存储 / 贴图导出「原文 | 译文」所选的版本（<kbd>⇧⌘T</kbd> 同样切换它）；按住空格与卷帘对比不影响导出。开关在「译文」时 <kbd>⌘T</kbd> 复制译文而不是再做 OCR。
- [ ] **Copy Translation** copies the blocks in reading order, one per line, with untranslated blocks in the original; a "Copied translation" HUD appears, the overlay stays open, and the text joins the history (not while recording is paused).<br>
  「复制译文」按阅读顺序逐块一行复制，未翻译的块用原文；出现「已复制译文」提示，覆盖层保持打开，文字加入历史（暂停记录时不加入）。
- [ ] <kbd>⌘Z</kbd> removes the whole translation in one step (annotations drawn later are undone first), <kbd>⇧⌘Z</kbd> brings it back complete. Choosing another language from the language menu re-translates the same blocks without recognizing again, is one more undo step, and is remembered for the next screenshot.<br>
  <kbd>⌘Z</kbd> 一步撤销整个翻译（之后画的标注先被撤销），<kbd>⇧⌘Z</kbd> 完整恢复。在语言选单中换语言：沿用已识别的块重新翻译、不重新识别，算一步撤销，下次截图沿用该语言。
- [ ] <kbd>esc</kbd> while recognizing or translating cancels only the translation ("Translation cancelled"); the next <kbd>esc</kbd> follows the usual rules. With a finished translation the first <kbd>esc</kbd> asks to press again.<br>
  识别或翻译进行中按 <kbd>esc</kbd> 只取消翻译（提示「已取消翻译」），再按 <kbd>esc</kbd> 按原有规则处理。已有译文时第一次 <kbd>esc</kbd> 提示再按一次。
- [ ] Failures show a short reason in the bar: with the cloud engine not set up, **Open Settings** hides the overlay and opens Settings › Translation; after closing Settings the overlay returns and translates automatically. The screenshot shortcut during that time neither starts a new screenshot nor cancels. With a missing language pack, **Download Languages** opens the system download sheet the same way. Network, rate-limit and server errors offer **Retry**. If the network drops mid-way, the arrived blocks stay, the bar says "Some text wasn't translated", and Retry sends only the missing blocks.<br>
  失败时条内显示简短原因：大模型未配置时点「去设置」，覆盖层隐藏并打开「设置 › 翻译」，关闭设置后覆盖层回来并自动重试；期间按截图快捷键既不开始新截图也不取消。缺少语言包时「下载语言」同样打开系统的下载界面。网络、频率、服务端错误给「重试」。翻译中途断网：已到达的译文保留，条内提示「部分内容未翻译」，重试只发送未完成的块。
- [ ] Moving or growing the selection after translating keeps the translation anchored on screen; when the new selection includes untranslated area the bar offers "Selection changed · Translate Again".<br>
  翻译后移动或放大选区，译文仍锚定在屏幕内容上；新选区包含未识别的区域时，翻译条提示「选区已变化 · 重新翻译」。
- [ ] With the system engine nothing leaves the Mac (`lsof -i -a -p $(pgrep -x Cubby)` shows no connection); with a cloud engine only the recognized text of the sent blocks goes to the configured host.<br>
  使用系统翻译时没有任何网络连接（`lsof -i` 核对）；使用大模型时只有被发送块的文字发往所配置的主机。

**Environments · 环境**

- [ ] **Two displays with different scaling** (for example a 2× built-in display and a 1× external display arranged to its upper left): both freeze; a selection stays on one display; the result has the right size and pixels on each display; the magnifier, size label and toolbar stay on the current display.<br>
  **两台缩放不同的显示器**（例如 2× 内建屏 + 排列在其左上方的 1× 外接屏）：两屏同时冻结；选区只在一块屏幕内；各屏导出的尺寸与像素正确；放大镜、尺寸标签与工具栏不超出当前显示器。
- [ ] Connecting or disconnecting a display during a screenshot cancels it with a "Screen layout changed" HUD, and no overlay is left behind.<br>
  截图过程中插拔显示器会取消截图并显示「屏幕布局已变化，截图已取消」HUD，不残留覆盖层。
- [ ] **Spaces and full screen:** on another desktop (Space) the screenshot shows that desktop; over full-screen Safari the overlay appears, and typing Chinese in a text annotation works there. A system alert or notification during a screenshot doesn't close the overlay, and clicking the overlay gives it the keyboard back.<br>
  **多桌面与全屏：** 在其他桌面（Space）上截图，画面是该桌面的内容；在全屏 Safari 上方也能出现覆盖层，并能在文字标注中输入中文。截图过程中出现系统弹窗或通知不会关闭覆盖层，点击覆盖层后键盘恢复。
- [ ] **Chinese input method:** with Pinyin as the current input source, tool keys (<kbd>R</kbd>, <kbd>A</kbd>, <kbd>T</kbd> …) and other shortcuts still work outside a text box and don't open the candidate window.<br>
  **中文输入法：** 当前输入法为拼音时，在文字框之外，工具键（<kbd>R</kbd>、<kbd>A</kbd>、<kbd>T</kbd> 等）与其他快捷键仍然生效，不会弹出候选窗。
- [ ] **Pause recording:** while paused, copying, saving, pinning, extracting text and picking colors all work, but nothing is added to the history; after resuming, screenshots are added again.<br>
  **暂停记录：** 暂停期间复制、存储、贴图、提取文字与取色均可用，但都不加入历史；恢复后截图重新加入历史。
- [ ] **Dark and light:** the toolbar, style bar, magnifier, handles, size label, HUDs, pinned windows, the permission window and the Screenshots settings are legible in both appearances; switching appearance during a screenshot updates the toolbar.<br>
  **深色与浅色：** 两种外观下，工具栏、样式条、放大镜、手柄、尺寸标签、HUD、贴图窗口、权限引导窗口与截图设置都清晰可读；截图过程中切换外观，工具栏随之更新。
- [ ] **Language:** in English and in Simplified Chinese, all screenshot text (menu item, tooltips, HUDs, permission window, settings, pin menu) is translated and nothing is truncated.<br>
  **语言：** 英文与简体中文下，截图相关文字（菜单项、tooltip、HUD、权限引导窗口、设置、贴图菜单）均已翻译且无截断。
- [ ] **Secure input:** with Terminal › Secure Keyboard Entry turned on, <kbd>⇧⌘2</kbd> still starts a screenshot. If it doesn't, record it in the release issue and check that the menu item and the panel button still work and that Copy Diagnostic Info shows `Secure input: on`.<br>
  **安全键盘输入：** 在终端中开启「安全键盘输入」后，<kbd>⇧⌘2</kbd> 仍能开始截图；若不能，记录在发版 Issue 中，并确认菜单项与面板按钮可用、「复制诊断信息」显示 `安全键盘输入: on`。

## 10. Language, appearance and accessibility · 语言、外观与可访问性

- [ ] System language **English**: no Chinese text anywhere (menu bar menu, panel, preview, help, settings, guide, alerts); nothing truncated.<br>
  系统语言为**英文**：菜单、面板、预览、帮助、设置、引导、弹窗中无中文残留，无截断。
- [ ] System language **Simplified Chinese**: everything is translated; nothing truncated.<br>
  系统语言为**简体中文**：全部已翻译，无截断。
- [ ] Plural forms read correctly (1 item / 2 items).<br>
  复数形式正确（1 item / 2 items）。
- [ ] **Dark** and **light** mode: panel, cards (color, code, image), preview, settings and guide are legible; switching appearance while the panel is open updates it.<br>
  **深色**与**浅色**模式下，面板、各类卡片、预览、设置与引导均清晰可读；面板打开时切换外观能即时更新。
- [ ] **VoiceOver spot check** (<kbd>⌘F5</kbd>): with the panel open, moving to a card reads its source, title and relative time plus "Press Return to paste, or Space to preview."; a deleted file card also says "File no longer exists". VO-Space on a card pastes it, and the Actions rotor offers Favorite (or Unfavorite), Preview, Pick Words (items with text), Pin to Screen (images only) and Delete. In the Pick Words card each chip reads its text, picked chips say "Selected", and VO-Space picks or unpicks a chip. Category tabs read their names and which one is selected; the camera, gear and <kbd>?</kbd> buttons read "Take Screenshot", "Settings" and "Keyboard Shortcuts"; key caps in the help overlay are read as key names ("Shift Return"), not symbols. Searching, choosing and pasting an item works with VoiceOver alone.<br>
  **VoiceOver 抽查**（<kbd>⌘F5</kbd>）：面板打开时移到卡片上，朗读来源、标题、相对时间以及提示「按回车粘贴，按空格预览」；文件已被删除的文件卡另外朗读「文件已不存在」。在卡片上按 VO-空格即粘贴，「操作」转子中有收藏（或取消收藏）、预览、拆词（有文字的条目）、贴图（仅图片）、删除。拆词卡里每个词块朗读其文字，已选的块朗读「已选」，按 VO-空格选取或取消。分类标签朗读名称与选中状态；相机、齿轮与 <kbd>?</kbd> 按钮分别朗读「截图」「设置」「快捷键」；帮助浮层中的键帽按键名朗读（如「Shift Return」），而不是逐个念符号。只用 VoiceOver 也能完成搜索、选择、粘贴。
- [ ] **Reduce Motion** (System Settings › Accessibility › Display): the panel fades in where it is, without dropping into place; the preview appears and changes height without animating; the Pick Words chips appear without fading or scaling and a pressed card doesn't shrink; the help overlay, banners, category highlight and scrolling to the selection change without animation. In the screenshot overlay the toolbar appears without scaling, the active-tool highlight jumps instead of sliding, handles grow without animation, and hints disappear without fading. Turning it off brings the animations back.<br>
  **减弱动态效果**（系统设置 › 辅助功能 › 显示）：面板原地淡入，不再下落；预览出现与高度变化都没有动画；拆词卡的词块直接出现、不淡入不放大，按下卡片不缩小；帮助浮层、横幅、分类高亮与滚动到选中项都直接切换。截图覆盖层中工具栏出现时不缩放，激活工具的底块直接跳到位而不滑动，手柄放大没有动画，提示直接消失而不淡出。关闭该选项后动画恢复。
- [ ] **Increase Contrast** (System Settings › Accessibility › Display): card outlines and secondary text get stronger on all card types, Pick Words chips get an outline, and panel banners get an orange outline; everything stays legible in dark and light mode.<br>
  **增强对比度**（系统设置 › 辅助功能 › 显示）：各类卡片的描边与次要文字更明显，拆词卡的词块加上描边，面板横幅加上橙色描边；深色与浅色模式下均清晰可读。

## 11. Multiple displays · 多显示器

- [ ] With the pointer on the secondary display, the panel opens on that display.<br>
  鼠标位于副屏时，面板在副屏打开。
- [ ] Clicking the menu bar icon on either display opens the panel below that icon.<br>
  在任一显示器上点击菜单栏图标，面板都在该图标下方打开。
- [ ] The preview stays on the same display as the panel and within the visible area.<br>
  预览与面板在同一显示器且不超出可见区域。
- [ ] After disconnecting a display, the panel opens on the remaining one.<br>
  断开一台显示器后，面板在剩余显示器上正常打开。

## 12. Signing changes and permission repair · 签名切换与授权修复

- [ ] Install an ad-hoc source build (`SIGN_IDENTITY=- make install`), grant Accessibility, then install the Developer ID release over it. If direct pasting stops working, Cubby tells you so and its repair steps (select Cubby, click **−**, grant again, or `tccutil reset Accessibility io.github.no1coder.Cubby`) restore direct pasting.<br>
  先安装 ad-hoc 签名的源码构建版并授权辅助功能，再覆盖安装 Developer ID 发布版。若直接粘贴失效，Cubby 应给出提示，按其修复步骤（选中 Cubby 点 **−** 后重新授权，或执行 `tccutil reset`）后恢复直接粘贴。
- [ ] Repeat in the opposite order (release first, then ad-hoc build).<br>
  反向再测一次（先发布版，后 ad-hoc 构建）。
- [ ] Following the README FAQ alone is enough to fix the problem.<br>
  仅按 README 常见问题的说明操作即可修复。

## 13. Upgrade · 升级

- [ ] Install the previous release, create history (all content types), favorites and custom settings (shortcut, position, ignored apps, history limit).<br>
  安装上一个发布版，制造各类型历史、收藏与自定义设置（快捷键、位置、排除应用、上限）。
- [ ] Upgrade with `brew upgrade --cask cubby`, and separately by replacing the app from the new DMG.<br>
  分别通过 `brew upgrade --cask cubby` 与用新 DMG 替换应用的方式升级。
- [ ] After upgrading, history, images, favorites and settings are intact, and both permissions still work without re-granting.<br>
  升级后历史、图片、收藏与设置完好，两项权限无需重新授权即可使用。
- [ ] Check for Updates in the old version finds the new release.<br>
  旧版本的「检查更新」能发现新版本。
- [ ] **Asking once:** upgrade from 0.2.1 or earlier with the weekly check off. The first time you open the panel, a blue banner asks "Remind you about new versions?". **Remind Me** turns on **Check for updates automatically** and checks once; **No Thanks** leaves it off. Either way it doesn't ask again, also after a relaunch. Upgrading with the weekly check on keeps it on and doesn't ask; changing the switch in Settings before opening the panel also means no question.<br>
  **只问一次：** 从 0.2.1 或更早版本升级，且原来没开每周检查。第一次打开面板时顶部出现蓝色横幅「有新版本时提醒你吗？」。「提醒我」打开「自动检查更新」并检查一次；「不用了」保持关闭。无论选哪个都不再询问，重启后也不会。原来开着每周检查的，升级后保持开启且不询问；打开面板前先在设置中改过开关的，也不会询问。

**Update reminders · 更新提醒**

Use a build whose version is lower than the latest release: set `VERSION` to, for example, `0.1.0`, run `make install`, then restore `VERSION`.<br>
使用版本号低于最新正式版的构建：把 `VERSION` 临时改为例如 `0.1.0`，运行 `make install`，之后改回。

- [ ] Click **Check for Updates…**: the menu bar icon gets a blue dot at its top right, and the right-click menu starts with **Version x.y.z Available…**, which opens the release page. No system notification appears. With VoiceOver, the menu bar icon reads "Cubby, update available".<br>
  点「检查更新…」：菜单栏图标右上角出现蓝点，右键菜单顶部为「新版本 x.y.z 可用…」，点击打开发布页。不出现系统通知。开启 VoiceOver 时，菜单栏图标朗读有可用更新（英文界面为“Cubby, update available”）。
- [ ] The panel shows a blue banner "Version x.y.z is available" with "You're running 0.1.0.", **View & Download** (opens the release page) and **Not Now**. It comes after the orange permission banners and before "Recording paused". Settings › About shows the new version with **View & Download**.<br>
  面板顶部出现蓝色横幅「新版本 x.y.z 可用」，显示「你在用 0.1.0。」以及「查看并下载」（打开发布页）和「稍后」。它排在橙色权限横幅之后、「已暂停记录」之前。「设置 › 关于」显示新版本和「查看并下载」。
- [ ] **Homebrew:** before clicking **Not Now**, create an empty `/opt/homebrew/Caskroom/cubby` folder (`/usr/local/Caskroom/cubby` on Intel; remove it after the test) and relaunch Cubby. The banner says "Run brew upgrade --cask cubby in Terminal to upgrade." with **Copy Upgrade Command**, **Release Notes** and **Not Now**. **Copy Upgrade Command** briefly shows **Copied** and puts `brew upgrade --cask cubby` on the clipboard, and no history item is added. **Release Notes** opens the release page. Settings › About offers the same two buttons.<br>
  **Homebrew：** 在点「稍后」之前，新建空文件夹 `/opt/homebrew/Caskroom/cubby`（Intel 上为 `/usr/local/Caskroom/cubby`，测完删除），然后重新打开 Cubby。横幅提示「在终端运行 brew upgrade --cask cubby 升级。」，按钮为「复制升级命令」「更新内容」「稍后」。「复制升级命令」短暂显示「已复制」，剪贴板中为 `brew upgrade --cask cubby`，历史中没有新增条目。「更新内容」打开发布页。「设置 › 关于」提供同样的两个按钮。
- [ ] **Not Now** hides the banner; it stays hidden after quitting and relaunching Cubby, while the blue dot and the menu item stay.<br>
  「稍后」隐藏横幅，退出并重新打开 Cubby 后仍不显示；蓝点和菜单项保留。
- [ ] With Wi-Fi off, relaunching Cubby shows the blue dot and the menu item right away.<br>
  关闭 Wi-Fi 后重新打开 Cubby，蓝点和菜单项立即出现。
- [ ] After installing a version at least as new as the one found (restore `VERSION` and `make install`, or install the release), the blue dot, the menu item and the banner are gone.<br>
  安装不低于所发现版本的版本后（改回 `VERSION` 并 `make install`，或安装该发布版），蓝点、菜单项和横幅都消失。

## 14. Uninstall · 卸载

- [ ] `brew uninstall --zap --cask cubby` quits Cubby and removes the app, `~/Library/Application Support/Cubby` and `~/Library/Preferences/io.github.no1coder.Cubby.plist`.<br>
  `brew uninstall --zap --cask cubby` 会退出 Cubby 并删除应用、数据目录与偏好设置文件。
- [ ] The manual uninstall commands in the README remove everything, and a fresh install afterwards starts with the first-launch guide and empty history.<br>
  按 README 的手动卸载命令可删除全部内容；之后重新安装会从首次启动引导与空历史开始。

## Sign-off · 签字确认

- [ ] All items pass on every tested configuration, or failures are recorded in the release issue and accepted by the maintainer.<br>
  所有测试配置均通过；如有失败，已记录在发版 Issue 中并由维护者接受。
