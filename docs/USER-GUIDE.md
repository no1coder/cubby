# Cubby User Guide

Cubby (小格子) is a native macOS clipboard manager: it remembers the text, links, colors, images and files you copy, and brings them back with one shortcut. It also takes WeChat-style screenshots that you can mark up and pin, hangs images on a clothesline at the top of the screen, warns you when an address you copied is replaced, and on macOS 26 translates screenshots and clipboard items. Everything stays on your Mac: Cubby only goes online to check for a new version (once a day, and you can turn that off) or to translate with a language model you set up yourself.

## Getting started

This section gets Cubby installed, gives it the permissions it needs, and shows you how to open the panel.

### Install

- **Homebrew:** run `brew install --cask no1coder/tap/cubby` in Terminal, and update later with `brew upgrade --cask cubby`.
- **Download:** get the DMG from the [latest release](https://github.com/no1coder/cubby/releases/latest), drag Cubby into Applications, and open it from there.

Don't run Cubby from the disk image or the Downloads folder, or macOS may not keep its permissions and its login item. Releases are signed and notarized by Apple, so you only confirm once when you first open Cubby. Cubby needs macOS 14 or later and runs on Apple silicon and Intel; translation needs macOS 26 or later. Cubby lives in the menu bar and has no Dock icon.

### The first-launch guide

The first time you open Cubby, a **Welcome to Cubby** window walks you through four short steps. Click **Continue** (or press `↩`) to go on and **Back** to return to a step.

1. **Welcome:** turn on **Launch at login** if you like. **Remind me about new versions** ("Reads the latest version number from GitHub once a day") is ticked; untick it if you don't want Cubby to check.
2. **Permissions:** **Allow clipboard access** (starting with macOS 15.4, reading the clipboard needs your permission, see below) and **Allow direct paste** (with Accessibility access, choosing an item pastes it into the current app). Their status updates live, and Cubby only asks when you click a button.
3. **Choose a Style:** pick where the clipboard appears: a **Floating Panel** next to the pointer, **Docked to the Right Edge** as a full-height sidebar, or **Docked to the Bottom Edge** as a row of cards. Below, choose the **Appearance**: Match System, Light or Dark. Both apply right away; use `←` `→` to switch cards from the keyboard.
4. **Shortcut:** set the shortcut that opens the panel, `⇧⌘V` by default (it replaces "Paste and Match Style" in some apps; you can change it anytime), and the screenshot shortcut, `⇧⌘2` by default. Screenshots are only explained here; Cubby doesn't ask for Screen Recording. If the **Only images** or clothesline shortcuts are on, they're listed too.

Then click **Get Started**. Cubby doesn't check for updates until you close this window. To see the guide again, choose **Setup Guide…** from the menu bar icon's menu; reopening it shows your current settings and doesn't change them.

### Permissions

Cubby uses at most three permissions, each for a single job, and `Settings › Privacy` shows the status of all three. A fourth one, Input Monitoring, is optional and only helps the address guard; see "Address guard".

**Clipboard access (macOS 15.4 and later):** lets Cubby record what you copy. On earlier versions this row reads "Not required on this version of macOS".

1. Copy something first, then click **Grant Access** in the guide or in `Settings › Privacy`. If the clipboard is empty, macOS doesn't ask, and the card tells you to copy something first.
2. When macOS asks, choose **Allow Paste**.
3. The prompt has no "Always Allow", so the status changes to "Set to “Ask”, so macOS will keep asking when you copy". Click the button, now called **Open System Settings**, and set Cubby to **Allow** in `System Settings › Privacy & Security › Paste from Other Apps`. On macOS 15.4 – 15.x this pane is called **Paste**.
4. Once the status reads **Allowed**, copying no longer brings up a prompt.

**Accessibility:** lets Cubby send `⌘V` to the current app when you choose an item, so it pastes directly. Click **Grant Access**, then turn on Cubby in `System Settings › Privacy & Security › Accessibility`. Without it, choosing an item only copies it to the clipboard, and the panel says "Cubby can only copy for now".

**Screen Recording (screenshots only):** requested the first time you take a screenshot. macOS shows its prompt, and Cubby shows an **Allow Screen Recording to take screenshots** window. Click **Open System Settings** and turn on Cubby in `System Settings › Privacy & Security › Screen & System Audio Recording` (**Screen Recording** on macOS 14). macOS may ask you to reopen the app; click **Quit & Reopen Cubby** in that window. Cubby only uses this permission when you take a screenshot, and your clipboard history works without it.

### Open the panel

Press `⇧⌘V` in any app to open the panel and press it again to close it, or click the menu bar icon. Clicking outside the panel or pressing `esc` also closes it. You can change the shortcut in `Settings › General`. The panel can float next to the pointer, below the menu bar icon or in the center of the screen, or be docked to the right or bottom edge; see "Panel position" below.

### The menu bar icon

Click the menu bar icon to open the panel. Right-click it (or Control-click) to open its menu:

- The top of the menu shows Cubby's status: **Recording · N items**, **Paused · N items**, or a red **Address Replaced** while a replaced address is waiting for you.
- **Open Clipboard**, **Only Images**, **Take Screenshot** and **Show Clothesline · N photos:** their shortcuts are shown in gray on the right. **Show Clothesline** is hidden while the clothesline is off and dimmed while nothing hangs on it.
- **Panel Position** and **Appearance:** submenus that show the current choice on the right. **Panel Position** offers Next to the pointer, Below the menu bar icon, Center of the screen, Docked to the right edge and Docked to the bottom edge; **Appearance** offers Match System, Light and Dark.
- **Pause Recording:** nothing new is recorded, and the menu bar icon changes. While paused, the item reads **Resume Recording**.
- **Clear History…:** after you confirm, deletes every item that isn't a favorite. This can't be undone.
- **User Guide:** opens this guide.
- **Setup Guide…:** reopens the first-launch guide.
- **Check for Updates…**, **Settings…** (`⌘,`) and **Quit Cubby** (`⌘Q`).

When something needs your attention, **Allow Clipboard Access…** appears at the top of the menu. When a new version is available, the menu bar icon gets a blue dot at its top right and **Version x.y.z Available…** appears at the top of the menu; choose it to open the release page. See "Update reminders" under Settings.

The icon itself also shows how many photos hang on the clothesline. When the address guard catches a replaced address, the icon turns into a red **Address Replaced** label until you respond; clicking it brings the warning back.

## The clipboard panel

The panel is the heart of Cubby: find anything you copied and paste it back into the app you're using.

### Panel position

The panel can appear in five places:

- **Floating:** **Next to the pointer** (the default), **Below the menu bar icon** or **Center of the screen**.
- **Docked to the right edge:** a full-height sidebar along the right side of the screen.
- **Docked to the bottom edge:** a full-width shelf of cards along the bottom of the screen. Press `←` `→` to move between cards (while the search field is empty); the preview, the translation card and the Pick Words card open right above the selected card.

There are three ways to switch:

- Click the layout button (**Switch Layout**) at the top of the panel, next to the camera button. It goes from floating to the right edge, to the bottom edge and back to the floating position you used last.
- Pick one of the five thumbnails in `Settings › General › Panel position`.
- Choose it from **Panel Position** in the menu bar icon's menu.

### Appearance

Choose **Match System** (the default, follows macOS), **Light** or **Dark** in `Settings › General › Appearance`, from **Appearance** in the menu bar icon's menu, or in the first-launch guide. It applies to the panel, the preview, the clothesline and Settings.

### Cards and categories

Every item is a card that looks like its content. Each card shows the source app, when you copied it and, on the first nine cards, their `⌘1` – `⌘9` number. On text and code cards these sit in a header row at the top, so the content below uses the full width.

- **Text** shows its first lines; rich text keeps its RTF / HTML formatting.
- **Links** show a colored letter tile for the site, the page title when the browser copied one with the link, and the full address. Cubby doesn't go online to fetch site icons.
- **Code** shows its language (Swift, JavaScript, Python, JSON, Shell, HTML, CSS, SQL, Go or Rust, otherwise "Code") with light syntax colors for keywords, strings and types.
- **Colors** fill the card with the color and show its HEX and rgb() values.
- **Images** show the whole picture, screenshots included: the frame follows the image's shape, and very tall or very wide images are fitted inside it instead of cropped. Images on the clothesline are marked **Hanging**.
- **Files** show their name and path, struck through and marked "File no longer exists" if the file was deleted or moved.
- Addresses and bank card numbers show what they are and whether they passed the checksum or format check; see "Address guard".

Copying the same content again moves the existing item to the top instead of adding a duplicate. The list is grouped into **Today**, **Yesterday** and **Earlier** (search results are sorted by relevance instead).

The categories at the top are **All**, **Text**, **Links**, **Images**, **Files**, **Colors** and **Favorites** (a star). Press `⇥` / `⇧⇥` to switch, or click one. If you reopen the panel within 30 seconds, it stays on the category you left it on; the search field always starts empty.

### Hover actions

Hover over a card to show a small toolbar at its top right, so you don't need the right-click menu: **Add to Favorites** (`⌘P`), **Preview** (`Space`) and **Delete** (`⌘⌫`). Images also have **Pin to Screen** (`⇧⌘P`) and, while the clothesline is on, **Hang on Clothesline** (`⌘L`). In the image grid (see below), the toolbar only has the image buttons and **Delete**.

### Only images

Press `⌃⇧V` in any app to open the panel straight on your images; press it again to close it. In the floating panel and the right-edge sidebar, the **Images** category is a two-column grid: `↑` `↓` move a row and `←` `→` move one image (while the search field is empty). When you open it with the shortcut, a short hint above the panel reminds you of the keys. Docked to the bottom edge, images stay in the shelf's single row. Typing searches images by the text in them, unless **Search text in images** is off.

You can also choose **Only Images** from the menu bar icon's menu. Change or turn off the shortcut under **Only images** in `Settings › General`; if you already use `⌃⇧V` for another Cubby shortcut, it starts turned off.

### Search

Just start typing when the panel is open. Matches are highlighted.

- With several words, an item must contain all of them. If that finds nothing, **Search Only "…"** searches for the first word alone.
- Besides the content itself, file paths, source app names and the page titles of links are searched too.
- While you search, the category bar shows how many items match in each category and hides the categories with no matches.
- Images, screenshots included, can be found by the text in them. The text is recognized on your Mac and never uploaded; turn off **Search text in images** in `Settings › History` if you don't want this.
- Items you translated can also be found by their translation.
- Results are sorted by relevance: items containing your exact phrase come first; items that match only through text in an image come after text matches; items that match only through a translation come last.
- Press `esc`, or click the clear button in the search field, to clear the search.

### Preview

Press `Space` (while the search field is empty) or `⌘Y` to show the full content in a preview next to the panel, and again to close it. The preview follows your selection and never takes keyboard focus. Its footer shows details such as length and lines, a link's domain, a color's opacity or an image's pixel size, and it offers buttons such as **Paste**, **Open** and **Pin to Screen**, depending on the item.

### Pick words

When you only need part of a long text, such as an address, a phone number or a few words from a message, press `⌘B` (or press and hold a card for about half a second, or choose **Pick Words** from its right-click menu). The text is split into word chips next to the panel; Chinese and Japanese are split into words, and links, email addresses and phone numbers stay in one piece.

- Click a chip to pick it, click again to unpick. Drag across chips to pick a run (starting on a picked chip unpicks instead), and `⇧`-click to pick everything from your last click.
- `⌘A` or **Select All** picks every chip; press it again to clear.
- `↩`, `⇧↩` or **Paste** pastes the picked words into the current app. `⌘C`, `⌘↩` or **Copy** only copies them, and the panel stays open.
- Picked words keep their original spacing and line breaks. Separate runs are joined with a line break if they were on different lines, directly between Chinese, Japanese or Korean characters, and with a space otherwise.
- The picked words aren't added to your history as a new item.

Pick Words works with text (including rich text and code) and with images whose text Cubby has recognized. Links, colors, files and images without text only beep. Only the first 20,000 characters are split. The card follows your selection; press `Space` or `⌘Y` to switch to the preview, `⌘T` to the translation card, and `⌘B` or `esc` to close it.

### Choose and paste

Use `↑` `↓` (or `⌃P` `⌃N`) to choose an item, `⌥↑` `⌥↓` (or `Home` `End`) to jump to the first or last item, and `Page Up` `Page Down` (`fn↑` `fn↓` on a laptop) to move five items at a time. A single click only selects a card.

- `↩` or a double-click: paste into the current app.
- `⇧↩`: paste in the other format. When the default is **Original formatting**, `⇧↩` pastes as plain text, and the other way round. Change the default in `Settings › General › Paste text as`.
- `⌘↩`: copy to the clipboard without pasting.
- `⌘1` – `⌘9`: quick paste one of the first nine items.

The footer shows where the paste goes: "↩ Paste to" followed by the target app's icon and name. The target is the app you were using before you opened the panel. Before sending `⌘V`, Cubby checks that this app is still in front; if you switched apps in between, it only copies and says "Target app changed, copied instead".

Without Accessibility access, or with `Settings › General › When you choose an item` set to **Copy to the clipboard only**, `↩` only copies and the footer shows "↩ Copy". Press `⌘V` yourself to paste.

### Favorites, delete and undo

- `⌘P`: favorite or unfavorite an item. Favorites appear under **Favorites**, don't count toward the history limit and are kept when you clear the history.
- `⌘⌫`: delete the selected item. The footer shows "Deleted" and **Undo**.
- `⌘Z`: undo the deletion before the notice disappears (about 4 seconds); the item returns to its place. Once you close the panel, the deletion can't be undone.

### Open, pin and drag

- `⌘O`: open a link (in your default browser), a file or an image.
- `⇧⌘P`: pin the selected image in the middle of the screen as a floating window; see "Pinned images" under Screenshots. For other items it only beeps.
- `⌘L`: hang the selected image on the clothesline, or take it down; see "Clothesline". It works while the clothesline is on; for other items it only beeps.
- Drag a card into another app to drop its text, image or file there. Dropping an image in Finder lets Finder write the file itself, so no temporary copy is made; see "Encryption" under Privacy and data.

### The right-click menu

Right-click a card to see what you can do with it, with each shortcut shown on the right:

- **Paste**, **Copy Only**, **Preview**, **Pick Words**, **Delete**, and **Favorite** or **Unfavorite**. **Pick Words** is dimmed for items without text to pick.
- Rich text also offers **Paste as Plain Text** or **Paste with Original Formatting**.
- Links, files and images have **Open**; images have **Pin to Screen** and, while the clothesline is on, **Hang on Clothesline** or **Take Down from Clothesline**; files have **Show in Finder**.
- On macOS 26 there are also **Translate** and **Translate and Paste**, plus **Copy Translation** for items you've translated. Both are dimmed for items that can't be translated.

### esc and the shortcut help

`esc` steps back one level at a time: close the shortcut help → cancel a translation in progress → close the translation card, the Pick Words card or the preview → clear the search → close the panel.

Click the keyboard icon (**Keyboard Shortcuts**) at the right of the footer to see every shortcut and mouse action inside the panel; click its close button, click an empty spot or press `esc` to close it. The shortcuts are grouped into **Select & Paste**, **View & Organize**, **Images** (marked **New**: Only Images, the clothesline and Pin to Screen, with the shortcuts you set) and **Translation**. The list follows the current state: when Cubby can't paste directly, the `↩` row says **Copy**; global shortcuts you turned off, and the clothesline rows while the clothesline is off, are left out; and the **Translation** group only appears when translation is available. At the bottom, **Full user guide…** opens this guide.

### Pause recording

When you're about to copy something sensitive, pause recording: choose **Pause Recording** in the menu bar icon's menu, or turn on **Pause recording** in `Settings › Privacy`. While paused:

- Nothing you copy is saved, and the menu bar icon changes.
- A "Recording paused" banner stays at the top of the panel; click **Resume** on it to start recording again.
- Screenshots still work; they just aren't added to your history.
- Text in new images isn't recognized, and **Save** on the translation card and **Translate text when you copy it** pause too.

## Clothesline

Hang images you'll need again on a line at the top of the screen, so they're always one move away.

### Hang and take down

The clothesline is on by default; turn it off with **Hang images at the top of the screen** in `Settings › General › Clothesline`.

- In the panel, select an image and press `⌘L`, choose **Hang on Clothesline** from its right-click menu, or click the clothesline button in its hover toolbar. The line slides down for a moment to show the new photo.
- Up to 12 photos hang at once; hanging another one takes down the leftmost.
- To take a photo down, do the same again (**Take Down from Clothesline**), or hover over it on the line and click the **×** at its top left. **Take All Down** in Settings empties the line. Taking a photo down doesn't remove it from your history.
- To hang every new screenshot automatically, turn on **Hang screenshots on the clothesline** in `Settings › Screenshots` (shown while the clothesline is on).

### Show the line

- Press on an empty spot in the menu bar and drag down: once you've dragged about 30 points, the line slides down from under the menu bar. Pressing on a menu title or a menu bar icon opens that menu instead, so start from an empty spot.
- Or rest the pointer at the very top edge of the screen. After the delay set in **Slide down after the pointer rests at the top edge for** (0.3 to 1.2 seconds, 0.5 by default), the line slides down. Turn off **Also slide down when the pointer rests at the top edge** if it slides down when you don't want it; dragging down still works.
- Either way, the line slides back up shortly after the pointer leaves it.
- Press `⌃⌥T` or choose **Show Clothesline** from the menu bar icon's menu; press it again to hide the line. Change or turn off the shortcut under **Show / Hide** in `Settings › General › Clothesline`.
- The line stays hidden while nothing hangs on it and in full-screen apps. The menu bar icon shows how many photos are hanging.

### Use a photo

Hover over a photo to see the hint "Click to edit | Double-click to copy | Drag to an app".

- **Double-click** copies the image.
- **Drag** it into another app to drop it there.
- **Click** enlarges it and opens the screenshot tools on it, so you can annotate it as described in "Annotate"; Extract Text, Pin to Screen and Save work too. Enlarging doesn't need Screen Recording.
  - `⌘C` or **Copy** copies the annotated image.
  - `↩` or **Done & Hang Back** saves the result as a new history item that takes the photo's spot on the line. The original stays in your history. While recording is paused, nothing is saved.
  - `esc` closes it without saving.

Photos on the line aren't removed when your history is trimmed to its limit. Deleting an item or clearing the history also takes it off the line.

## Address guard

Some malware watches the clipboard and swaps an address you copied for its own. Cubby's address guard warns you when that happens. It's on by default; turn it off or choose what to guard in `Settings › Security`.

### What's guarded

Bitcoin, Ethereum and EVM chain, TRON, Solana and Litecoin addresses, and bank card numbers. Cubby recognizes them by their checksum or format, so ordinary text isn't mistaken for an address. In the panel these items show what they are and "checksum valid" or "valid format". The one you copied last is marked **Guarding**, other addresses with a valid checksum are marked **Verified**, and card numbers are marked **Bank card**. Bank card numbers are shown in full.

### When an address is replaced

Cubby steps in when the clipboard changes to a different value of the same kind shortly after you copied one (within 10 seconds with Input Monitoring, 1.5 seconds without it), while the same app stayed in front. With Input Monitoring, it also checks that you didn't press `⌘C` or `⌘X` yourself in between.

A warning, "The address in your clipboard was replaced", then appears near the top of the screen. It compares **You copied** with **Now in your clipboard** character by character, with the differences in red, and doesn't take the focus away from the app you're using.

- **Restore What I Copied:** puts your value back into the clipboard. If the clipboard has changed again since, nothing is restored.
- **I Changed It Myself:** closes the warning, and the new value is treated as yours.
- **View Security Log:** opens `Settings › Security`.

Cubby never restores anything automatically. Until you choose, the menu bar icon shows a red **Address Replaced**; click it to see the warning again.

### The replaced item in the panel

The value that replaced yours stays in your history as a red record, "Unknown source · replaced the previous item", with the value struck through and the note "Not in ⌘1–⌘9 · can't be pasted or copied". It can't be pasted, copied or dragged in any way, not even through Pick Words, the translation card or Translate and Paste. You can still select it, preview it, favorite it and delete it. **Details** shows the warning again (after Cubby restarts, it opens `Settings › Security` instead). If you chose **I Changed It Myself**, it's a normal item.

### Checks when you paste

When you paste or copy an address or card number from Cubby, Cubby reads the clipboard again right before pasting. If it matches, a short note says "Pasted to “App”, matches what you copied" (or "Copied, matches what you copied"); turn this note off with **Show the check result after pasting an address** in `Settings › Security`. If the clipboard changed in between, Cubby doesn't paste and says "The clipboard changed before pasting, so Cubby didn't paste it".

### Input Monitoring (optional)

In `Settings › Security`, **Tell more accurately whether you copied it** has a **Grant Access** button for Input Monitoring (`System Settings › Privacy & Security › Input Monitoring`). With it, Cubby notices when you press `⌘C` or `⌘X`, so it can tell your own copies from replacements and watch for longer. It only notices those two shortcuts and never records what you type. Without it, very fast replacements may go unnoticed.

### What the address guard never does

- It never clears your clipboard, never intercepts `⌘V` and never changes how normal copy and paste work. If nothing is replaced, you won't notice it.
- The security log stays on your Mac. It keeps 90 days of events (up to 500) with shortened values only.

macOS doesn't tell apps who reads the clipboard. To keep other apps from reading it, set apps you don't recognize to **Ask** in `System Settings › Privacy & Security › Paste from Other Apps`; **Open System Settings** at the bottom of `Settings › Security` takes you there.

## Screenshots

Press `⇧⌘2` to freeze the screen, pick a window or an area and mark it up, then copy, save, pin or extract its text.

### Start a screenshot

There are three ways: press `⇧⌘2` (change or turn it off in `Settings › Screenshots`), choose **Take Screenshot** from the menu bar icon's menu, or click the camera button to the right of the panel's search field.

The screen freezes right away. If the panel is open, it hides first so it's never in the picture. For your first three screenshots, a hint bar at the bottom of the screen shows what you can do. The first screenshot asks for Screen Recording (see "Getting started"). Pressing the screenshot shortcut again during a screenshot cancels it if you haven't drawn anything yet; once you have, it's ignored so a stray key press can't throw your annotations away.

### Pick a window

As you move the pointer, the window under it is highlighted: the highlighted part is what will be captured. Over the desktop, the menu bar or the Dock, the whole screen is highlighted.

- Click: select the highlighted window or screen, so you can adjust and annotate it.
- `↩` or `⌘C`: capture the highlighted target right away and copy it.
- Double-click a window: select it and finish in one go.
- `⌘A`: select the whole screen under the pointer.

Where windows overlap, press `⇥` or scroll down to highlight the next window behind, down to the whole screen; press `⇧⇥` or scroll up to go back. This way even a window that only peeks out from behind another can be selected. The label on the window shows the app name and pixel size, and for overlapping windows which layer you're on, such as "1 / 3".

### Clean window capture

With the pointer over a window, press `Space` once to switch to clean window mode: the magnifier hides, the highlight changes, and the label says "Click to capture · ⌥ no shadow · Space to exit". A clean window capture is copied and added to your history right away, without an annotation step.

- Click or press `↩`: capture only that window, complete even where other windows cover it, with its transparent rounded corners and its shadow.
- `⌥`-click: capture it the same way, without the shadow.
- Press `Space` again: leave clean window mode.

### Select and adjust an area

Drag to select an area. While dragging, hold `⇧` for a square, `⌥` to grow the selection from its center, or `Space` to move the whole selection without resizing it. Once you've selected an area:

- Drag one of the eight handles or an edge to resize it (hold `⇧` to keep it square), or drag inside it to move it.
- The arrow keys move the selection by 1 pt, or 10 pt with `⇧`. The size label at its top-left corner is in pixels.
- Dragging outside the selection starts a new one, and right-clicking the selection clears it so you can select again. Either way, your annotations stay.
- A selection is always on a single display.

### Magnifier and color picker

While you pick a window, drag out an area or drag a handle, a magnifier next to the pointer shows the pixels under it, with the position and the color value below. Press `C` to copy the color value shown and end the screenshot; a HEX color is added to your history as a color card. Hold `⇧` to show the color as RGB instead, and `C` then copies the RGB value.

### Annotate

Once you've selected an area, a toolbar appears below it. Press a letter or click the toolbar to choose a tool:

- `R` Rectangle; hold `⇧` for a square.
- `O` Ellipse; hold `⇧` for a circle.
- `A` Arrow; hold `⇧` to snap to 45° steps.
- `P` Pen.
- `H` Highlighter: it doesn't get darker where it overlaps itself, and the text underneath stays readable.
- `M` Mosaic: it only pixelates the screen image itself.
- `T` Text: click to place a text box. Input methods such as Pinyin work. `↩` starts a new line; `esc`, `⌘↩` or a click outside the box finishes typing, and an empty box is discarded.
- `N` Number: click to place a numbered step. If you delete one, the numbers after it close the gap.

Press the same letter again, or `V`, to go back to the pointer. With a tool chosen, a style bar appears next to the toolbar: each tool has three sizes (**Thin**, **Regular** and **Thick**, or **Small**, **Medium** and **Large** for text) and eight colors, except mosaic, which only has sizes. From the keyboard, `1` – `8` pick red, orange, yellow, green, blue, purple, black and white, and `[` / `]` make the line thinner or thicker.

If an annotation is selected, style changes apply to it; otherwise they apply to the current tool. Each tool remembers the style you used last, even after you quit Cubby. You can draw outside the selection: annotations there stay visible but are cropped from the result, so you can enlarge the selection later to include them.

### Edit, undo and discard

Until you finish, annotations stay editable. In pointer mode (`V`), click an annotation to select it, then drag it, nudge it with the arrow keys (10 pt with `⇧`), change its color or size in the style bar, or press `⌫` to delete it. Click existing text with the text tool to edit it again. `⌘Z` undoes and `⇧⌘Z` redoes; dragging an annotation counts as one step.

- Before you've drawn anything, one `esc` cancels the screenshot; so does a right-click when there's no selection.
- Once you've drawn something (or translated), the first `esc` only shows "Press Esc again to discard", and the second one discards the screenshot. Doing anything else in between resets the warning.
- While you type in a text box, `esc` only finishes typing and never cancels the screenshot; while an input method shows candidates, `esc` only closes them.

### Finish

- **Copy:** press `↩` or `⌘C`, double-click inside the selection, or click **Done** in the toolbar. The screenshot is copied to the clipboard and added to your history with "Screenshot" as its source. The app you were using stays in front, so you can paste right away.
- **Save:** press `⌘S` or click **Save** to choose a folder and a file name in a save dialog. Only PNG is offered, the suggested name looks like `Cubby 2026-09-27 01.23.45.png`, and the dialog opens the folder you used last. **Cancel** takes you back to the screenshot with your selection and annotations intact. Saved screenshots are added to your history too, but not copied to the clipboard.
- **Pin to Screen:** press `⌘P` or click **Pin to Screen** to pin the screenshot in place at its actual size. It's also added to your history.
- **Extract Text:** press `⌘T` or click **Extract Text**. Cubby recognizes the Chinese and English text in the selection on your Mac with Apple's Vision framework (annotations are left out), copies it in reading order and adds it to your history as text. If there's no text, you'll see "No text found".

Turn off **Ask where to save each time** in `Settings › Screenshots` to have `⌘S` save straight to the folder in **Save screenshots to**, without a dialog. A name that already exists gets a number added, and if the folder isn't available, the file goes to your Desktop. While recording is paused, all of this still works; nothing is added to your history.

### Pinned images

A pinned image floats above all other windows, and you can pin several at once.

- Drag to move it. Scroll or pinch to zoom around the pointer (10% – 400%); `⌘0` returns to the actual size.
- Its right-click menu has **Copy** (`⌘C`), **Save…** (`⌘S`, which always opens the save dialog), **Opacity** (100%, 80%, 60% or 40%) and **Close** (`⌘W`).
- Double-click it or press `esc` to close it. A new pin doesn't take keyboard focus; click it first so your shortcuts go to it.

Pinned images appear in your next screenshot, and they all disappear when Cubby quits. You can also pin images from your history with `⇧⌘P`; they appear in the middle of the screen.

## Screenshot translation

On macOS 26, `⇧⌘T` translates the text in the selection in place, typesetting the translation right where the original was.

### Translate a screenshot

Screenshot translation needs macOS 26 or later; on earlier versions the toolbar has no **Translate** button and `⇧⌘T` does nothing. After selecting an area, press `⇧⌘T` or click **Translate** in the toolbar, right after **Extract Text**. If you're typing in a text box, `⇧⌘T` finishes the text first and then translates.

1. **Recognize:** Cubby recognizes the text in the selection on your Mac and splits it into blocks: paragraphs, list items and table cells. The translation bar says "Recognizing text…".
2. **Translate:** translations stream in block by block, and the bar counts them, for example "Translating 5/14".
3. **Replace in place:** the original text of each block is covered up, and the translation is typeset in the same place, size, color and alignment. Buttons keep their shape.

You can keep annotating after translating; annotations are drawn on top of the translation.

### The translation bar

The translation bar appears on the side of the toolbar away from the selection. Once the translation is done, it has:

- **Language menu:** shows the language pair, for example "English → Japanese". Click it to choose another target language. Cubby re-translates the text it already recognized and remembers your choice for next time. The language the text is already in is dimmed.
- **Engine chip:** a laptop icon means the translation happens on your Mac; a cloud icon means the text is sent to the service you set up. Hover over it for details.
- **Original | Translated switch:** decides which version **Done**, **Save** and **Pin to Screen** export. Once there's a translation, `⇧⌘T` also flips this switch. With **Translated** selected, `⌘T` copies the translated text instead of recognizing text again.
- **Compare:** turns on a divider you can drag to compare the original and the translation.
- **Copy Translation:** copies all translated text in reading order, one block per line, with the original text for any block that wasn't translated. The text is added to your history (unless recording is paused), and the screenshot stays open.
- The hint "Hold Space to see the original".

### Four ways to compare

- **Hold `Space`:** shows the original for as long as you hold it.
- **Compare:** the divider starts in the middle of the selection, with the original on the left and the translation on the right. Drag its round handle to move it; after dragging, `←` `→` nudge it, with bigger steps while you hold `⇧`.
- **Hover:** rest the pointer on a translated block for about 0.4 seconds to see its original text in a bubble.
- **Original | Translated switch:** flips between the two versions.

Only the switch changes what's exported; holding Space, the divider and hovering are for looking only.

### Undo and cancel

- `⌘Z` removes the whole translation in one step, and `⇧⌘Z` brings it back. Switching the target language counts as one more step.
- While text is being recognized or translated, undo and redo aren't available. Press `esc` then to cancel only the translation: you're back where you were before, and any blocks that already arrived are dropped.
- If the translation failed, `esc` closes the translation bar. After a finished translation, discarding the screenshot takes two presses of `esc`, as with annotations.
- If you move or enlarge the selection after translating, the translation stays anchored to the screen content. When the new selection includes text that wasn't translated, the bar says "Selection changed"; click **Translate Again**.

### What isn't translated or sent

This text stays as it is and is never sent to any translation engine:

- anything without letters, such as numbers, prices, times and symbols;
- text that looks like code, a file path, a URL, an email address or a command line;
- text that's already in the target language;
- text under a mosaic;
- text that looks like a secret, such as an API key or a token.

To hide something, draw a mosaic over it before you translate. With a language model, only the recognized text is sent; the screenshot itself is never uploaded.

### When translation fails

The translation bar shows a short reason and a button:

- "Translation isn't set up" or "The API key is invalid or not allowed": click **Open Settings**. The screenshot hides for a moment and `Settings › Translation` opens. When you close Settings, the screenshot comes back and tries again if the setup now works.
- "Download English → Japanese first": click **Download Languages** and confirm the download in the macOS window that appears. Cubby tries again once it's done.
- "Can't connect to …", "Too many requests or no quota left", "The service is temporarily unavailable" or "Couldn't read the translation": click **Retry**.
- "This language pair isn't supported" or "The text is already in English. Choose a target language": choose another target language from the language menu.
- "No text to translate": there's nothing in the selection that needs translating.

If only some blocks failed, the ones that arrived stay, and the bar says "Some text wasn't translated". **Retry** sends only the missing blocks.

## Clipboard translation

On macOS 26 you can also translate text, rich text and images in the panel, and paste the translation directly.

### Open the translation card

Select an item in the panel and press `⌘T` (or `⇧⌘T`), or choose **Translate** from its right-click menu. The translation card opens next to the panel; press `⌘T` again to close it. The card has three views. Click to switch, or press `←` `→` while the search field is empty:

- **Translated:** the translation only.
- **Compare:** the original and the translation paragraph by paragraph; hover over a paragraph to highlight its original.
- **Original:** the original only.

The translation streams in paragraph by paragraph. Rich text keeps its headings, lists, bold text and links, and inline code isn't translated. Hold `⌥` on the card to see the original for a moment.

While the card is open, it follows your selection: an item you've already translated shows up at once; with System Translation a new item is translated right away; with a language model, Cubby sends an item only after you stay on it for about 0.6 seconds, so items you skip past are never sent, and pressing `↩` during that wait sends it immediately. The preview and the translation card share the same spot: press `Space` or `⌘Y` on the card to switch to the preview, and `⌘T` in the preview to switch back.

### Languages and engine

The top of the card shows:

- **Language pill:** the detected source language and the target language, for example "English (auto-detected) → Japanese". Click it to choose a target language; your choice is remembered and screenshot translation uses it too. The source language is dimmed in the menu.
- **Remember a language for an app:** at the bottom of the language menu, an item such as "Always translate to this when pasting into Slack" (named after the app you're pasting into). Check it to always translate to the current target language when pasting into that app; choose it again to forget. Remembered apps are listed in `Settings › Translation › Target language by app`.
- **Swap button `⇄`:** translates the translation back into the source language, so you can check it. The result isn't saved, and images can't be swapped.
- **Engine chip:** shows the engine in use. Click it to see where your text goes and to open **Translation Settings…**.
- **Privacy line:** below the language pill, one line tells you where the content went, for example "Translated on this Mac; nothing leaves it", "Sent to api.deepseek.com" or "Cached · not sent this time".

### Card actions

While the card is open, the panel's keys act on the translation:

- `↩` or **Paste:** paste the translation into the current app. For rich text, the translation keeps its formatting according to your default paste format. `⌥↩` does the same.
- `⇧↩`: paste the translation as plain text.
- `⌘C` or **Copy:** copy the translation and keep the panel open. `⌘↩` also copies it.
- `⌘S` or **Save:** save the translation as a new item, with "Translated Text" as its source. Not available while recording is paused.

If you press `↩` before the translation is done, the button changes to **Paste When Done** and pastes as soon as it's finished. Copying or pasting a translation never adds a history item; only **Save** does. After pasting, a notice names the engine, for example "Translated with System Translation (on this Mac) and pasted". The card's footer shows the source language and length, plus the engine and how long it took, or "Cached".

### Translate and paste

To skip the card, select an item and press `⌥↩`, or choose **Translate and Paste** from its right-click menu:

- If there's already a translation in the target language, it's pasted right away.
- Otherwise the card shows the progress, for example "Translating 3/12 · esc to cancel". The panel stays open and pastes when the translation is done.
- If something goes wrong, the card explains it in one line with a button such as **Retry**, **Go to Settings** or **Download Languages**. Cubby never falls back to pasting the original.
- If it takes longer than 30 seconds, you'll see "Translation timed out · ⌘T opens the card".
- If the text is already in the target language, you'll see a note such as "Already in English · ⌘T to choose a language", and nothing is pasted.

If you remembered a target language for the app you're pasting into, `⌥↩` uses it.

### Hold ⌥ to preview

Select an item and hold `⌥` for about 0.3 seconds without pressing another key: the card's content fades into the translation, and releasing `⌥` brings the original back. Press `↩` while holding (that is, `⌥↩`) to paste exactly the translation you see. Any other key cancels the preview at once, so `⌥↑` and `⌥↓` still jump to the first and last item. With a language model, Cubby still waits until you've stayed for about 0.6 seconds before sending.

### Cache, the Tr chip and search

- Translations are saved with their item on your Mac, show up instantly the next time and are never sent twice. Each item keeps translations in up to three languages.
- A card with a translation shows a small "Tr" chip next to the favorite star; hover over it to see the languages.
- Search looks in translations too. A card that matches only through its translation shows the first line of the translation with the match highlighted.
- Turn on **Show translations on cards** in `Settings › Translation` to show the first line of the translation on every translated card.
- Deleting an item deletes its translations. `Settings › Translation › Clear All Translations…` deletes only the translations and keeps your history.

### Images

Images in your history, screenshots included, can be translated too, block by block in place, just like screenshot translation.

- On the card, **Compare** becomes a wipe: drag the divider to compare; after dragging or clicking it, `←` `→` nudge it.
- Rest the pointer on a translated block for about 0.4 seconds to see its original; hold `⌥` to see the original image.
- `⌘C` and `↩` copy and paste the translated image, and `⌘S` saves it as a new image item.
- Images longer than 8192 pixels on a side, or larger than 8K, can't be translated.

### Items that can't be translated

Links, files, colors and code snippets aren't translated, and neither is text longer than about 10,000 characters. For these items, `⌘T` and `⌥↩` only beep, and the footer explains why, for example "Code snippets aren't translated", "Links can't be translated" or "Text is too long to translate".

### Text that looks like a secret

With a language model, if an item looks like it contains a secret (an API key, a private key, a token and so on), Cubby doesn't send it, and the card says "Looks like it contains a secret, not sent". If you do want to translate it, click **Translate Anyway**. This applies only to this item, this once, and the service shown; Cubby doesn't remember it. With System Translation the text never leaves your Mac, so it's translated right away. Text that looks like a secret inside an image is never sent and can't be confirmed.

### Translate on copy

Turn on **Translate text when you copy it** in `Settings › Translation` (off by default), and Cubby translates foreign-language text in the background as you copy it, saving the result as that item's translation. Turning it on also turns on **Show translations on cards**, so you can see the results in the list.

- It only uses System Translation on your Mac, never a language model, and never goes online.
- It only works for languages you've already downloaded, and never downloads one.
- It only handles plain text of 2 – 2,000 characters; links, code, colors, files, images and text that looks like a secret are skipped.
- It stops while recording is paused or Low Power Mode is on.

## Translation engines and settings

Translation uses free, offline System Translation by default, and you can connect your own language model in `Settings › Translation`.

Screenshot translation and clipboard translation share the same engine and the same target language. The **Translation** pane only appears on macOS 26 and later.

### System Translation (default)

System Translation is the translation built into macOS. It runs on your Mac, it's free, it works offline, and your text never leaves your Mac.

The first time you translate a language, its language pack has to be downloaded. The translation bar or card tells you it's missing; click **Download Languages**, and Cubby asks macOS to show its download window. Whether to download is up to you, and you confirm it in that macOS window; Cubby never downloads anything for you. After that, translation works offline. Downloaded languages are managed in `System Settings › General › Language & Region › Translation Languages`, and the **Manage Languages…** button in `Settings › Translation` opens that page.

### Set up a language model

Any service compatible with the OpenAI Chat Completions API works. The presets are DeepSeek, Qwen (Alibaba Cloud), Kimi, Zhipu GLM, OpenAI, OpenRouter and Ollama (on this Mac), and you can choose **Custom** for anything else.

1. Open `Settings › Translation` and choose **Large language model** under **Translation Engine**. A **Large Language Model** group appears below.
2. Choose a preset under **Provider**. **Base URL** is filled in for you.
3. Pick a region: Qwen, Kimi and Zhipu GLM have several addresses, so click the globe icon next to the address field and choose **China mainland**, **International** and so on. With **Custom**, enter the service's address yourself. It must start with `https://`; only local addresses such as `localhost` may use `http://`.
4. Paste your key under **API Key** and click **Save Key**. The key goes into your macOS login Keychain, tied to the current address, and the row says **Stored in Keychain**. From then on only its last four characters are shown; click **Remove** to delete it.
5. Under **Model**, click **Refresh** to fetch the model list and choose one from the menu next to the field, or type a model name and press `↩`.
6. Click **Test Connection**. On success you'll see "Connected" with the model, the time it took and a sample translation; otherwise you'll see why it failed.

Once the setup is complete, both screenshot and clipboard translation use this model, and the translation bar and card show its name. To go back, choose **System Translation** under **Translation Engine**; your model settings and key are kept, so choosing **Large language model** again works right away. If you choose **Large language model** before finishing the setup, translating says "Translation isn't set up", and **Open Settings** brings you back here.

### Ollama on your Mac

1. Install and run Ollama on your Mac, and download a model.
2. Choose **Ollama (on this Mac)** under **Provider**. The address becomes `http://localhost:11434/v1`. A local address needs no API key, so that row is hidden.
3. Click **Refresh** and choose a model you've downloaded, or type its name, then click **Test Connection**.

Your text only goes to Ollama on your Mac and never leaves it.

### Target language

`Settings › Translation › Translate into` decides which language you translate into:

- **Automatic (follow system)** (the default): translates into the first of your preferred system languages that differs from the text; text that's already in your system language is translated into English. If your system language is English and so is the text, Cubby asks you to choose a target language on the translation bar or card.
- A specific language: always translate into it. You can choose 简体中文, 繁體中文, English, 日本語, 한국어, Français, Deutsch, Español, Português, Italiano, Русский, Tiếng Việt, ไทย, Bahasa Indonesia and العربية.

Choosing a language from the language menu on the translation bar or the translation card changes this setting too; to go back to automatic, choose **Automatic (follow system)** here. For clipboard translation, a language you remembered for an app comes first: pasting into that app always translates into that language, unless the text is already in it.

### Clipboard settings

The **Clipboard** group at the bottom of `Settings › Translation` has:

- **Translate text when you copy it:** see "Clipboard translation".
- **Show translations on cards:** show the first line of the translation on translated cards.
- **Target language by app:** the apps and languages you remembered from the translation card's language menu. Click the remove button next to an app (**Forget This App's Language**) to delete it.
- **Saved translations:** click **Clear All Translations…** and confirm to delete every translation saved with your history items. Your history itself isn't affected.

### Costs

System Translation and Ollama on your Mac are free. With a cloud language model, your provider charges your own account according to its pricing; Cubby charges nothing and never handles your account. Long text is sent in several requests. Check your usage in your provider's console; if you run out of credit, translating says "Too many requests or no quota left".

## Settings

Open Settings with **Settings…** in the menu bar icon's menu, the gear button in the panel, or `⌘,` while the panel is open. Pick a page in the sidebar on the left: **General**, **History**, **Screenshots**, **Translation** (macOS 26), **Security**, **Privacy** and **About**. You can make the window taller or shorter, and long pages scroll.

### General

- **Appearance:** **Match System** (the default), **Light** or **Dark**, shown as thumbnails. It applies to the panel, the preview, the clothesline and Settings.
- **Language:** **Interface language** can be **System Default** (the default), **English** or **简体中文**. After you switch, click **Restart Now**; Cubby reopens and comes back to Settings. This only changes Cubby's own menus and text; automatic translation still translates into your system language. It's the same setting as Cubby's entry in `System Settings › General › Language & Region › Applications`, so you can change it in either place.
- **Shortcut & Panel:** **Keyboard shortcut** (click it, then press a new combination that includes `⌘`, `⌥` or `⌃`; `F1` – `F12` also work on their own), **Only images** (`⌃⇧V` by default, can be turned off) and **Panel position**, five thumbnails: **Next to the pointer**, **Below the menu bar icon**, **Center of the screen**, **Docked to the right edge** and **Docked to the bottom edge**.
- **Clothesline:** **Hang images at the top of the screen** (on by default), **Show / Hide** (`⌃⌥T` by default, can be turned off), **Also slide down when the pointer rests at the top edge** (on by default) with **Slide down after the pointer rests at the top edge for** (0.3 to 1.2 seconds), and **Photos on the line** with **Take All Down**. See "Clothesline".
- **Pasting:** **When you choose an item** (**Paste into the current app** or **Copy to the clipboard only**) and **Paste text as** (**Original formatting** or **Plain text**; `⇧↩` uses the other one).
- **Startup & Updates:** **Launch at login**, and **Check for updates automatically**, which reads the latest version number from GitHub once a day and never uploads any data. It's on if you left **Remind me about new versions** ticked on the welcome screen or chose **Remind Me** when Cubby asked; otherwise it's off. If you turned on the weekly check in an earlier version, it stays on and now checks daily.

### History

- **Keep up to:** 50 to 2,000 items, 500 by default. When the limit is reached, the oldest items are removed; favorites don't count.
- **Search text in images:** on by default. Turning it off deletes all recognized text.
- **Encryption:** **On**, with "History, images and logs are stored encrypted". It's always on. Right after an update, while Cubby encrypts your existing history, the row shows its progress.
  - If the key can't be read, the row says "History is locked: can't read the key from the keychain"; click **Try Again**. See "Encryption" under Privacy and data.
  - If the key for an older history is missing, the row says "Couldn't find the key for your old history, so Cubby started a new one"; **Show in Finder** reveals the old, still encrypted folder.
- **Items**, **Storage used** and **Data folder**; **Show in Finder** reveals the folder.
- **Clear history:** click **Clear…** and confirm. Favorites are kept.

### Screenshots

- **Shortcut:** **Screenshot shortcut**, which you can change or turn **Off** (then screenshots start only from the menu bar and the panel). The panel shortcut and the screenshot shortcut can't be the same.
- **Saving:** **Save screenshots to**, **Same as macOS screenshots** by default, with **Choose Folder…** and **Reset**; and **Ask where to save each time**, on by default.
- **After Capturing:** **Hang screenshots on the clothesline**, off by default. Only shown while the clothesline is on.

### Translation (macOS 26)

This pane has **Translation Engine** (**System Translation** or **Large language model**), **Translate into**, the **Language packs** row for System Translation or **Provider**, **Base URL**, **API Key**, **Model** and **Test Connection** for a language model, and the **Clipboard** group at the bottom. See "Translation engines and settings".

### Security

- **Address guard:** the switch at the top, on by default, with a summary of the last 30 days: replacements found and pastes verified.
- **Guarded Content:** Bitcoin, Ethereum & EVM chains, TRON, Solana, Litecoin and Bank card; click one to stop or start guarding it.
- **Hints:** **Show the check result after pasting an address** (on by default), and **Tell more accurately whether you copied it** with the Input Monitoring status and **Grant Access**.
- **Security Log:** the latest 20 events (replaced addresses, restores, "Changed by you" and matched pastes) with **Time**, **Event** and **App in Front**.
- At the bottom, **Open System Settings** opens `Privacy & Security › Paste from Other Apps`.

See "Address guard".

### Privacy

- **Permissions:** the status of **Clipboard access**, **Accessibility** and **Screen Recording**, each with a button. It says **Grant Access** where macOS can ask you directly, and **Open System Settings** where the change has to be made there. If direct pasting stops working, repair steps appear here.
- **Pause recording:** nothing you copy while paused is saved.
- **Don't record likely secrets and tokens:** on by default; catches API keys, private keys, JWTs and more, even when copied from a terminal or browser. Content marked as concealed or transient, like passwords from a password manager, is never recorded either way.
- **Ignored Apps:** anything you copy in these apps isn't recorded. Click **Add App…** to add one, or the remove button next to an app (**Stop Ignoring**) to take it off the list. Common password managers are on the list by default.

### About

- The version number.
- **Check for Updates:** checks GitHub right away, whether or not the automatic check is on. If there's a new version, it shows "Version x.y.z is available" with **View & Download**, which opens the release page; if you installed with Homebrew, it offers **Copy Upgrade Command** and **Release Notes** instead.
- **Copy Diagnostic Info:** copies the version, system and permission status for bug reports. It never includes clipboard content.

### Update reminders

When a newer version of Cubby is found, by the automatic check or by **Check for Updates**, Cubby shows it in three places. There are no system notifications.

- **The menu bar icon** gets a blue dot at its top right (VoiceOver reads "Cubby, update available"), and **Version x.y.z Available…** appears at the top of its right-click menu.
- **The panel** shows a blue banner at the top, "Version x.y.z is available", with the version you're running. **View & Download** opens the release page on GitHub. If a permission problem needs your attention, its banner comes first.
- **Settings › About** shows the new version with the same button.

**Not Now** on the banner hides it for that version only, even after a restart. The blue dot and the menu item stay, and a newer version brings the banner back.

If you installed with Homebrew, the banner says to run `brew upgrade --cask cubby` in Terminal, and Settings › About offers the same buttons:

- **Copy Upgrade Command** copies the command, and the button shows **Copied** for a moment. The command isn't added to your clipboard history.
- **Release Notes** opens the release page.

Cubby remembers the latest version it found, so the dot and the banner are back right after a restart without going online. Once you've upgraded, they disappear. Cubby never downloads or installs updates by itself.

If you upgraded from an earlier version and the automatic check was off, the panel asks once, "Remind you about new versions?". **Remind Me** turns on the check and checks right away; **No Thanks** keeps it off. Either way, Cubby doesn't ask again, and you can change it later in `Settings › General`.

## Privacy and data

Your data stays on your Mac. Cubby only goes online to check for a new version, which you can turn off, and to translate with a language model you set up.

### What's stored on your Mac

- Your history lives, encrypted, in `~/Library/Application Support/Cubby/Vault`: `history.cubby` holds text, links, colors, rich-text formatting, file paths (not the files themselves), source apps, times, favorites, translations and text recognized in images; the `Blobs` folder holds images and translated images.
- Only your macOS user can open this folder, and it's excluded from Time Machine backups.
- The address guard's security log is `Vault/security-log.cubby`, also encrypted. It holds shortened values only, for up to 90 days.
- Settings are stored in `~/Library/Preferences/io.github.no1coder.Cubby.plist`, with no clipboard content and no API keys.
- API keys are stored in your login Keychain under `io.github.no1coder.Cubby.translation`, never in settings, history or logs.
- The frozen screen image of a screenshot exists only in memory, and canceling leaves no trace. Pinned images disappear when Cubby quits.

### Encryption

Everything Cubby keeps that comes from your clipboard is stored encrypted: history, recognized text, translations, images, thumbnails, translated images, the security log and backups. It's always on, and `Settings › History` shows **Encryption: On**.

- **The key:** a random key in your login Keychain (`io.github.no1coder.Cubby.history`). Only Cubby's signature is trusted to read it.
- **What it protects against:** other apps and scripts running as you quietly reading the data folder (they now see only encrypted data), the folder being copied or synced somewhere by mistake, and file names revealing which images you copied.
- **What it doesn't protect against:** malware with administrator rights or your login password, apps reading the clipboard at the moment you copy, apps you've allowed to use Accessibility or Screen Recording, copies you hand to other apps, and any app you allow when the Keychain asks. Keep FileVault on to encrypt your disk.
- **Not encrypted:** your settings (no clipboard content), screenshots you save to a folder yourself, and API keys (already in the Keychain).
- **Files for other apps:** dropping an image in Finder makes no temporary copy. When an app needs a file, for example when you open an image with `⌘O` or drop it on an app that accepts only files, Cubby writes a decrypted copy to a temporary folder (`$TMPDIR/Cubby-Shared`). Other apps running as you can read it. Cubby deletes these copies when it quits and again at its next launch.

**After updating.** The first time you open an updated Cubby, it encrypts your existing history. The panel shows "Encrypting your history…" for a moment, and the items appear when it's done. The old, unencrypted files are deleted only after the encrypted copy has been checked.

**Going back to an older version.** Versions 0.3.3 and earlier can't read the encrypted history and start with an empty one. When you update again, what you copied in the meantime is merged in, but items you deleted or cleared while on the older version come back.

**History is locked.** If Cubby can't read the key, for example because you clicked **Deny** when macOS asked, the panel shows **History is locked** with **Try Again** and **Not Now**, and `Settings › History` shows the same. Nothing is lost: what you copy is kept in memory until Cubby can save it. Click **Try Again** and allow, and those items are merged into your history.

**The key is missing.** If the key is gone but an encrypted history exists, for example after resetting your login Keychain, Cubby never deletes it. It renames the folder to `Vault-unreadable-` followed by the date, starts a new history, and `Settings › History` offers **Show in Finder**. If the key comes back, Cubby restores the old history automatically.

### If macOS asks about the key

macOS may ask whether an app can use `io.github.no1coder.Cubby.history` in your keychain.

- The app name in the prompt can be faked. **Only allow it right after you've installed or updated Cubby, and only when it's Cubby itself asking.** At any other time, or if any other app asks, click **Deny**.
- Denying never loses data. Cubby shows **History is locked** and keeps new copies in memory; click **Try Again** and allow, and they're merged back into your history.
- Releases share a stable signature, so normal updates don't ask. You'll only see the prompt once after running a differently signed build, for example one you built yourself.

### What's never recorded

- Content that password managers and other apps mark as concealed, transient or auto-generated.
- Anything copied in an app on your **Ignored Apps** list.
- Text that looks like an API key, a private key or a JWT (on by default; you can turn it off). This is a best-effort check and can't recognize every format.
- Anything copied while recording is paused.

### When Cubby goes online

Cubby has no analytics, telemetry or crash reporting. It sends a request only in two cases:

- **Checking for updates:** when you click **Check for Updates**, and once a day if **Check for updates automatically** is on, Cubby asks `api.github.com` for the latest release and reads only its version number. The automatic check is ticked by default on the welcome screen of a new install, and you can turn it off in `Settings › General`. No data is uploaded, and no clipboard content is sent.
- **Translating with a language model:** only while the engine is a language model and you translate a screenshot or an item (including when the translation card follows your selection and you stay on an item for about 0.6 seconds, or when you hold `⌥` to preview), and when you click **Refresh** or **Test Connection** in Settings. Requests go only to the address you configured; remote addresses must use HTTPS, and redirects to other hosts are refused, so your key is never forwarded anywhere else.

What's sent to a language model:

- Screenshots: the text recognized in the selection, plus the target language, the detected source language, the model name and your API key.
- Clipboard items: the text of that item, or for an image, only the text recognized in it. In rich text, link addresses are replaced with placeholders, and inline code and code blocks aren't sent.
- **Test Connection** sends only the word Hello; **Refresh** sends only your API key.

Never sent: the images themselves, text under a mosaic, text that looks like a secret unless you confirm it, text that looks like a secret inside an image, and the other items in your history. System Translation, translate on copy, recognizing text in images and extracting text all happen on your Mac without going online. Opening a link with `⌘O` hands it to your default browser; Cubby doesn't fetch link previews.

### Delete your data

- **One item:** select it and press `⌘⌫`.
- **All history:** **Clear History…** in the menu bar icon's menu, or `Settings › History`. Favorites are kept.
- **All translations:** `Settings › Translation › Clear All Translations…`.
- **Text recognized in images:** turn off `Settings › History › Search text in images`.
- **Your API key:** click **Remove** in `Settings › Translation`.
- **Everything:** if you installed with Homebrew, run `brew uninstall --zap --cask cubby`. Otherwise quit Cubby, delete `/Applications/Cubby.app` and `~/Library/Application Support/Cubby`, then run `defaults delete io.github.no1coder.Cubby` and `tccutil reset All io.github.no1coder.Cubby` in Terminal. If you saved an API key, remove it in Settings first, or delete the `io.github.no1coder.Cubby.translation` item in Keychain Access. To remove the history key too, delete the `io.github.no1coder.Cubby.history` item in Keychain Access after deleting the data folder.

For the full details, see the [privacy policy (PRIVACY.md)](https://github.com/no1coder/cubby/blob/main/PRIVACY.md).

## FAQ and troubleshooting

If something doesn't work as expected, start here.

### Choosing an item only copies it

- Check that `Settings › General › When you choose an item` is set to **Paste into the current app**, and that **Accessibility** reads **Allowed** in `Settings › Privacy`.
- After an update, a build from source or switching to a version with a different signature, System Settings may still show Cubby as allowed while the permission no longer works. The panel then says "Direct paste stopped working". Click **Fix…** and follow the steps: select Cubby in `System Settings › Privacy & Security › Accessibility`, click **−** to remove it, then come back to Cubby, click **Grant Access Again** and turn on Cubby in the list that appears.
- If it still doesn't work, run `tccutil reset Accessibility io.github.no1coder.Cubby` in Terminal and grant access again.

### Screenshots don't start

- The first screenshot needs Screen Recording. In the **Allow Screen Recording to take screenshots** window, click **Open System Settings** and turn on Cubby. If screenshots still don't work after that, click **Quit & Reopen Cubby** in the same window.
- The screenshot shortcut may be turned off or taken by another app; check `Settings › Screenshots`. You can always start a screenshot from the menu bar icon's menu or the camera button in the panel.
- If you see "Couldn't capture the screen. Check the permission prompt.", look for a macOS prompt waiting for your answer.

### macOS asks every time I copy

This is the clipboard privacy protection in macOS 15.4 and later. The prompt only offers **Allow Paste** and **Don't Allow Paste**; there's no "Always Allow". Set Cubby to **Allow** in `System Settings › Privacy & Security › Paste from Other Apps` (**Paste** on macOS 15.4 – 15.x). **Allow Clipboard Access…** in the menu bar icon's menu and **Open System Settings** on the panel banner both open that page. If Cubby isn't in the list yet, copy something, then click **Grant Access** in `Settings › Privacy`.

### There's no Translate button

Translation needs macOS 26 or later. On macOS 14 and 15 the screenshot toolbar has no **Translate** button, `⌘T` and `⌥↩` in the panel only beep, and Settings has no **Translation** pane.

### It says a language pack is missing

System Translation needs a language pack the first time you use a language. Click **Download Languages** and confirm the download in the macOS window that appears, or download languages ahead of time in `System Settings › General › Language & Region › Translation Languages`. **Translate text when you copy it** never downloads language packs and skips languages that aren't downloaded.

### The API key is invalid, or saved for another address

- "The API key is invalid or not allowed" or "DeepSeek rejected the API key": the key may have expired, been mistyped or lack access to the model. In `Settings › Translation`, click **Remove**, paste the key again, click **Save Key** and then **Test Connection**.
- "The API key was saved for A. Enter it again for B.": a key is tied to the address it was saved for. After you change the base URL or the region, the old key is never sent to the new address; enter a key for the new one.
- "Too many requests or no quota left": try again later, or check the balance of your provider account.

### macOS asks whether Cubby may use the Keychain

When Cubby reads its history key or your saved API key, macOS may ask whether Cubby may use the Keychain item. Releases share a stable signature, so this normally happens only once after building from source or running a differently signed build.

- The app name in the prompt can be faked. Only allow it right after you've installed or updated Cubby, and only when it's Cubby itself asking. At any other time, or if any other app asks, click **Deny**.
- If you denied the history key, the panel shows **History is locked**; click **Try Again** and allow. What you copied in the meantime is merged into your history. See "Encryption" under Privacy and data.
- If you denied the API key, Settings shows "Couldn't access the Keychain, so the saved API key can't be used."; click **Try Again** to try once more.

### Cubby says an address was replaced

The clipboard changed to another address or card number of the same kind right after you copied one, while the same app stayed in front. Compare the two values in the warning. If you didn't make the change, click **Restore What I Copied** and check your Mac for software you don't recognize; if you did (for example, you copied a second address in the same app quickly), click **I Changed It Myself**. Allowing Input Monitoring in `Settings › Security` lets Cubby tell your own copies apart. See "Address guard".

### The panel doesn't appear

- Check that the Cubby icon is in the menu bar; Cubby has no Dock icon. Clicking the icon opens the panel too.
- If another app already uses your shortcut, Cubby tells you so and goes back to the previous shortcut. Record a different combination in `Settings › General`.
- The panel opens where **Panel position** says; with several displays, it opens on the display with the pointer.

### Report a problem

Open an issue on [GitHub Issues](https://github.com/no1coder/cubby/issues/new/choose). Pasting the output of **Copy Diagnostic Info** from `Settings › About` helps a lot, and it never includes clipboard content. Please keep real keys and other sensitive content out of your screenshots and descriptions. Report security issues privately as described in [SECURITY.md](https://github.com/no1coder/cubby/blob/main/SECURITY.md).

## Shortcut reference

All shortcuts, grouped by where you use them; the ones marked macOS 26 need macOS 26 or later.

### Panel

- `⇧⌘V` — open / close the panel (global, can be changed)
- `⌃⇧V` — only images (global, can be changed or turned off)
- `↑` `↓` or `⌃P` `⌃N` — choose an item
- `←` `→` — choose an item in the image grid or the bottom shelf (while the search field is empty)
- `⌥↑` `⌥↓` or `Home` `End` — first / last item
- `Page Up` `Page Down` — up / down 5 items
- `↩` or double-click — paste
- `⇧↩` — paste in the other format
- `⌘↩` — copy only
- `⌘1` – `⌘9` — quick paste
- `Space` / `⌘Y` — preview (`Space` only while the search field is empty)
- `⇥` / `⇧⇥` — next / previous category
- `⌘P` — favorite / unfavorite
- `⇧⌘P` — pin the image to the screen
- `⌘L` — hang the image on the clothesline / take it down
- `⌘B` — pick words
- `⌘⌫` — delete
- `⌘Z` — undo delete
- `⌘O` — open a link or file
- `⌘,` — Settings
- `⌘T` (or `⇧⌘T`) — translate (macOS 26)
- `⌥↩` — translate and paste (macOS 26)
- Hold `⌥` — preview the translation (macOS 26)
- `esc` — close, one step at a time

### Clothesline

- `⌃⌥T` — show / hide the clothesline (global, can be changed or turned off)
- Drag down from an empty spot in the menu bar, or rest the pointer at the top edge — show the clothesline
- Double-click a photo — copy
- Drag a photo — drop it into another app
- Click a photo — enlarge and annotate
- `↩` — Done & Hang Back (while enlarged)
- `⌘C` — copy the annotated image (while enlarged)
- `esc` — close without saving (while enlarged)

### Translation card

- `↩` or `⌥↩` — paste the translation
- `⇧↩` — paste the translation as plain text
- `⌘C` or `⌘↩` — copy the translation
- `⌘S` — save as a new item
- `←` `→` — switch between Translated, Compare and Original; nudge the image divider when it has focus
- Hold `⌥` — see the original
- `Space` / `⌘Y` — switch to the preview
- `⌘T` — close the card
- `esc` — cancel the translation, or close the card

### Screenshot

- `⇧⌘2` — take a screenshot (global, can be changed)
- `⇥` / `⇧⇥` or scroll — step through overlapping windows
- `Space` — enter / leave clean window mode (over a window)
- `⌥`-click — clean window capture without the shadow
- `⌘A` — select the whole screen
- Hold `⇧` / `⌥` / `Space` while dragging — square / from the center / move the selection
- Arrow keys — move the selection or the selected annotation 1 pt (10 pt with `⇧`)
- `R` `O` `A` `P` `H` `M` `T` `N` — rectangle, ellipse, arrow, pen, highlighter, mosaic, text, number
- `V` — back to the pointer
- `1` – `8` — choose a color
- `[` / `]` — thinner / thicker
- `⌫` — delete the selected annotation
- `⌘Z` / `⇧⌘Z` — undo / redo
- `C` — copy the color under the magnifier (RGB while holding `⇧`)
- `↩`, `⌘C` or double-click — finish and copy
- `⌘↩` — finish typing in a text box; otherwise finish and copy
- `⌘S` — save
- `⌘P` — pin to the screen
- `⌘T` — extract text
- Right-click — clear the selection; cancel when there's no selection
- `esc` — cancel (press twice once you've drawn something)

### Screenshot translation

- `⇧⌘T` — translate; with a translation, switch between Original and Translated; after a failure, retry
- Hold `Space` — see the original
- `←` `→` — nudge the Compare divider after dragging it (bigger steps with `⇧`)
- `⌘Z` / `⇧⌘Z` — undo / redo the translation
- `⌘T` — copy the translated text while the switch is on Translated
- `esc` — cancel a translation in progress; close the bar after a failure

### Pinned image

- Drag — move
- Scroll or pinch — zoom
- `⌘0` — actual size
- `⌘C` — copy
- `⌘S` — save
- `⌘W`, `esc` or double-click — close
