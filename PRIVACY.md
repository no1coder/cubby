# Privacy

[English](#english) · [简体中文](#简体中文)

## English

_Applies to Cubby 0.2 and later. Changes to this policy are recorded in [CHANGELOG.md](CHANGELOG.md)._

### Summary

Cubby does not collect, upload or share any data. There are no accounts, no analytics, no telemetry, no crash reporting and no ads. Your clipboard history stays on your Mac.

The one exception is a service you set up yourself: if you choose a large language model for translation (of screenshots or clipboard items), the text you translate is sent to that service. See [Network access](#network-access).

### What Cubby stores on your Mac

Everything lives in `~/Library/Application Support/Cubby/Vault`, and every file in it is encrypted (see [Encryption](#encryption)):

| Item | Contents |
| --- | --- |
| `history.cubby` | Text, links and colors you copied; the RTF / HTML versions of rich text; for copied files, their paths (not the files themselves); the name and bundle ID of the app you copied from; the time of copying; whether an item is a favorite; text recognized in images; link titles; and translations of items you translated |
| `Blobs/` | Images you copied, their rich-text formats and thumbnails, and translated versions of images you translated. File names are derived from a key, not from the content, so they don't reveal what you copied |
| `security-log.cubby` | The address guard's security log (Settings › Security): the time, the kind (for example Ethereum address), a shortened value like `0x5aAe…eAed`, the app in front, and which history item replaced your copy. Never the full value. Entries are kept for 90 days, except the ones that still keep a replaced item blocked |
| `Backups/` | Backups Cubby makes when it upgrades the history format or finds a damaged history file |

`.vault.lock` next to `Vault/` (used so only one copy of Cubby changes the folder at a time) and, if you set a custom data folder with `CUBBY_DATA_DIR`, `vault-id` (a random identifier that tells Cubby which key belongs to the folder) contain no clipboard content.

- The folder can only be opened by your macOS user (permissions 0700), and the files can only be read by you (0600).
- The folder is excluded from Time Machine backups.
- History is limited to the number of items you choose in Settings › History. Favorites don't count toward the limit.
- Translations are kept with the item they belong to and are deleted with it. **Settings › Translation › Clear All Translations…** deletes all of them.

Your settings (shortcuts, panel position, ignored apps, screenshot folder, translation engine, provider, base URL, model, clipboard translation options, the target language you chose for each app you paste into, the latest version found by the update check, and so on) are stored in `~/Library/Preferences/io.github.no1coder.Cubby.plist`. They contain no clipboard content and no API keys.

If you set up a large language model for screenshot translation, its API key is stored in your login Keychain, not in these files. See [Screenshot translation](#screenshot-translation).

### Encryption

Cubby encrypts everything in its data folder that comes from your clipboard. It is always on; **Settings › History › Encryption** shows **On**.

- **What is encrypted:** your history (text, recognized text, translations, link titles and the content hashes used to find duplicates), images, rich-text formats, thumbnails, translated images, the address guard's security log, and backups. Files use AES-256-GCM, which also detects any change to them.
- **What isn't:** your settings in `~/Library/Preferences/io.github.no1coder.Cubby.plist` (they contain no clipboard content), screenshots you save to a folder yourself (those are your own files), and translation API keys (already in the Keychain).
- **Where the key is:** a random 256-bit key stored in your login Keychain as a generic password (service `io.github.no1coder.Cubby.history`). The Keychain trusts only Cubby's code signature to read it. Cubby reads it once at launch and keeps it in memory; Hardened Runtime stops other processes from reading Cubby's memory or injecting code into it.

What it protects against:

- Other apps, scripts and install scripts running as your macOS user quietly reading the data folder. Before, they could read it without any prompt; now they get only encrypted data, and reaching the key goes through the Keychain, which asks you.
- The data folder being zipped, synced to a cloud drive or sent to someone by mistake.
- Using file names to check whether you copied a particular image.

What it doesn't protect against:

- Malware that already has administrator (root) rights, or that has tricked you into giving it your login password: it can unlock your whole login Keychain.
- Apps that read the system clipboard at the moment you copy. That is the system clipboard itself, not Cubby.
- Apps you've given Accessibility or Screen Recording, which can control or see Cubby's windows.
- Copies you hand to other apps (see below).
- Rolling your history back to an older encrypted copy. Encryption keeps the data secret and unaltered, but can't tell whether it's the latest version.
- An app you allowed when the Keychain asked (see [If macOS asks about the key](#if-macos-asks-about-the-key)).

Deleting a file only unlinks it, and on an SSD Cubby can't guarantee that old blocks are overwritten. Keep FileVault on to encrypt the disk at rest, including any unencrypted history left behind by earlier versions.

**Upgrading from an earlier version.** Cubby 0.3.3 and earlier stored history unencrypted in `history.json` and `Images/`. On the first launch after updating, Cubby encrypts them into `Vault/`; the panel shows **Encrypting your history…** and Settings › History shows the progress. The unencrypted files are deleted only after the encrypted copy has been written and read back successfully. If the update is interrupted, Cubby picks up where it left off at the next launch.

**Going back to an earlier version.** Versions 0.3.3 and earlier can't read `Vault/` and start with an empty, unencrypted history. When you update again, the items you copied in the meantime are merged into the encrypted history and the unencrypted files are deleted. Items you deleted or cleared while on the older version aren't deleted from the encrypted history, so they reappear.

**Files handed to other apps.** Dragging an image to Finder lets Finder write the file itself, so no temporary copy is made. When an app needs a file path, for example when you open an image with **Open** (<kbd>⌘O</kbd>, usually in Preview) or drop it on an app that accepts only files, Cubby writes a decrypted copy to `$TMPDIR/Cubby-Shared/`. Those copies can be read by other processes running as your user. Cubby deletes them when it quits and again at its next launch, but not while it runs, so a file you're editing in Preview isn't deleted under you.

**If the key can't be read.** Cubby never deletes encrypted data on its own.

- If reading the key fails (you denied the Keychain prompt, the Keychain is locked, or another error), the history is locked: the panel shows **History is locked** with **Try Again** and **Not Now**, and Settings › History shows the same with **Try Again**. Until then, nothing is written to disk; what you copy is kept in memory only. After **Try Again** succeeds, those items are merged into your history.
- If the key is gone but encrypted history exists (for example after you reset your login Keychain), Cubby renames the folder to `Vault-unreadable-<date>`, keeps it, and starts a new, empty history. Settings › History says so and offers **Show in Finder**. If the key comes back (for example you restore the Keychain), Cubby restores the old history automatically at the next launch.

### If macOS asks about the key

macOS may ask whether an app can use the confidential information `io.github.no1coder.Cubby.history` in your keychain.

- The app name in that prompt can be faked. **Only allow it right after you've installed or updated Cubby, and only when it's Cubby itself asking.** At any other time, or if any other app asks, choose **Deny**.
- Denying never loses data. Cubby goes into the locked state and keeps new copies in memory; click **Try Again** and allow, and they're merged back into your history.
- Releases share a stable signature, so normal updates don't ask. You'll see the prompt once only after running a build with a different signature, for example one you built yourself.

### What Cubby does not record

- Content that other apps mark as concealed, transient or auto-generated, following the [nspasteboard.org](http://nspasteboard.org) conventions. Password managers use these markers.
- Anything copied in apps in your Ignored Apps list (Settings › Privacy). By default this list includes 1Password, Bitwarden, KeePassXC, Keychain Access and Passwords.
- Text that looks like a secret, such as API keys, private keys and JWTs. This is on by default and can be turned off in Settings › Privacy. It is a best-effort check and cannot recognize every format.
- Anything copied while recording is paused.

While the address guard is on (Settings › Security, on by default), Cubby also looks at short text on the clipboard that it doesn't record, including text marked as concealed or transient, to tell whether an address or card number you copied was swapped. This check happens in memory only: that text is never stored, logged or sent anywhere, and Cubby forgets it as soon as you copy something else or turn the guard off.

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
- Cubby shows the reply as plain text with the item's formatting and puts the original link addresses back on your Mac. A translated image is kept only with its item, encrypted in `Vault/Blobs/`; translating writes no temporary copies.

Cubby does not download or install updates by itself: **View & Download** opens the release page in your default browser. Opening a link from your history with <kbd>⌘O</kbd> hands it to your default browser; Cubby does not fetch link previews or titles. macOS itself may contact Apple to verify the app's notarization. That is system behavior, not something Cubby does.

### Permissions

| Permission | What Cubby uses it for |
| --- | --- |
| Clipboard access (macOS 15.4 and later) | Reading what you copy so it can be added to your history |
| Accessibility | Sending <kbd>⌘V</kbd> to the frontmost app when you choose to paste. Cubby does not use it to read other apps' windows or content. |
| Screen Recording (only for screenshots) | Capturing your screen when you take a screenshot. See [Screenshots](#screenshots). |
| Login item (optional) | Starting Cubby when you log in, if you enable it in Settings › General |
| Input Monitoring (optional) | Only if you allow it in Settings › Security: noticing when you press <kbd>⌘C</kbd> or <kbd>⌘X</kbd>, so the address guard can tell a copy you made from a replacement. Cubby checks each key press for those two shortcuts and discards it right away; it never records, stores or logs what you type |

The global shortcuts (open the panel, take a screenshot) are registered through the standard macOS hot key API. Apart from the optional Input Monitoring check above, Cubby does not monitor your keystrokes.

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

- **Translations stay with the item.** Each translation is saved in your local history file with the item it belongs to (up to 3 languages per item), and a translated image is saved, encrypted, in `Vault/Blobs/`. Search also looks at translations. They are deleted with the item, and **Settings › Translation › Clear All Translations…** deletes all of them.
- **Copying or pasting a translation doesn't add it to your history.** Only **Save as New Item** (<kbd>⌘S</kbd>) does, and it follows **Pause Recording** and "Don't record likely secrets and tokens" like anything you copy.
- **Translate text when you copy it** is off by default. When you turn it on, new text items are translated with System Translation on your Mac, only for languages you've already downloaded. It never downloads a language, never uses a large language model and never goes online. It skips links, code and text that looks like a secret, and it stops while recording is paused or Low Power Mode is on.
- The target language you choose for an app you paste into is stored in your settings as that app's bundle ID and a language code.

### Text in images

To let you find images by the text in them, Cubby recognizes text in images in your history on your Mac using Apple's Vision framework. Nothing is uploaded. Recognized text is kept only in your local history file (up to 10,000 characters per image) and never written to logs; text that looks like a secret or token isn't saved. Recognition pauses while recording is paused. Turn this off in **Settings › History › Search text in images**, which also deletes all recognized text.

### Diagnostic information

**Settings › About › Copy Diagnostic Info** copies a plain-text summary to your clipboard: Cubby version and build, macOS version, chip, install location, signing information, permission status, encryption status, number of items and size of the data folder. It never includes clipboard content, and it is not sent anywhere. You decide whether to paste it into a bug report.

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

  If you saved API keys for screenshot translation, remove them in Settings › Translation before quitting, or delete the items named `io.github.no1coder.Cubby.translation` in Keychain Access. To remove the history key too, delete the item named `io.github.no1coder.Cubby.history` in Keychain Access. Do this only after deleting the data folder: without the key, the encrypted history can't be read.

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

所有数据位于 `~/Library/Application Support/Cubby/Vault`，其中每个文件都经过加密（详见[加密](#加密)）：

| 项目 | 内容 |
| --- | --- |
| `history.cubby` | 复制的文本、链接和颜色；富文本的 RTF / HTML 版本；复制文件时记录其路径（不复制文件本身）；复制时所在应用的名称和 bundle ID；复制时间；是否收藏；图片中识别出的文字；链接标题；你翻译过的条目的译文 |
| `Blobs/` | 复制的图片及其富文本格式与缩略图，以及你翻译过的图片的译后版本。文件名由密钥派生而非由内容生成，不会透露你复制了什么 |
| `security-log.cubby` | 地址守护的安全记录（设置 › 剪贴板安全）：时间、类型（如以太坊地址）、缩写的值（如 `0x5aAe…eAed`）、当时的前台应用，以及替换了你复制内容的那条历史。从不保存完整的值。记录保留 90 天，仍在禁止被替换条目的记录除外 |
| `Backups/` | 升级历史格式或发现历史文件损坏时 Cubby 留下的备份 |

`Vault/` 旁边的 `.vault.lock`（保证同一时间只有一个 Cubby 实例修改该目录）以及用 `CUBBY_DATA_DIR` 指定自定义数据目录时的 `vault-id`（一个随机标识，用来找到该目录对应的密钥）不含任何剪贴板内容。

- 目录仅限你的 macOS 用户访问（权限 0700），文件仅限你读取（0600）。
- 目录排除在 Time Machine 备份之外。
- 历史条数受「设置 › 历史」中的上限约束，收藏不计入上限。
- 译文随所属条目保存、随条目删除；「设置 › 翻译 › 清除全部译文…」可删除全部译文。

设置（快捷键、面板位置、排除的应用、截图存储位置、翻译引擎、服务商、接入地址、模型名、剪贴板翻译选项、按粘贴目标应用记住的目标语言、更新检查查到的最新版本号等）保存在 `~/Library/Preferences/io.github.no1coder.Cubby.plist`，不含任何剪贴板内容，也不含 API Key。

如果你为截图翻译配置了大模型，其 API Key 保存在登录钥匙串中，而不是上述文件里。详见[截图翻译](#截图翻译)。

### 加密

Cubby 会加密数据目录中一切由剪贴板内容派生的数据。加密始终开启，「设置 › 历史 › 加密」显示「已开启」。

- **加密的内容：** 历史（文本、识别出的文字、译文、链接标题以及用于去重的内容哈希）、图片、富文本格式、缩略图、译后的图片、地址守护的安全记录与备份。文件使用 AES-256-GCM 加密，任何改动都能被发现。
- **不加密的内容：** `~/Library/Preferences/io.github.no1coder.Cubby.plist` 中的设置（不含剪贴板内容）、你主动保存到文件夹的截图（那是你自己的文件）、翻译 API Key（本来就在钥匙串中）。
- **密钥在哪里：** 一个随机生成的 256 位密钥，以通用密码的形式保存在登录钥匙串中（服务名 `io.github.no1coder.Cubby.history`）。钥匙串只信任 Cubby 的代码签名读取它。Cubby 在启动时读取一次并保存在内存中；Cubby 启用了 Hardened Runtime，其他进程无法读取它的内存或向它注入代码。

能防：

- 同一 macOS 用户下的其他应用、脚本、安装脚本静默读取数据目录。以前它们无需任何提示即可读取；现在只能拿到密文，要拿到密钥必须经过钥匙串，系统会询问你。
- 数据目录被打包、同步到网盘或误传给别人。
- 通过文件名比对确认你是否复制过某张图片。

不能防：

- 已获得管理员（root）权限，或已骗到你登录密码的恶意软件：它可以解开整个登录钥匙串。
- 在你复制的当下读取系统剪贴板的应用。这是系统剪贴板本身，与 Cubby 无关。
- 被授予「辅助功能」或「屏幕录制」权限、能操控或看到 Cubby 窗口的应用。
- 你交给其他应用的副本（见下文）。
- 用较旧的加密文件回滚历史。加密保证数据不被读取和篡改，但无法判断它是不是最新版本。
- 在钥匙串询问中被你点了「允许」的应用（见[系统询问钥匙串密钥时怎么选](#系统询问钥匙串密钥时怎么选)）。

删除文件只是取消链接，在固态硬盘上 Cubby 无法保证旧数据块被覆写。建议继续开启 FileVault 对磁盘进行加密，旧版本留下的未加密历史也因此受到保护。

**从旧版本升级。** Cubby 0.3.3 及更早版本把历史以明文保存在 `history.json` 与 `Images/` 中。更新后首次启动时，Cubby 会把它们加密到 `Vault/`；期间面板显示「正在加密历史…」，「设置 › 历史」显示进度。只有在加密副本写入并读回校验无误后，才会删除未加密的文件。如果过程被中断，下次启动时会接着完成。

**退回旧版本。** 0.3.3 及更早版本无法读取 `Vault/`，会从空的未加密历史开始。再次更新后，这期间复制的条目会合并进加密历史，未加密的文件随后删除。在旧版本中删除或清空的条目不会从加密历史中删除，因此会重新出现。

**交给其他应用的文件。** 把图片拖到访达时由访达自己写入文件，不产生临时副本。当其他应用需要文件路径时（例如用「打开」（<kbd>⌘O</kbd>，通常在「预览」中）打开图片，或拖放到只接受文件的应用），Cubby 会把解密后的副本写入 `$TMPDIR/Cubby-Shared/`。这些副本同一用户下的其他进程可以读取。Cubby 在退出时和下次启动时删除它们，运行期间不删，以免你正在「预览」中编辑的文件被删掉。

**无法读取密钥时。** Cubby 任何情况下都不会自动删除加密数据。

- 如果读取密钥失败（你在询问中点了拒绝、钥匙串已锁定或其他错误），历史会被锁定：面板显示「历史已锁定」横幅以及「重试」「稍后」，「设置 › 历史」显示同样的提示与「重试」。在此之前不会写入磁盘，新复制的内容只保存在内存中；点「重试」成功后，这些条目会合并回历史。
- 如果密钥不见了但加密历史还在（例如重置过登录钥匙串），Cubby 会把该目录改名为 `Vault-unreadable-<日期>` 保留下来，并从空历史重新开始。「设置 › 历史」会说明这一情况并提供「在访达中显示」。如果密钥恢复了（例如还原了钥匙串），下次启动时 Cubby 会自动还原旧历史。

### 系统询问钥匙串密钥时怎么选

macOS 可能会询问某个应用能否使用你钥匙串中的机密信息 `io.github.no1coder.Cubby.history`。

- 询问里的应用名可以伪造。**只有刚安装或更新了 Cubby、而且是 Cubby 自己在问时才允许**；其他任何时候、任何应用来问，一律选「拒绝」。
- 拒绝不会丢数据：Cubby 进入「已锁定」，新复制的内容暂存在内存中；点「重试」并允许后合并回历史。
- 正式版之间签名稳定，正常升级不会出现询问；只有运行过签名不同的版本（例如自己构建的版本）后才会问一次。

### 不会记录的内容

- 其他应用按 [nspasteboard.org](http://nspasteboard.org) 约定标记为机密、临时或自动生成的内容。密码管理器会使用这些标记。
- 在排除列表（设置 › 隐私）中的应用里复制的内容。默认列表包含 1Password、Bitwarden、KeePassXC、钥匙串访问和「密码」。
- 疑似密钥的文本，如 API Key、私钥、JWT。该选项默认开启，可在「设置 › 隐私」中关闭。这是尽力而为的检测，无法识别所有格式。
- 暂停记录期间复制的内容。

地址守护开启时（设置 › 剪贴板安全，默认开启），为了判断你复制的地址或卡号有没有被换掉，Cubby 也会查看剪贴板上不记录的短文本，包括标记为机密或临时的内容。这一检查只在内存里进行：这些文本不会被保存、写入日志或发送到任何地方，你复制别的内容或关闭守护后即被丢弃。

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
- Cubby 以纯文本加上条目原有格式显示返回内容，并在本机把原文的链接地址放回。译后的图片只随条目加密保存在 `Vault/Blobs/` 中，翻译时不写入任何临时副本。

Cubby 不会自行下载或安装更新：「查看并下载」只是在默认浏览器中打开发布页。用 <kbd>⌘O</kbd> 打开历史中的链接时，由你的默认浏览器打开；Cubby 不抓取链接预览或标题。macOS 可能会联系 Apple 验证应用的公证状态，这属于系统行为，并非 Cubby 发起。

### 权限

| 权限 | 用途 |
| --- | --- |
| 剪贴板读取（macOS 15.4 及以上） | 读取你复制的内容并加入历史 |
| 辅助功能 | 在你选择粘贴时向当前应用发送 <kbd>⌘V</kbd>。Cubby 不会用它读取其他应用的窗口或内容。 |
| 屏幕录制（仅截图时需要） | 在你截图时捕捉屏幕画面，详见[截图](#截图)。 |
| 登录项（可选） | 在「设置 › 通用」中开启后，登录时自动启动 Cubby |
| 输入监控（可选） | 仅在你于「设置 › 剪贴板安全」中授权后：识别你按下 <kbd>⌘C</kbd> 或 <kbd>⌘X</kbd>，让地址守护分辨是你自己复制的还是被替换的。每次按键只判断是不是这两个快捷键，随即丢弃，从不记录、保存或写入日志 |

全局快捷键（打开面板、截图）通过 macOS 标准的热键接口注册。除上面可选的输入监控检查外，Cubby 不监听你的键盘输入。

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

- **译文随条目保存。** 每条译文与所属条目一起保存在本地历史文件中（每条最多 3 种语言），译后的图片加密保存在 `Vault/Blobs/` 中。搜索也会查找译文。译文随条目删除，「设置 › 翻译 › 清除全部译文…」可删除全部译文。
- **复制或粘贴译文不会加入历史。** 只有「存为新条目」（<kbd>⌘S</kbd>）才会，并且与复制的内容一样遵守「暂停记录」与「不记录疑似密钥和令牌」。
- **复制外文时自动翻译**默认关闭。开启后，新复制的文本用本机的系统翻译自动翻译，只适用于已下载的语言；从不下载语言、从不使用大模型，也不联网。链接、代码和疑似密钥的文字不会自动翻译；暂停记录或开启低电量模式时停止。
- 你为粘贴目标应用选择的目标语言以该应用的 bundle ID 与语言代码保存在设置中。

### 图片中的文字

为了能按图中文字搜索图片，Cubby 使用 Apple Vision 在本机识别历史图片中的文字，全程不联网、不上传。识别结果只保存在本地历史文件中（每张最多 10 000 字），不写入日志；疑似密钥或令牌的文字不会保存。暂停记录期间不会识别。可在「设置 › 历史 › 搜索图片中的文字」关闭，关闭后会删除全部已识别的文字。

### 诊断信息

「设置 › 关于 › 复制诊断信息」会把一段纯文本摘要复制到剪贴板：Cubby 版本与构建号、macOS 版本、芯片、安装位置、签名信息、权限状态、加密状态、条目数与数据目录大小。其中绝不包含剪贴板内容，也不会被发送到任何地方，是否粘贴到问题报告中由你决定。

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

  如果为截图翻译保存过 API Key，请在退出前到「设置 › 翻译」中移除，或在「钥匙串访问」中删除名为 `io.github.no1coder.Cubby.translation` 的条目。如果要连历史密钥一起删除，在「钥匙串访问」中删除名为 `io.github.no1coder.Cubby.history` 的条目。请在删除数据目录之后再删它：没有密钥，加密的历史就无法读取。

  通过 Homebrew 安装的，`brew uninstall --zap --cask cubby` 会同时删除应用与数据。

### 联系方式

隐私相关问题请提交 [Issue](https://github.com/no1coder/cubby/issues/new/choose)。如需私下报告隐私或安全问题，请按 [SECURITY.md](SECURITY.md) 操作。
