# Changelog

All notable changes to Cubby are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!--
Add user-visible changes here under Added / Changed / Deprecated / Removed / Fixed / Security.
When releasing, move these entries into a new "## [x.y.z] - YYYY-MM-DD" section (see docs/RELEASING.md).
The release script extracts the section that starts with "## [x.y.z]".
-->

### Changed

- The engine badge on the screenshot translation bar now shows a short name instead of the provider and model: the provider's brand (for example DeepSeek), or the main part of a custom service's domain (for example `siliconflow` for `api.siliconflow.cn`). Long names no longer stretch the bar; hover over the badge to see the full host and model. The clipboard translation card uses the same short name when it fits.

## [0.2.1] - 2026-09-28

### Added

- Settings › General › Language: use Cubby in English or Simplified Chinese regardless of the macOS language. **Restart Now** applies it and brings you back to Settings. Automatic translation still translates into your system language.

### Changed

- Screenshot settings moved from Settings › General to their own Settings › Screenshots pane, which keeps General short enough to show without scrolling.
- The DMG now opens to a proper install window: drag Cubby onto the Applications shortcut, with a bilingual hint. The mounted disk shows Cubby's icon.

## [0.2.0] - 2026-09-27

First public release. The app is renamed from Zhantie to **Cubby**, and is now open source under the MIT License.

### Added

- **Screenshots.** Press <kbd>⇧⌘2</kbd>, choose **Take Screenshot** from the menu bar icon's menu, or click the camera button in the panel. The screen freezes so you can pick a window or drag out an area, then <kbd>↩</kbd> copies the screenshot. Screenshots go straight into your clipboard history as image cards with "Screenshot" as their source, so you can find and paste them again later. While recording is paused they are still copied, just not added to the history.
- **Window detection.** The window under the pointer is highlighted as you hover. Where windows overlap, <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> or the scroll wheel step through them one layer at a time, down to the whole screen. <kbd>Space</kbd> captures only that window, unobstructed, with transparent rounded corners and its shadow (<kbd>⌥</kbd>-click to leave out the shadow).
- **Annotation.** Rectangle, ellipse, arrow, pen, highlighter, mosaic, text and numbered steps. Each tool has three sizes and, except mosaic, eight colors, and remembers what you picked. The text tool works with input methods such as Pinyin. Annotations stay editable: select one to move, nudge, recolor or delete it, with undo and redo. Once you've drawn something, <kbd>esc</kbd> must be pressed twice to discard the screenshot.
- **Pin, save and extract text.** <kbd>⌘P</kbd> pins the screenshot as a floating window that you can move, zoom and make translucent. <kbd>⌘S</kbd> opens a save dialog where you choose the folder and file name for the PNG; it starts in the folder you used last, and cancelling it takes you back to the screenshot with your annotations intact. Turn off **Ask where to save each time** in Settings to save straight to the macOS screenshot folder or a folder you choose. <kbd>⌘T</kbd> recognizes Chinese and English text on your Mac with Apple's Vision framework and copies it.
- **Magnifier and color picker.** A pixel magnifier shows the pointer position and the color under it; <kbd>C</kbd> copies the color as HEX, or as RGB while <kbd>⇧</kbd> is held.
- **Screenshot settings.** Change or turn off the screenshot shortcut, choose the save folder, and decide whether to be asked where to save each time in Settings › General › Screenshots. Settings › Privacy shows the Screen Recording permission, which Cubby asks for the first time you take a screenshot.
- **Screenshot translation** (macOS 26 or later). Press <kbd>⇧⌘T</kbd> or click **Translate** in the screenshot toolbar to translate the text in the selection right where it is: the original text is covered with its own background, and the translation is typeset in the same place, size, color and alignment. Buttons keep their shape. Paragraphs, lists and tables are recognized with Apple's Vision document recognition, and translations stream in block by block. Compare with the original by holding <kbd>Space</kbd>, dragging the wipe divider, hovering a block to see its original text, or switching between **Original** and **Translated**, which also decides what is copied, saved or pinned. <kbd>⌘Z</kbd> undoes the translation in one step, and you can keep annotating on top of it.
- **Clipboard translation** (macOS 26 or later). Press <kbd>⌘T</kbd> on a card to open a translation card next to the panel with **Translated**, **Compare** and **Original** views, a language menu with the detected source language, and a ⇄ button that swaps the direction. <kbd>⌥↩</kbd> translates and pastes in one step, and holding <kbd>⌥</kbd> on a card previews the translation first. Rich text keeps its headings, lists, bold text and links; code is never translated. Images in your history are translated in place, like screenshots. Translations are saved with the item, marked with a translation badge, and included in search.
- **Translation engines.** Translation uses Apple's on-device translation by default: free, offline and private. To use a large language model instead, choose a provider in Settings › Translation (DeepSeek, Qwen, Kimi, GLM, OpenAI, OpenRouter, Ollama on your Mac, or any OpenAI-compatible service) and enter your own API key, which is stored in your Keychain and bound to the server it was entered for. Choose **Large Language Model** as the engine to see these settings; you can switch back to system translation at any time.
- **Translate on copy.** An optional setting translates foreign-language text as you copy it, using on-device translation only.
- **Translation privacy.** Cubby never connects to the network on its own. When you translate with a language model you set up, the recognized or copied text is sent to that provider; images are never uploaded, and text under a mosaic or text that looks like a password or key is never sent without your confirmation. See [PRIVACY.md](PRIVACY.md).
- **Card panel.** Items are shown as cards that look like their content: color swatches, monospaced code and image thumbnails. On macOS 26 the panel uses Liquid Glass. Files that have been deleted or moved are struck through and marked "File no longer exists".
- **Side preview.** <kbd>Space</kbd> (while the search field is empty) or <kbd>⌘Y</kbd> shows the full content next to the panel without taking focus. Image previews size themselves to the image's aspect ratio, color previews show the opacity, and link previews show the domain and length.
- **Keyboard navigation.** <kbd>Home</kbd> / <kbd>End</kbd> or <kbd>⌥↑</kbd> / <kbd>⌥↓</kbd> jump to the first or last item, and <kbd>Page Up</kbd> / <kbd>Page Down</kbd> move five items at a time. A card's right-click menu shows the shortcut for each action. If you reopen the panel within 30 seconds, it stays on the category you left it on.
- **Pin images from your history.** Press <kbd>⇧⌘P</kbd>, or choose **Pin to Screen** from an image card's right-click menu or the preview, to float the image in the middle of the screen, just like a pinned screenshot.
- **Search text in images.** Images in your history, including screenshots, can be found by the text in them. Text is recognized on your Mac with Apple's Vision framework and never uploaded. It's on by default; turning off Settings › History › Search text in images also deletes all recognized text.
- **Paused banner.** While recording is paused, the panel says so and offers a **Resume** button.
- **Accessibility.** Cards, categories and shortcuts are labeled for VoiceOver; a card's default action pastes it, and the Actions rotor offers favorite, preview, pin and delete. The panel, the preview and the screenshot overlay follow Reduce Motion, and cards and banners get stronger outlines and text with Increase Contrast.
- **Rich text.** RTF and HTML formatting is kept. Choose whether <kbd>↩</kbd> pastes with the original formatting or as plain text; <kbd>⇧↩</kbd> uses the other format.
- **More ways to paste.** <kbd>⌘↩</kbd> copies without pasting, <kbd>⌘1</kbd> – <kbd>⌘9</kbd> paste one of the first nine items, a double-click pastes, and cards can be dragged into other apps. The panel footer shows which app will receive the paste.
- **Undo.** <kbd>⌘⌫</kbd> deletes an item and <kbd>⌘Z</kbd> restores it.
- **Search and organize.** Matches are highlighted; every word must match, and file paths and source app names are searchable. Results are sorted by relevance: items containing your exact phrase come first, then items where the first word appears near the start, then everything else. Filter by category with <kbd>⇥</kbd>, and mark favorites with <kbd>⌘P</kbd>. Favorites are kept regardless of the history limit.
- **Custom shortcut.** Record any key combination to open the panel (<kbd>⇧⌘V</kbd> by default).
- **Panel position.** Open the panel next to the pointer, under the menu bar icon, or in the center of the screen. Clicking the menu bar icon also opens it.
- **First-launch guide** with the live status of the clipboard access and Accessibility permissions, and a **Take and pin screenshots** card where you can set the screenshot shortcut. On macOS 15.4 and later, **Grant Access** makes macOS ask for clipboard access right away (choose **Allow Paste**), and the guide then points you to System Settings to set Cubby to **Allow** so macOS stops asking. Reopen the guide any time with **Setup Guide…** in the menu bar icon's menu.
- **Screenshot hints.** The label on a hovered window always reminds you that <kbd>Space</kbd> captures a clean window and, where windows overlap, that <kbd>⇥</kbd> steps through them. For your first three screenshots, a hint bar at the bottom of the screen shows what you can do.
- **Quit & Reopen Cubby** button in the Screen Recording window, for when macOS needs Cubby to restart before screenshots work.
- **Settings window** with General, History, Privacy, Translation (macOS 26) and About panes, including launch at login and a history limit of 50 to 2,000 items.
- **Check for Updates** in Settings › About. Cubby only asks GitHub for the latest release when you click it, or weekly if you turn on the automatic check, which is off by default.
- **Copy Diagnostic Info** in Settings › About, for bug reports. It never includes clipboard content.
- **Accessibility repair guide.** When an update changes the code signature, macOS may keep showing Cubby as allowed while the permission no longer works. Cubby detects this and walks you through removing and re-adding it.
- **Install location check.** Cubby reminds you to move it to Applications when it runs from a disk image or a quarantined location.
- **Versioned history format.** The history file now records a schema version. Older files are migrated automatically (the original is backed up first), and a file written by a newer Cubby is opened read-only so it is never overwritten.
- **English and Simplified Chinese** interface. Cubby follows your macOS language settings. English is now the development language, and all interface text lives in a String Catalog, so new languages can be added with a pull request.
- **Signed and notarized downloads.** Universal (Apple silicon and Intel) DMG and zip on GitHub Releases, signed with a Developer ID and notarized by Apple.
- **Homebrew:** `brew install --cask no1coder/tap/cubby`.
- **`make strings` and `make check-strings`** for contributors. `make strings` extracts new interface text from the source into `Resources/Localizable.xcstrings`; `make check-strings` fails if the catalog is out of date or a Simplified Chinese translation is missing, and runs in CI.
- **User guide.** Choose **User Guide…** from the menu bar icon's menu (also in Settings › About and the panel's shortcut help) to read how every feature works, with a table of contents and search.

### Changed

- Renamed from Zhantie to Cubby. The bundle ID is now `io.github.no1coder.Cubby`, and data lives in `~/Library/Application Support/Cubby`. History, settings and permissions from Zhantie are not migrated automatically.
- Copying the same content again moves the existing item to the top instead of adding a duplicate.
- Search is much faster in a large history: with 2,000 items, each keystroke takes about 1–11 ms instead of 70–280 ms.
- Permission buttons use the same words everywhere: **Grant Access** when macOS can ask you directly, **Open System Settings** when the change has to be made there. Permission status reads **Allowed** or **Not allowed**, as in System Settings.
- The four groups in Settings › General now have titles: Shortcut & Panel, Pasting, Screenshots, and Startup & Updates.
- Screenshot overlay: the highlighter is more visible, numbered steps have a white outline so they stand out on any background, the hover outline has rounded corners like the windows it frames, **Done** is a solid accent-colored button, and the highlight slides between tools as you switch (unless Reduce Motion is on). The layer count on the hover label counts only windows, not the whole screen.

### Fixed

- On macOS 26, the panel's shadow now follows its rounded corners instead of showing square corners.
- The screen capture timeout now fires on time even when the system is busy, so a stalled capture can't leave the screenshot hanging.
- Resizing a screenshot selection by a handle no longer nudges the edges that should stay in place.
- Text editing no longer gets stuck when a click with the text tool interrupts resizing a selection.
- Leaving window mode in the middle of a click (by stepping to the whole screen) no longer captures only the window.
- Holding <kbd>⇧</kbd> while resizing a selection near the edge of the display no longer pushes the square past the edge.

### Security

- Content marked concealed, transient or auto-generated (as password managers do) is never recorded.
- Recording can be turned off for specific apps. Common password managers are excluded by default.
- Text that looks like an API key, private key or JWT is not recorded by default.
- The data folder is private to your user (0700, files 0600) and excluded from Time Machine.
- Before pasting, Cubby checks that the target app is still frontmost.
- Screen Recording is requested only when you take your first screenshot and is never used at launch or in the background. The captured screen stays in memory while you select and annotate, and text recognition runs on your Mac.
- Text recognized in history images is kept only in the local history file and never written to logs; text that looks like a secret isn't saved, and recognition stops while recording is paused.
- No network access by default and no analytics or telemetry. See [PRIVACY.md](https://github.com/no1coder/cubby/blob/main/PRIVACY.md).

## [0.1.0]

Internal preview under the working name Zhantie. Not publicly released.

- Menu bar clipboard history with a global shortcut to open it.

[Unreleased]: https://github.com/no1coder/cubby/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/no1coder/cubby/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/no1coder/cubby/releases/tag/v0.2.0
