#!/usr/bin/env python3
# 生成截图翻译视觉验收语料 corpus.json（坐标为点，左上原点；译文为手写的预置译文）。
# 用法：python3 Tests/TranslationQA/generate-corpus.py  → 覆盖同目录的 corpus.json
# 运行验收：swift build && .build/debug/Cubby --translate-qa Tests/TranslationQA/corpus.json /tmp/cubby-translate-qa
import json
import os

def lh_of(size, lh=None):
    return lh if lh is not None else round(size * 1.35)

def T(text, x, y, size=13, weight=None, color=None, width=None, lh=None, align=None, lang=None, tr=None, marker=None):
    d = {"text": text, "x": x, "y": y, "size": size}
    if weight: d["weight"] = weight
    if color: d["color"] = color
    if width: d["width"] = width
    if lh: d["lineHeight"] = lh
    if align: d["align"] = align
    if lang: d["lang"] = lang
    if tr is not None: d["translation"] = tr
    if marker: d["marker"] = marker
    return d

def R(x, y, w, h, fill=None, radius=None, stroke=None, oval=False, gradient=None, noise=None):
    d = {"rect": [x, y, w, h]}
    if fill or gradient or noise is not None:
        p = {}
        if fill: p["color"] = fill
        if gradient: p["gradient"] = gradient
        if noise is not None: p["noise"] = noise
        d["fill"] = p
    if radius: d["radius"] = radius
    if stroke: d["stroke"] = stroke
    if oval: d["oval"] = True
    return d

def button(x, y, w, h, label, tr, fill="#FFFFFF", color="#1D1D1F", stroke=None, radius=7, size=13, weight=None, lang=None):
    lh = lh_of(size)
    return R(x, y, w, h, fill=fill, radius=radius, stroke=stroke), T(label, x + w / 2, y + (h - lh) / 2, size, weight, color, align="center", lang=lang, tr=tr)

scenes = []
def scene(id, title, w, h, target, bg, shapes, texts, scale=2):
    s = {"id": id, "title": title, "width": w, "height": h, "target": target, "background": bg, "shapes": shapes, "texts": texts}
    if scale != 2: s["scale"] = scale
    scenes.append(s)

# 1 prototype-like storage pane
sh, tx = [], []
sh += [R(0, 0, 900, 40, fill="#ECECEC"), R(0, 39, 900, 1, fill="#D8D8DC")]
for i, c in enumerate(["#FF5F57", "#FEBC2E", "#28C840"]):
    sh.append(R(14 + 20 * i, 14, 12, 12, fill=c, oval=True))
tx.append(T("Settings", 450, 11, 13, "semibold", "#4D4D4D", align="center", tr="设置"))
sh += [R(0, 40, 220, 560, fill="#F2F2F5"), R(220, 40, 1, 560, fill="#D8D8DC")]
sh += [R(10, 52, 200, 28, fill="#E3E3E8", radius=7), R(18, 61, 10, 10, fill="#8E8E93", oval=True)]
tx.append(T("Search", 34, 57, 13, color="#8E8E93", tr="搜索"))
items = [("General", "#8E8E93", "通用"), ("Appearance", "#1C1C1E", "外观"), ("Notifications", "#FF3B30", "通知"),
         ("Privacy & Security", "#007AFF", "隐私与安全性"), ("Storage", "#FFFFFF", "储存空间"), ("Advanced", "#636366", "高级")]
for i, (label, icon, tr) in enumerate(items):
    y = 92 + i * 32
    selected = label == "Storage"
    if selected: sh.append(R(10, y, 200, 30, fill="#0A84FF", radius=7))
    sh.append(R(18, y + 5, 20, 20, fill=icon if not selected else "#FFFFFF", radius=5))
    tx.append(T(label, 46, y + 6, 13, color="#FFFFFF" if selected else "#1D1D1F", tr=tr))
tx.append(T("Storage", 244, 58, 22, "bold", "#1D1D1F", tr="储存空间"))
tx.append(T("Your Mac is using 186.2 GB of 494.4 GB. Optimize storage to free up space automatically by removing items you no longer need, such as watched movies, old email attachments and duplicate downloads.",
            244, 96, 13, color="#3C3C43", width=370, lh=18,
            tr="你的 Mac 已使用 494.4 GB 中的 186.2 GB。优化储存空间可自动移除不再需要的项目（例如已看过的影片、旧的邮件附件和重复的下载项），从而释放空间。"))
tx.append(T("Recommendations", 244, 184, 15, "semibold", "#1D1D1F", tr="建议"))
recs = [("Store in iCloud — Keep files and photos in iCloud and free up space when needed.", "储存在 iCloud 中 — 将文件和照片保留在 iCloud 中，并在需要时释放空间。"),
        ("Optimize Storage — Remove movies and TV shows you’ve already watched from this Mac.", "优化储存空间 — 从这台 Mac 上移除已看过的电影和电视节目。"),
        ("Empty Trash Automatically — Erase items that have been in the Trash for more than 30 days.", "自动清倒废纸篓 — 抹掉在废纸篓中存放超过 30 天的项目。")]
for i, (s, t) in enumerate(recs):
    tx.append(T(s, 262, 212 + i * 44, 13, color="#3C3C43", width=350, lh=18, tr=t, marker="•"))
for (x, w, label, tr, fill, color, weight) in [(244, 80, "Cancel", "取消", "#FFFFFF", "#1D1D1F", None), (334, 110, "Review Files", "查看文件", "#FFFFFF", "#1D1D1F", None), (454, 96, "Optimize", "优化", "#007AFF", "#FFFFFF", "medium")]:
    s, t = button(x, 360, w, 28, label, tr, fill=fill, color=color, stroke="#C7C7CC" if fill == "#FFFFFF" else None, weight=weight)
    sh.append(s); tx.append(t)
sh.append(R(640, 60, 240, 190, fill="#F5F5F7", radius=10, stroke="#E4E4E8"))
rows = [("Documents", "文稿", "12.4 GB", None, "#6E6E73"), ("Photos", "照片", "48.1 GB", None, "#6E6E73"), ("Items in Trash", "废纸篓中的项目", "1,284", None, "#6E6E73"),
        ("iCloud Drive", "iCloud 云盘", "Synced", "已同步", "#248A3D"), ("Last backup:", "上次备份：", "Yesterday at 21:30", "昨天 21:30", "#6E6E73")]
for i, (label, tr, value, vtr, vcolor) in enumerate(rows):
    y = 60 + i * 38
    if i > 0: sh.append(R(654, y, 212, 1, fill="#E4E4E8"))
    tx.append(T(label, 654, y + 10, 13, color="#1D1D1F", tr=tr))
    tx.append(T(value, 866, y + 10, 13, color=vcolor, align="right", tr=vtr))
tx.append(T("Cache location", 640, 266, 11, "medium", "#8E8E93", tr="缓存位置"))
tx.append(T("~/Library/Caches/com.example.app", 640, 284, 12, color="#1D1D1F"))
tx.append(T("API key: sk-live-8f3a9c21e7d4b5a6c7d8e9f0", 640, 308, 12, color="#1D1D1F"))
sh.append(R(244, 430, 636, 140, radius=12, gradient=["#5E5CE6", "#0A84FF"]))
tx.append(T("Get 2 TB of iCloud+ free for 3 months", 268, 456, 20, "bold", "#FFFFFF", tr="免费畅享 3 个月 2 TB iCloud+"))
tx.append(T("Offer ends October 31. Cancel anytime.", 268, 490, 13, color="#FFFFFF", tr="优惠截至 10 月 31 日，可随时取消。"))
s, t = button(740, 520, 116, 32, "Learn More", "了解更多", fill="#FFFFFF", color="#1D1D1F", radius=16, weight="semibold")
sh.append(s); tx.append(t)
scene("prototype-storage", "Prototype-like Storage pane (light UI, sidebar, list, buttons, card, gradient banner)", 900, 600, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)

# 2 dark UI
sh, tx = [R(20, 20, 600, 340, fill="#2A2A2A", radius=10, stroke="#3A3A3C")], []
tx.append(T("Display", 40, 34, 17, "bold", "#FFFFFF", tr="显示器"))
drows = [("True Tone", "原彩显示", "Adjusts colors to match the light around you", "根据周围环境光自动调整颜色", True),
         ("Night Shift", "夜览", "Warmer colors after sunset", "日落后使用更暖的色调", False),
         ("Automatically adjust brightness", "自动调节亮度", "Uses the ambient light sensor", "使用环境光传感器", True)]
for i, (a, at, b, bt, on) in enumerate(drows):
    y = 72 + i * 56
    tx.append(T(a, 40, y + 8, 13, color="#FFFFFF", tr=at))
    tx.append(T(b, 40, y + 27, 11, color="#A1A1A6", tr=bt))
    sh.append(R(560, y + 14, 38, 22, fill="#30D158" if on else "#48484A", radius=11))
    sh.append(R(on and 576 or 562, y + 16, 18, 18, fill="#FFFFFF", oval=True))
    sh.append(R(40, y + 54, 560, 1, fill="#3A3A3C"))
tx.append(T("Refresh Rate", 40, 248, 13, color="#FFFFFF", tr="刷新率"))
sh.append(R(470, 242, 130, 26, fill="#3A3A3C", radius=6))
tx.append(T("ProMotion", 482, 246, 13, color="#FFFFFF", tr="ProMotion"))
for (x, w, label, tr, fill) in [(40, 110, "Advanced…", "高级…", "#3A3A3C"), (510, 90, "Done", "完成", "#0A84FF")]:
    s, t = button(x, 306, w, 28, label, tr, fill=fill, color="#FFFFFF")
    sh.append(s); tx.append(t)
scene("dark-ui", "Dark UI settings panel with secondary gray text and toggles", 640, 380, "zh-Hans", {"color": "#1E1E1E"}, sh, tx)

# 3 buttons
sh, tx = [], []
for (x, w, label, tr, fill, color, weight) in [(30, 110, "Cancel", "取消", "#E5E5EA", "#1D1D1F", None), (152, 120, "Continue", "继续", "#007AFF", "#FFFFFF", "semibold"),
                                                 (284, 110, "Delete", "删除", "#FF3B30", "#FFFFFF", None), (406, 120, "Install", "安装", "#34C759", "#FFFFFF", "semibold")]:
    s, t = button(x, 30, w, 30, label, tr, fill=fill, color=color, radius=8, weight=weight)
    sh.append(s); tx.append(t)
for (x, w, label, tr, fill, color, stroke, radius) in [(30, 160, "Add to Library", "添加到资料库", "#FFFFFF", "#007AFF", "#007AFF", 16), (206, 120, "Download", "下载", "#1D1D1F", "#FFFFFF", None, 16),
                                                        (342, 184, "Share Feedback", "分享反馈", "#E8F0FE", "#0B57D0", None, 8)]:
    s, t = button(x, 90, w, 32, label, tr, fill=fill, color=color, stroke=stroke, radius=radius)
    sh.append(s); tx.append(t)
sh += [R(30, 150, 300, 28, fill="#E5E5EA", radius=7), R(32, 152, 98, 24, fill="#FFFFFF", radius=6), R(230, 156, 1, 16, fill="#C7C7CC")]
for (cx, label, tr) in [(81, "Day", "日"), (180, "Week", "周"), (280, "Month", "月")]:
    tx.append(T(label, cx, 150 + (28 - 18) / 2, 13, color="#1D1D1F", align="center", tr=tr))
tx.append(T("Forgot password?", 30, 206, 13, color="#007AFF", tr="忘记密码？"))
s, t = button(200, 204, 70, 22, "Beta", "测试版", fill="#FFE8CC", color="#C25400", radius=11, size=11, weight="semibold")
sh.append(s); tx.append(t)
scene("buttons", "Colored buttons, pills, segmented control, tag and link", 560, 250, "zh-Hans", {"color": "#F5F5F7"}, sh, tx)

# 4 gradient banner
sh, tx = [], []
tx.append(T("Make every screenshot count", 48, 56, 32, "bold", "#FFFFFF", tr="让每一张截图都物尽其用"))
tx.append(T("Annotate, translate and share in seconds — right where you capture.", 48, 112, 15, color="#FFFFFF", width=420, lh=22, tr="截图后即可标注、翻译与分享，几秒钟就能完成。"))
s, t = button(48, 200, 150, 40, "Try It Free", "免费试用", fill="#FFFFFF", color="#7B61FF", radius=20, size=15, weight="semibold")
sh.append(s); tx.append(t)
scene("gradient-banner", "Gradient banner (plate backdrop expected) with a solid white pill", 720, 290, "zh-Hans", {"gradient": ["#FF6B6B", "#7B61FF"]}, sh, tx)

# 5 photo noise
sh, tx = [], []
tx.append(T("Golden Hour at the Coast", 40, 236, 28, "bold", "#FFFFFF", tr="海岸边的黄金时刻"))
tx.append(T("Shot on iPhone · 26 mm · f/1.8", 40, 280, 14, color="#FFFFFF", tr="使用 iPhone 拍摄 · 26 毫米 · f/1.8"))
tx.append(T("Waves roll in as the sun sets behind the cliffs, painting the sky in warm orange and pink.", 40, 316, 14, color="#FFFFFF", width=520, lh=20,
            tr="夕阳落到悬崖背后，海浪翻涌而来，把天空染成温暖的橙色和粉色。"))
s, t = button(626, 24, 64, 24, "Live", "实况", fill="#1C1C1E", color="#FFFFFF", radius=6, size=12, weight="semibold")
sh.append(s); tx.append(t)
scene("photo-noise", "Photo-like noisy background with white captions (plate expected)", 720, 380, "zh-Hans", {"noise": 7}, sh, tx)

# 6 paragraph
tx = [T("About Clipboard History", 40, 32, 22, "bold", "#1D1D1F", tr="关于剪贴板历史"),
      T("Cubby keeps a searchable history of everything you copy, including text, images, links and files. Items stay on this Mac and are never uploaded. You can pin frequently used snippets, organize them into collections, and paste any item with a single keystroke.",
        40, 76, 13, color="#1D1D1F", width=520, lh=19, tr="Cubby 会保存你拷贝过的所有内容的可搜索历史记录，包括文本、图片、链接和文件。所有项目都只保存在这台 Mac 上，绝不会上传。你可以固定常用片段、将它们整理到收藏夹中，并通过一次按键粘贴任意项目。"),
      T("Older items are removed automatically after thirty days unless they are pinned. To change how long items are kept, open Settings and choose History.",
        40, 180, 13, color="#1D1D1F", width=520, lh=19, tr="除非已固定，较早的项目会在三十天后自动移除。若要更改项目的保留时长，请打开“设置”并选择“历史记录”。"),
      T("Last updated September 27, 2026", 40, 250, 11, color="#86868B", tr="最后更新于 2026 年 9 月 27 日")]
scene("paragraph", "Article: title, two paragraphs, caption", 620, 290, "zh-Hans", {"color": "#FFFFFF"}, [], tx)

# 7 lists
tx = [T("Before You Begin", 40, 26, 17, "semibold", "#1D1D1F", tr="开始之前")]
bl = [("Copy anything: text, images, files and links.", "拷贝任何内容：文本、图片、文件和链接。"),
      ("Search your history instantly with fuzzy matching, even across thousands of items stored over several months.", "使用模糊匹配即时搜索历史记录，即使是数月来储存的数千个项目也能快速找到。"),
      ("Pin snippets you use every day.", "固定每天都会用到的片段。")]
y = 60
for s, t in bl:
    tx.append(T(s, 58, y, 13, color="#1D1D1F", width=500, lh=19, tr=t, marker="•"))
    y += 19 * (2 if len(s) > 80 else 1) + 8
tx.append(T("Set Up", 40, 176, 17, "semibold", "#1D1D1F", tr="设置步骤"))
nl = [("Open Cubby from the menu bar.", "从菜单栏打开 Cubby。"), ("Choose Settings, then click Shortcuts to pick a hotkey.", "选取“设置”，然后点按“快捷键”以选择一个热键。"),
      ("Press the hotkey anywhere to show your clipboard history.", "在任意位置按下该热键即可显示剪贴板历史记录。")]
for i, (s, t) in enumerate(nl):
    tx.append(T(s, 62, 208 + i * 27, 13, color="#1D1D1F", width=500, lh=19, tr=t, marker=f"{i + 1}."))
scene("lists", "Bulleted and numbered lists (markers must stay)", 620, 300, "zh-Hans", {"color": "#FFFFFF"}, [], tx)

# 8 columns
tx = [T("Screenshots", 40, 30, 15, "semibold", "#1D1D1F", tr="截图"),
      T("Screenshots are saved to the history automatically. Select any region of the screen, annotate it with arrows, text and highlights, then copy it or drag it straight into another app.",
        40, 58, 13, color="#3C3C43", width=320, lh=19, tr="截图会自动保存到历史记录中。选择屏幕上的任意区域，用箭头、文字和高亮进行标注，然后拷贝或直接拖到其他应用中。"),
      T("Privacy", 400, 30, 15, "semibold", "#1D1D1F", tr="隐私"),
      T("Everything stays on your Mac. Cubby never uploads your clipboard, and it skips passwords and other sensitive items copied from password managers.",
        400, 58, 13, color="#3C3C43", width=320, lh=19, tr="所有内容都保留在你的 Mac 上。Cubby 从不上传你的剪贴板，并会跳过从密码管理器中拷贝的密码和其他敏感项目。")]
scene("columns", "Two columns", 760, 220, "zh-Hans", {"color": "#FFFFFF"}, [R(380, 24, 1, 170, fill="#E5E5EA")], tx)

# 9 table
sh = [R(20, 20, 600, 32, fill="#F5F5F7"), R(20, 52, 600, 1, fill="#D2D2D7")]
tx = [T("Setting", 36, 27, 12, "semibold", "#6E6E73", tr="设置"), T("Status", 330, 27, 12, "semibold", "#6E6E73", tr="状态"), T("Updated", 604, 27, 12, "semibold", "#6E6E73", align="right", tr="更新时间")]
trows = [("Automatic updates", "自动更新", "On", "开", "2 days ago", "2 天前"), ("Security responses", "安全响应", "Off", "关", "1 week ago", "1 周前"),
         ("App Store downloads", "App Store 下载项", "On", "开", "Yesterday", "昨天"), ("System data files", "系统数据文件", "Pending", "待处理", "Today", "今天")]
for i, (a, at, b, bt, c, ct) in enumerate(trows):
    y = 53 + i * 34
    if i % 2 == 1: sh.append(R(20, y, 600, 34, fill="#FAFAFA"))
    sh.append(R(20, y + 33, 600, 1, fill="#E5E5EA"))
    tx += [T(a, 36, y + 8, 13, color="#1D1D1F", tr=at), T(b, 330, y + 8, 13, color="#1D1D1F", tr=bt), T(c, 604, y + 8, 13, color="#6E6E73", align="right", tr=ct)]
scene("table", "Table with header row, stripes and a right-aligned column", 640, 210, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)

# 10 centered
sh = [R(268, 30, 64, 64, radius=14, gradient=["#34C759", "#007AFF"])]
tx = [T("Welcome to Cubby", 300, 110, 26, "bold", "#1D1D1F", align="center", tr="欢迎使用 Cubby"),
      T("A tidy clipboard history and screenshot tool that lives in your menu bar.", 300, 152, 14, color="#6E6E73", width=380, lh=20, align="center", tr="一个住在菜单栏里、井井有条的剪贴板历史与截图工具。")]
s, t = button(220, 222, 160, 36, "Get Started", "开始使用", fill="#007AFF", color="#FFFFFF", radius=8, size=14, weight="semibold")
sh.append(s); tx.append(t)
tx.append(T("Not Now", 300, 276, 13, color="#007AFF", align="center", tr="以后再说"))
scene("centered", "Centered onboarding: title, two-line subtitle, button, link", 600, 320, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)

# 11 sidebar
sh, tx = [R(0, 0, 240, 440, fill="#F2F2F5"), R(240, 0, 1, 440, fill="#D8D8DC")], []
y = 18
sections = [("Favorites", "个人收藏", [("Recents", "最近使用", "#007AFF"), ("Applications", "应用程序", "#5856D6"), ("Desktop", "桌面", "#34AADC"), ("Documents", "文稿", "#8E8E93"), ("Downloads", "下载", "#FF9500")]),
            ("Locations", "位置", [("iCloud Drive", "iCloud 云盘", "#0A84FF"), ("Network", "网络", "#8E8E93")]),
            ("Tags", "标签", [("Red", "红色", "#FF3B30"), ("Important", "重要", "#FF9500")])]
for (h, ht, items) in sections:
    tx.append(T(h, 18, y, 11, "semibold", "#8E8E93", tr=ht))
    y += 22
    for (label, tr, c) in items:
        if label == "Documents": sh.append(R(8, y - 2, 224, 28, fill="#DCDCE0", radius=6))
        if h == "Tags": sh.append(R(22, y + 7, 10, 10, fill=c, oval=True))
        else: sh.append(R(18, y + 3, 18, 18, fill=c, radius=4))
        tx.append(T(label, 44, y + 3, 13, color="#1D1D1F", tr=tr))
        y += 30
    y += 10
tx.append(T("No Selection", 360, 200, 15, color="#8E8E93", align="center", tr="未选择"))
scene("sidebar", "Finder-like sidebar with section headers, icons and a selected row", 480, 440, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)

# 12 form
sh, tx = [], []
frows = [("Name:", "姓名：", "John Appleseed", "John Appleseed"), ("Email:", "电子邮件：", "john@example.com", None), ("Plan:", "方案：", "Family (up to 6 people)", "家庭（最多 6 人）"), ("Renews:", "续订日期：", "October 31, 2026", "2026 年 10 月 31 日")]
for i, (label, tr, value, vtr) in enumerate(frows):
    y = 28 + i * 40
    tx.append(T(label, 150, y + 3, 13, color="#1D1D1F", align="right", tr=tr))
    sh.append(R(162, y, 300, 24, fill="#FFFFFF", radius=5, stroke="#C7C7CC"))
    tx.append(T(value, 170, y + 3, 13, color="#1D1D1F", tr=vtr))
sh.append(R(162, 197, 14, 14, fill="#007AFF", radius=3))
tx.append(T("Send me product news and offers", 184, 194, 13, color="#1D1D1F", tr="向我发送产品资讯和优惠"))
for (x, w, label, tr, fill, color) in [(330, 90, "Cancel", "取消", "#FFFFFF", "#1D1D1F"), (430, 90, "Save", "存储", "#007AFF", "#FFFFFF")]:
    s, t = button(x, 246, w, 28, label, tr, fill=fill, color=color, stroke="#C7C7CC" if fill == "#FFFFFF" else None)
    sh.append(s); tx.append(t)
scene("form", "Label : value form with right-aligned labels", 560, 300, "zh-Hans", {"color": "#ECECEC"}, sh, tx)

# 13 low contrast
sh = [R(20, 20, 480, 32, fill="#F2F2F7", radius=8)]
tx = [T("Search messages", 44, 26, 14, color="#C7C7CC", tr="搜索信息"),
      T("No messages yet", 260, 96, 17, "semibold", "#8E8E93", align="center", tr="还没有信息"),
      T("Messages you receive will appear here.", 260, 124, 13, color="#AEAEB2", align="center", tr="你收到的信息将显示在这里。"),
      T("Encrypted end to end", 260, 196, 10, color="#C7C7CC", align="center", tr="端到端加密")]
scene("low-contrast", "Low-contrast gray text (placeholder, empty state, footnote)", 520, 230, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)

# 14 chinese source → en
sh = [R(20, 64, 560, 190, fill="#F5F5F7", radius=10)]
tx = [T("通用", 30, 20, 22, "bold", "#1D1D1F", lang="zh-Hans", tr="General")]
crows = [("关于本机", "About This Mac", None, None), ("软件更新", "Software Update", "有 1 个可用更新", "1 Update Available"), ("储存空间", "Storage", "已使用 186.2 GB", "186.2 GB Used"),
         ("隔空投送与接力", "AirDrop & Handoff", None, None), ("登录项与扩展", "Login Items & Extensions", None, None)]
for i, (a, at, b, bt) in enumerate(crows):
    y = 64 + i * 38
    if i > 0: sh.append(R(36, y, 528, 1, fill="#E4E4E8"))
    tx.append(T(a, 36, y + 10, 13, color="#1D1D1F", lang="zh-Hans", tr=at))
    if b: tx.append(T(b, 564, y + 10, 13, color="#6E6E73", align="right", lang="zh-Hans", tr=bt))
tx.append(T("你可以在这里管理 Mac 的软件更新、储存空间和登录时自动打开的项目。部分设置需要管理员密码。", 30, 272, 12, color="#6E6E73", width=540, lh=18, lang="zh-Hans",
            tr="Manage software updates, storage and the items that open automatically when you log in. Some settings require an administrator password."))
for (x, w, label, tr, fill, color) in [(380, 90, "取消", "Cancel", "#FFFFFF", "#1D1D1F"), (480, 90, "好", "OK", "#007AFF", "#FFFFFF")]:
    s, t = button(x, 330, w, 28, label, tr, fill=fill, color=color, stroke="#C7C7CC" if fill == "#FFFFFF" else None, lang="zh-Hans")
    sh.append(s); tx.append(t)
scene("chinese-source", "Chinese UI translated to English (expansion)", 600, 380, "en", {"color": "#FFFFFF"}, sh, tx)

# 15 japanese source → en
sh, tx = [], [T("ストレージ", 30, 20, 22, "bold", "#1D1D1F", lang="ja", tr="Storage"),
              T("この Mac は 494.4 GB のうち 186.2 GB を使用しています。ストレージを最適化すると、視聴済みのムービーや古いメールの添付ファイルなど、不要になった項目が自動的に削除されます。",
                30, 62, 13, color="#3C3C43", width=540, lh=20, lang="ja",
                tr="This Mac is using 186.2 GB of 494.4 GB. Optimizing storage automatically removes items you no longer need, such as watched movies and old email attachments."),
              T("おすすめ", 30, 140, 15, "semibold", "#1D1D1F", lang="ja", tr="Recommendations")]
for i, (s, t) in enumerate([("iCloud に保存", "Store in iCloud"), ("ゴミ箱を自動的に空にする", "Empty Trash Automatically"), ("ストレージを最適化", "Optimize Storage")]):
    tx.append(T(s, 48, 172 + i * 26, 13, color="#1D1D1F", lang="ja", tr=t, marker="•"))
for (x, w, label, tr, fill, color) in [(360, 100, "キャンセル", "Cancel", "#FFFFFF", "#1D1D1F"), (470, 100, "最適化", "Optimize", "#007AFF", "#FFFFFF")]:
    s, t = button(x, 290, w, 28, label, tr, fill=fill, color=color, stroke="#C7C7CC" if fill == "#FFFFFF" else None, lang="ja")
    sh.append(s); tx.append(t)
scene("japanese-source", "Japanese UI translated to English (kana re-pass)", 600, 340, "en", {"color": "#FFFFFF"}, sh, tx)

# 16 german expansion
sh, tx = [], [T("Storage", 30, 20, 22, "bold", "#1D1D1F", tr="Speicher")]
for i, (s, t) in enumerate([("General", "Allgemein"), ("Notifications", "Mitteilungen"), ("Privacy & Security", "Datenschutz & Sicherheit"), ("Accessibility", "Bedienungshilfen")]):
    sh.append(R(30, 66 + i * 30, 18, 18, fill=["#8E8E93", "#FF3B30", "#007AFF", "#34C759"][i], radius=4))
    tx.append(T(s, 56, 66 + i * 30, 13, color="#1D1D1F", tr=t))
for (x, w, label, tr, fill, color) in [(30, 80, "Cancel", "Abbrechen", "#FFFFFF", "#1D1D1F"), (120, 70, "Save", "Sichern", "#FFFFFF", "#1D1D1F"),
                                         (200, 110, "Review Files", "Dateien überprüfen", "#FFFFFF", "#1D1D1F"), (320, 110, "Empty Trash", "Papierkorb entleeren", "#007AFF", "#FFFFFF")]:
    s, t = button(x, 200, w, 28, label, tr, fill=fill, color=color, stroke="#C7C7CC" if fill == "#FFFFFF" else None)
    sh.append(s); tx.append(t)
tx.append(T("Items in Trash", 30, 252, 13, color="#1D1D1F", tr="Objekte im Papierkorb"))
tx.append(T("1,284", 300, 252, 13, color="#6E6E73", align="right"))
tx.append(T("Optimize storage to free up space automatically.", 30, 290, 13, color="#3C3C43", width=400, lh=18, tr="Optimiere den Speicher, um automatisch Speicherplatz freizugeben."))
scene("german-expansion", "German translation (long expansion: extend → shrink → ellipsis)", 620, 360, "de", {"color": "#FFFFFF"}, sh, tx)

# 17 light 1x
sh = [R(20, 20, 16, 16, fill="#007AFF", radius=4), R(20, 52, 16, 16, fill="#FFFFFF", radius=4, stroke="#AEAEB2"), R(300, 82, 120, 22, fill="#FFFFFF", radius=5, stroke="#C7C7CC")]
tx = [T("Show in menu bar", 44, 19, 13, color="#1D1D1F", tr="在菜单栏中显示"), T("Launch at login", 44, 51, 13, color="#1D1D1F", tr="登录时启动"),
      T("Keep history for", 20, 84, 13, color="#1D1D1F", tr="保留历史记录"), T("30 days", 308, 84, 13, color="#1D1D1F", tr="30 天"),
      T("Changes take effect immediately.", 20, 124, 11, color="#6E6E73", tr="更改会立即生效。")]
s, t = button(20, 160, 90, 26, "Reset…", "重置…", fill="#FFFFFF", color="#1D1D1F", stroke="#C7C7CC")
sh.append(s); tx.append(t)
scene("light-1x", "Light settings at 1x (small pixel sizes)", 460, 210, "zh-Hans", {"color": "#F5F5F7"}, sh, tx, scale=1)


# 18 large 5K selection (tiling): labels on a grid + a paragraph and a long line crossing the vertical tile seam
sh, tx = [], []
words = [("Photos", "照片"), ("Music", "音乐"), ("Mail", "邮件"), ("Notes", "备忘录"), ("Maps", "地图"), ("Calendar", "日历"), ("Reminders", "提醒事项"), ("Weather", "天气")]
for r in range(8):
    for c in range(8):
        w, t = words[(r + c) % 8]
        tx.append(T(w, 80 + c * 300, 90 + r * 150, 17, color="#1D1D1F", tr=t))
tx.append(T("This long headline deliberately crosses the vertical seam between recognition tiles", 700, 1300, 28, "bold", "#1D1D1F",
            tr="这条长标题特意跨过识别分片之间的竖直接缝"))
scene("large-5k", "5K selection (2560×1440 pt @2x) recognized in overlapping tiles", 2560, 1440, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)
# 19 mixed: English pane with one Japanese label (kana re-pass should only look at that label's region)
sh = [R(0, 0, 900, 600, fill="#FFFFFF")]
tx = [T("Storage", 40, 36, 22, "bold", "#1D1D1F", tr="储存空间"),
      T("Your Mac is using 186.2 GB of 494.4 GB. Optimize storage to free up space automatically by removing items you no longer need, such as watched movies, old email attachments and duplicate downloads.",
        40, 80, 13, color="#3C3C43", width=520, lh=19,
        tr="你的 Mac 已使用 494.4 GB 中的 186.2 GB。优化储存空间可自动移除不再需要的项目（例如已看过的影片、旧的邮件附件和重复的下载项），从而释放空间。"),
      T("Recommendations", 40, 170, 15, "semibold", "#1D1D1F", tr="建议"),
      T("Store in iCloud", 40, 200, 13, color="#1D1D1F", tr="储存在 iCloud 中"),
      T("Empty Trash Automatically", 40, 226, 13, color="#1D1D1F", tr="自动清倒废纸篓"),
      T("ストレージを最適化", 680, 540, 13, color="#1D1D1F", lang="ja", tr="优化储存空间")]
scene("mixed-kana", "English pane with one Japanese label (kana re-pass limited to its region)", 900, 600, "zh-Hans", {"color": "#FFFFFF"}, sh, tx)
json.dump({"scenes": scenes}, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(len(scenes), "scenes")
