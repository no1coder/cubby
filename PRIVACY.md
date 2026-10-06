# Privacy

[English](#english) · [简体中文](#简体中文)

## English

_Applies to Cubby 0.2 and later. Changes to this policy are recorded in [CHANGELOG.md](CHANGELOG.md)._

### Summary

Cubby does not collect, upload or share any data. There are no accounts, no analytics, no telemetry, no crash reporting and no ads. Your clipboard history stays on your Mac.

The one exception is a service you set up yourself: if you choose a large language model for translation (of screenshots or clipboard items), the text you translate is sent to that service. See [Network access](#network-access).

### What Cubby stores on your Mac

Everything lives in `~/Library/Application Support/Cubby`:

| Item | Contents |
| --- | --- |
| `history.json` | Text, links and colors you copied; the RTF / HTML versions of rich text; for copied files, their paths (not the files themselves); the name and bundle ID of the app you copied from; the time of copying; whether an item is a favorite; and translations of items you translated |
| `Images/` | Images you copied, and translated versions of images you translated |

- The folder can only be opened by your macOS user (permissions 0700), and the files can only be read by you (0600).
- The folder is excluded from Time Machine backups.
- Cubby does not add its own encryption. Turn on FileVault to encrypt the disk at rest.
- History is limited to the number of items you choose in Settings › History. Favorites don't count toward the limit.
- Translations are kept with the item they belong to and are deleted with it. **Settings › Translation › Clear All Translations…** deletes all of them.

Your settings (shortcuts, panel position, ignored apps, screenshot folder, translation engine, provider, base URL, model, clipboard translation options, the target language you chose for each app you paste into, the latest version found by the update check, and so on) are stored in `~/Library/Preferences/io.github.no1coder.Cubby.plist`. They contain no clipboard content and no API keys.

If you set up a large language model for screenshot translation, its API key is stored in your login Keychain, not in these files. See [Screenshot translation](#screenshot-translation).

### What Cubby does not record

- Content that other apps mark as concealed, transient or auto-generated, following the [nspasteboard.org](http://nspasteboard.org) conventions. Password managers use these markers.
- Anything copied in apps in your Ignored Apps list (Settings › Privacy). By default this list includes 1Password, Bitwarden, KeePassXC, Keychain Access and Passwords.
- Text that looks like a secret, such as API keys, private keys and JWTs. This is on by default and can be turned off in Settings › Privacy. It is a best-effort check and cannot recognize every format.
- Anything copied while recording is paused.

Text that looks like a secret is also never sent to a large language model for translation unless you confirm it, and text that looks like a secret in an image is never sent.

### Network access

Cubby connects to the network only in the two cases below. The automatic update check is an option you control: it is ticked by default on the welcome screen of a new install, and you can turn it off at any time. Translation with a large language model happens only when you ask for it, with a service you set up yourself.

**Checking for updates**

- **Request:** `GET https://api.github.com/repos/no1coder/cubby/releases/latest`
- **When:** when you click **Check for Updates**, and once a day if the automatic check is on (at launch when a check is due, then whenever a day has passed while Cubby is running or after your Mac wakes; after a failed check, Cubby waits an hour before trying again, or until it is next launched). On a new install, **Remind me about new versions** on the welcome screen is ticked by default and turns the automatic check on; untick it to keep it off. Cubby doesn't check until you close the welcome screen. On an install upgraded from an earlier version, the automatic check stays off unless you turn it on or answer **Remind Me** when Cubby asks once in the panel. If you had already turned on the weekly check in Cubby 0.2, it stays on and now runs once a day. Turn it off at any time with **Check for updates automatically** in Settings › General.
- **What is read:** only the version number of the latest release and the address of its release page. Cubby keeps them in its settings, so it can show that a new version is available without going online again.
- **What is sent:** a standard HTTPS request. Like any web request, it reveals your IP address and a user agent to GitHub. It contains no identifiers and no clipboard content. GitHub's handling of such requests is covered by the [GitHub Privacy Statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).

**Screenshot translation with a large language model** (Cubby 0.2 and later, macOS 26)

- **When:** only when you translate a screenshot (the **Translate** button or <kbd>⇧⌘T</kbd>) while the engine in Settings › Translation is a large language model, and when you click **Refresh** or **Test Connection** in that pane. The default engine, System Translation, runs on your Mac and sends nothing.
- **Where:** only to the base URL you configured, for example `api.deepseek.com`. Settings shows the host, and the translation bar always shows which engine is in use. HTTPS is required; plain HTTP is allowed only for `localhost`, `127.0.0.1` and `::1`. Redirects to another host are refused, so your API key is never forwarded anywhere else. A saved key is tied to the address it was saved for: if you change the base URL to another host (including another region of the same provider), Cubby doesn't send the old key and asks you to enter one for the new address.
- **What is sent:** the text recognized in the selection, split into blocks, together with the target language, the detected source language, the model name and your API key (in the `Authorization` header). When the text is long, it is sent in several requests, and each later request also repeats up to 3 blocks from the end of the previous one as context. All of this text comes from the selection. **Test Connection** sends only the word "Hello"; **Refresh** sends only the key. Like any web request, each request also reveals your IP address and the default macOS user agent (Cubby's name and build number plus the versions of the system's networking components, for example `Cubby/1 CFNetwork/… Darwin/…`) to the service.
- **What is never sent:** the image, text under mosaic, text that looks like a secret (API keys, tokens and similar), and anything from your clipboard history.
- The service you chose handles the text under its own privacy policy. Cubby draws its reply on the screenshot as plain text and never follows instructions or links in it. Cubby's logs record only counts, durations and HTTP status codes, never the text, the translation or the key.

**Clipboard translation with a large language model** (Cubby 0.2 and later, macOS 26)

- **When:** only while the engine in Settings › Translation is a large language model, and only when you translate an item in the panel: <kbd>⌘T</kbd> (the translation card), <kbd>⌥↩</kbd> (translate and paste), holding <kbd>⌥</kbd> on an item, or **Translate** in an item's right-click menu. While the translation card is open it follows your selection, and an item you stay on for 0.6 seconds is translated too. A translation you already have is shown from your Mac without sending anything. **Translate text when you copy it** never uses a large language model.
- **Where:** the same base URL, with the same rules, as screenshot translation. The translation card shows the engine and the host the text was sent to.
- **What is sent:** the text of the item you translate, split into paragraphs, together with the target language, the detected source language, the model name and your API key. For rich text, bold text and link text are marked up; link addresses are replaced with placeholders and are never sent, inline code is replaced with placeholders and isn't sent, and code blocks aren't sent. The check for text that looks like a secret covers exactly this text, including rich-text content that isn't in the item's plain text. For an image, the text recognized in it is sent, not the image. Long text is split into several requests with up to 3 paragraphs of context, as for screenshots.
- **What is never sent:** link addresses; text that looks like a secret, unless you confirm it for that item each time (a confirmation applies only to the service shown when you gave it); text that looks like a secret in an image, which can't be confirmed; and the other items in your history.
- Cubby shows the reply as plain text with the item's formatting and puts the original link addresses back on your Mac. A translated image is kept only in `Images/` with its item; Cubby writes no temporary copies.

Cubby does not download or install updates by itself: **View & Download** opens the release page in your default browser. Opening a link from your history with <kbd>⌘O</kbd> hands it to your default browser; Cubby does not fetch link previews or titles. macOS itself may contact Apple to verify the app's notarization. That is system behavior, not something Cubby does.

### Permissions

| Permission | What Cubby uses it for |
| --- | --- |
| Clipboard access (macOS 15.4 and later) | Reading what you copy so it can be added to your history |
| Accessibility | Sending <kbd>⌘V</kbd> to the frontmost app when you choose to paste. Cubby does not use it to read other apps' windows or content. |
| Screen Recording (only for screenshots) | Capturing your screen when you take a screenshot. See [Screenshots](#screenshots). |
| Login item (optional) | Starting Cubby when you log in, if you enable it in Settings › General |

The global shortcuts (open the panel, take a screenshot) are registered through the standard macOS hot key API. Cubby does not monitor your keystrokes.

### Screenshots

- **When the screen is captured.** Cubby uses the Screen Recording permission only when you start a screenshot yourself: with the screenshot shortcut, **Take Screenshot** in the menu bar icon's menu, or the camera button in the panel. It never captures at launch or in the background. It asks for the permission only when you take your first screenshot, or when you click **Grant Access** next to Screen Recording in Settings › Privacy.
- **The frozen image stays in memory.** While you select and annotate, the captured image of your screen exists only in memory. It is never written to disk, and it is discarded as soon as the screenshot ends. Canceling leaves no trace.
- **Only your choice is kept.** Something is written only when you finish, save, pin, extract text or pick a color: the image goes to the clipboard, to a file in the folder you chose (Settings › Screenshots), or to a pinned window on screen; extracted text and picked color values go to the clipboard as text. All of these are also added to your history like anything you copy, unless recording is paused. Text and color values also follow the "Don't record likely secrets and tokens" setting. Pinned windows disappear when Cubby quits.
- **Text recognition is local.** Extracting text from a screenshot uses Apple's Vision framework on your Mac. Nothing is uploaded.
- Saved files are marked as screenshots for Finder and Spotlight. Cubby adds no other information to them.

### Screenshot translation

Screenshot translation is available on macOS 26 and later.

- **System Translation** (the default) uses Apple's Translation framework on your Mac. The first time you translate a language, macOS asks whether to download its language pack; downloading is always your choice. Language packs are managed in System Settings › General › Language & Region › Translation Languages.
- **Large language models** receive only the text described under [Network access](#network-access).
- **API keys** are stored in your login Keychain as generic passwords (service `io.github.no1coder.Cubby.translation`, one account per provider, such as `deepseek`), together with the address they were saved for. They are never written to preferences, history or logs. Settings shows only the last four characters, and **Remove** deletes the Keychain item. You can also delete them in Keychain Access.
- The translated screenshot is handled like any other screenshot: nothing is kept until you finish, save or pin it.

### Clipboard translation

Clipboard translation is available on macOS 26 and later. It uses the engine and API key from Settings › Translation.

- **Translations stay with the item.** Each translation is saved in your local history file with the item it belongs to (up to 3 languages per item), and a translated image is saved in `Images/`. Search also looks at translations. They are deleted with the item, and **Settings › Translation › Clear All Translations…** deletes all of them.
- **Copying or pasting a translation doesn't add it to your history.** Only **Save as New Item** (<kbd>⌘S</kbd>) does, and it follows **Pause Recording** and "Don't record likely secrets and tokens" like anything you copy.
- **Translate text when you copy it** is off by default. When you turn it on, new text items are translated with System Translation on your Mac, only for languages you've already downloaded. It never downloads a language, never uses a large language model and never goes online. It skips links, code and text that looks like a secret, and it stops while recording is paused or Low Power Mode is on.
- The target language you choose for an app you paste into is stored in your settings as that app's bundle ID and a language code.

### Text in images

To let you find images by the text in them, Cubby recognizes text in images in your history on your Mac using Apple's Vision framework. Nothing is uploaded. Recognized text is kept only in your local history file (up to 10,000 characters per image) and never written to logs; text that looks like a secret or token isn't saved. Recognition pauses while recording is paused. Turn this off in **Settings › History › Search text in images**, which also deletes all recognized text.

### Diagnostic information

**Settings › About › Copy Diagnostic Info** copies a plain-text summary to your clipboard: Cubby version and build, macOS version, chip, install location, signing information, permission status, number of items and size of the data folder. It never includes clipboard content, and it is not sent anywhere. You decide whether to paste it into a bug report.

### Deleting your data

- **One item:** select it in the panel and press <kbd>⌘⌫</kbd>.
- **All history:** Settings › History, or **Clear History…** in the menu bar icon's right-click menu. Favorites are kept.
- **All translations:** Settings › Translation › **Clear All Translations…**. Your history is kept.
- **Everything:** quit Cubby, then run:

  ```sh
  rm -rf ~/Library/Application\ Support/Cubby
  defaults delete io.github.no1coder.Cubby
  tccutil reset All io.github.no1coder.Cubby
  ```

  If you saved API keys for screenshot translation, remove them in Settings › Translation before quitting, or delete the items named `io.github.no1coder.Cubby.translation` in Keychain Access.

  If you installed with Homebrew, `brew uninstall --zap --cask cubby` removes the app and its data.

### Contact

Questions about privacy: open an [issue](https://github.com/no1coder/cubby/issues/new/choose). To report a privacy or security problem privately, follow [SECURITY.md](SECURITY.md).

---

## 简体中文

_适用于 Cubby 0.2 及以后版本。本政策的变更记录在 [CHANGELOG.md](CHANGELOG.md) 中。_

### 概述

Cubby 不收集、不上传、不分享任何数据。没有账户、统计、遥测、崩溃上报，也没有广告。你的剪贴板历史只保存在你的 Mac 上。

唯一的例外是你自己配置的服务：如果你为翻译（截图或剪贴板条目）选择了大模型，要翻译的文字会发送到该服务。详见[网络访问](#网络访问)。

### 本机存储的内容

所有数据位于 `~/Library/Application Support/Cubby`：

| 项目 | 内容 |
| --- | --- |
| `history.json` | 复制的文本、链接和颜色；富文本的 RTF / HTML 版本；复制文件时记录其路径（不复制文件本身）；复制时所在应用的名称和 bundle ID；复制时间；是否收藏；你翻译过的条目的译文 |
| `Images/` | 复制的图片，以及你翻译过的图片的译后版本 |

- 目录仅限你的 macOS 用户访问（权限 0700），文件仅限你读取（0600）。
- 目录排除在 Time Machine 备份之外。
- Cubby 不额外加密数据。建议开启 FileVault 对磁盘进行加密。
- 历史条数受「设置 › 历史」中的上限约束，收藏不计入上限。
- 译文随所属条目保存、随条目删除；「设置 › 翻译 › 清除全部译文…」可删除全部译文。

设置（快捷键、面板位置、排除的应用、截图存储位置、翻译引擎、服务商、接入地址、模型名、剪贴板翻译选项、按粘贴目标应用记住的目标语言、更新检查查到的最新版本号等）保存在 `~/Library/Preferences/io.github.no1coder.Cubby.plist`，不含任何剪贴板内容，也不含 API Key。

如果你为截图翻译配置了大模型，其 API Key 保存在登录钥匙串中，而不是上述文件里。详见[截图翻译](#截图翻译)。

### 不会记录的内容

- 其他应用按 [nspasteboard.org](http://nspasteboard.org) 约定标记为机密、临时或自动生成的内容。密码管理器会使用这些标记。
- 在排除列表（设置 › 隐私）中的应用里复制的内容。默认列表包含 1Password、Bitwarden、KeePassXC、钥匙串访问和「密码」。
- 疑似密钥的文本，如 API Key、私钥、JWT。该选项默认开启，可在「设置 › 隐私」中关闭。这是尽力而为的检测，无法识别所有格式。
- 暂停记录期间复制的内容。

疑似密钥的文本也不会在未经你确认的情况下发送到大模型翻译；图片中的疑似密钥从不发送。

### 网络访问

Cubby 只在以下两种情况下联网。自动检查更新是一个由你决定的选项：新安装时欢迎页默认勾选，可随时关闭。使用大模型翻译只在你要求时进行，发往你自己配置的服务。

**检查更新**

- **请求：** `GET https://api.github.com/repos/no1coder/cubby/releases/latest`
- **时机：** 你点击「检查更新」时；开启自动检查后每天一次（启动时到期即检查，之后在 Cubby 运行期间或 Mac 从睡眠中唤醒后，满一天再检查；检查失败时等一小时再重试，或到下次启动时再试）。新安装时，欢迎页上的「有新版本时提醒我」默认勾选，会开启自动检查；取消勾选即保持关闭。关闭欢迎页之前不会检查。从旧版本升级的安装，除非你自己开启，或在面板询问时（只问一次）选择「提醒我」，自动检查保持关闭；在 Cubby 0.2 中已开启每周检查的，保持开启并改为每天一次。随时可以在「设置 › 通用」中关闭「自动检查更新」。
- **读取内容：** 只读取最新正式版的版本号和发布页地址。Cubby 把它们保存在设置中，之后不必再联网也能提示有新版本。
- **发送内容：** 标准 HTTPS 请求。与任何网络请求一样，GitHub 能看到你的 IP 地址和 User-Agent。请求中不含任何标识符或剪贴板内容。GitHub 对此类请求的处理适用 [GitHub 隐私声明](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)。

**使用大模型翻译截图**（Cubby 0.2 及以后，macOS 26）

- **时机：** 仅当「设置 › 翻译」中的引擎为大模型、且你翻译截图（点「翻译」按钮或按 <kbd>⇧⌘T</kbd>）时，以及你在该页点击「刷新」或「测试连接」时。默认引擎「系统翻译」在本机完成，不发送任何内容。
- **发往何处：** 只发往你配置的接入地址，例如 `api.deepseek.com`。设置页会显示主机名，翻译条上也始终显示正在使用的引擎。必须使用 HTTPS；只有 `localhost`、`127.0.0.1` 与 `::1` 可以使用 HTTP。拒绝重定向到其他主机，你的 API Key 不会被转发到别处。保存的 API Key 与保存时的地址绑定：把接入地址改到其他主机（包括同一服务商的其他地域）后，Cubby 不会发送原来的 Key，而是提示你为新地址重新填写。
- **发送内容：** 选区中识别出的文字（按块拆分），以及目标语言、检测到的源语言、模型名和你的 API Key（位于 `Authorization` 请求头）。文字较长时分多次请求发送，后一次请求还会附带上一次末尾最多 3 块文字作为上下文；这些文字都来自选区。「测试连接」只发送单词 "Hello"；「刷新」只发送 API Key。与任何网络请求一样，服务方还能看到你的 IP 地址和 macOS 默认的 User-Agent（包含 Cubby 的名称与构建号，以及系统网络组件的版本，例如 `Cubby/1 CFNetwork/… Darwin/…`）。
- **绝不发送：** 图片、被马赛克遮住的文字、疑似密钥的文字（API Key、令牌等），以及剪贴板历史中的任何内容。
- 你选择的服务按其自身的隐私政策处理收到的文字。Cubby 只把返回内容作为纯文本绘制在截图上，不会执行其中的指令或打开其中的链接。Cubby 的日志只记录数量、耗时与 HTTP 状态码，不记录原文、译文或 API Key。

**使用大模型翻译剪贴板条目**（Cubby 0.2 及以后，macOS 26）

- **时机：** 仅当「设置 › 翻译」中的引擎为大模型、且你在面板中翻译条目时：按 <kbd>⌘T</kbd>（翻译卡）、按 <kbd>⌥↩</kbd>（翻译并粘贴）、在条目上按住 <kbd>⌥</kbd>，或在条目的右键菜单中选「翻译」。翻译卡打开期间会跟随选中项，在某一条上停留 0.6 秒也会翻译该条。已有的译文直接从本机显示，不发送任何内容。「复制外文时自动翻译」从不使用大模型。
- **发往何处：** 与截图翻译相同的接入地址，规则也相同。翻译卡上会显示所用引擎和文字发往的主机名。
- **发送内容：** 所翻译条目的文字（按段落拆分），以及目标语言、检测到的源语言、模型名和你的 API Key。富文本中的粗体和链接文字会以标记形式发送；链接地址换成占位符、从不发送，行内代码换成占位符、不发送，代码块也不发送。疑似密钥的检查针对的正是这些要发送的文字，包括条目纯文本中没有、只在富文本中出现的内容。图片发送的是其中识别出的文字，而不是图片本身。长文本与截图一样分多次请求，并附带最多 3 段上文。
- **绝不发送：** 链接地址；疑似密钥的文字（除非你每次针对该条确认，且确认只对当时显示的服务有效）；图片中的疑似密钥（无法确认发送）；历史中的其他条目。
- Cubby 以纯文本加上条目原有格式显示返回内容，并在本机把原文的链接地址放回。译后的图片只随条目保存在 `Images/` 中，Cubby 不写入任何临时副本。

Cubby 不会自行下载或安装更新：「查看并下载」只是在默认浏览器中打开发布页。用 <kbd>⌘O</kbd> 打开历史中的链接时，由你的默认浏览器打开；Cubby 不抓取链接预览或标题。macOS 可能会联系 Apple 验证应用的公证状态，这属于系统行为，并非 Cubby 发起。

### 权限

| 权限 | 用途 |
| --- | --- |
| 剪贴板读取（macOS 15.4 及以上） | 读取你复制的内容并加入历史 |
| 辅助功能 | 在你选择粘贴时向当前应用发送 <kbd>⌘V</kbd>。Cubby 不会用它读取其他应用的窗口或内容。 |
| 屏幕录制（仅截图时需要） | 在你截图时捕捉屏幕画面，详见[截图](#截图)。 |
| 登录项（可选） | 在「设置 › 通用」中开启后，登录时自动启动 Cubby |

全局快捷键（打开面板、截图）通过 macOS 标准的热键接口注册，Cubby 不监听你的键盘输入。

### 截图

- **何时捕捉屏幕：** 只有你主动截图时（按截图快捷键、菜单栏图标菜单中的「截图」或面板上的相机按钮），Cubby 才会使用屏幕录制权限。启动时和后台从不捕捉。只有在你第一次截图，或在「设置 › 隐私」中点击屏幕录制旁的「去授权」时，才会申请该权限。
- **冻结画面只在内存中：** 选择区域和标注期间，捕捉到的屏幕画面只存在于内存，从不写入磁盘，截图结束后立即丢弃。取消截图不留任何痕迹。
- **只保存你选择的结果：** 只有在你完成、存储、贴图、提取文字或取色时才会写入：图片进入剪贴板、你选择的文件夹（设置 › 截图）中的文件，或屏幕上的贴图窗口；提取的文字与取到的颜色值以文本形式进入剪贴板。这些内容也会像你复制的内容一样加入历史（暂停记录时除外）；文字与颜色值同样遵守「不记录疑似密钥和令牌」设置。贴图在 Cubby 退出时消失。
- **文字识别在本机完成：** 从截图中提取文字使用 Mac 上的 Apple Vision 框架，不上传任何内容。
- 存储的文件会被标记为屏幕截图，便于访达和聚焦归类。Cubby 不会在文件中添加其他信息。

### 截图翻译

截图翻译需要 macOS 26 及以上版本。

- **系统翻译**（默认）使用 Mac 上的 Apple Translation 框架。首次翻译某种语言时，macOS 会询问是否下载语言包，是否下载始终由你决定。语言包在「系统设置 › 通用 › 语言与地区 › 翻译语言」中管理。
- **大模型**只会收到[网络访问](#网络访问)中所述的文字。
- **API Key** 以通用密码的形式保存在登录钥匙串中（服务名 `io.github.no1coder.Cubby.translation`，每个服务商一个账户，例如 `deepseek`），并记录保存时的接入地址。它不会写入偏好设置、历史或日志。设置界面只显示最后四位，点「移除」即删除该钥匙串条目；也可以在「钥匙串访问」中删除。
- 翻译后的截图与其他截图的处理方式相同：只有在你完成、存储或贴图时才会保留。

### 剪贴板翻译

剪贴板翻译需要 macOS 26 及以上版本，使用「设置 › 翻译」中的引擎与 API Key。

- **译文随条目保存。** 每条译文与所属条目一起保存在本地历史文件中（每条最多 3 种语言），译后的图片保存在 `Images/` 中。搜索也会查找译文。译文随条目删除，「设置 › 翻译 › 清除全部译文…」可删除全部译文。
- **复制或粘贴译文不会加入历史。** 只有「存为新条目」（<kbd>⌘S</kbd>）才会，并且与复制的内容一样遵守「暂停记录」与「不记录疑似密钥和令牌」。
- **复制外文时自动翻译**默认关闭。开启后，新复制的文本用本机的系统翻译自动翻译，只适用于已下载的语言；从不下载语言、从不使用大模型，也不联网。链接、代码和疑似密钥的文字不会自动翻译；暂停记录或开启低电量模式时停止。
- 你为粘贴目标应用选择的目标语言以该应用的 bundle ID 与语言代码保存在设置中。

### 图片中的文字

为了能按图中文字搜索图片，Cubby 使用 Apple Vision 在本机识别历史图片中的文字，全程不联网、不上传。识别结果只保存在本地历史文件中（每张最多 10 000 字），不写入日志；疑似密钥或令牌的文字不会保存。暂停记录期间不会识别。可在「设置 › 历史 › 搜索图片中的文字」关闭，关闭后会删除全部已识别的文字。

### 诊断信息

「设置 › 关于 › 复制诊断信息」会把一段纯文本摘要复制到剪贴板：Cubby 版本与构建号、macOS 版本、芯片、安装位置、签名信息、权限状态、条目数与数据目录大小。其中绝不包含剪贴板内容，也不会被发送到任何地方，是否粘贴到问题报告中由你决定。

### 删除数据

- **单条：** 在面板中选中后按 <kbd>⌘⌫</kbd>。
- **全部历史：** 「设置 › 历史」，或菜单栏图标右键菜单中的「清空历史记录…」。收藏会保留。
- **全部译文：** 「设置 › 翻译 › 清除全部译文…」。历史会保留。
- **彻底删除：** 先退出 Cubby，再执行：

  ```sh
  rm -rf ~/Library/Application\ Support/Cubby
  defaults delete io.github.no1coder.Cubby
  tccutil reset All io.github.no1coder.Cubby
  ```

  如果为截图翻译保存过 API Key，请在退出前到「设置 › 翻译」中移除，或在「钥匙串访问」中删除名为 `io.github.no1coder.Cubby.translation` 的条目。

  通过 Homebrew 安装的，`brew uninstall --zap --cask cubby` 会同时删除应用与数据。

### 联系方式

隐私相关问题请提交 [Issue](https://github.com/no1coder/cubby/issues/new/choose)。如需私下报告隐私或安全问题，请按 [SECURITY.md](SECURITY.md) 操作。
