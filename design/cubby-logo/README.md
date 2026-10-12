# Cubby 新 Logo（方案 C）

## 文件
- `AppIcon.appiconset/` — Xcode 资源目录用的完整应用图标（16–1024，含 @2x，Contents.json 已写好）。16/32 px 用的是简化版（无光影、单卡片）。
- `MenuBarIcon.imageset/` — 菜单栏模板图标（矢量 SVG，已设为 Template 渲染，系统会自动适配深/浅色菜单栏）。
- `svg/AppIcon.svg` — 1024 母版，按 macOS 图标网格留了 100px 边距和投影。
- `svg/AppIcon-flat.svg` — 无边距的满版图标（网页、README、About 窗口用）。
- `svg/AppIcon-mono.svg`、`svg/Glyph-white.svg` — 单色版 / 透明底白色图形。
- `svg/MenuBarIconTemplate.png` / `@2x.png` — 不用资源目录时的位图模板图标。
- `AppIcon-1024.png` — 预览 / 发布用大图。

## 规格
- 主色渐变：#4E90FF → #2358F2 → #1431B0（从上到下）
- 图形：白色到 #DCE6FF 的竖向渐变
- 格子：外圆角 R15 · 内圆角 R6 · 壁厚 9（100 单位网格）
- 卡片：圆角 R4，前卡 -5°，后卡 +11°、30% 白

## 在项目中的用法
- 应用图标：`./scripts/make-icon.sh` 由 `AppIcon.appiconset` 生成 `Resources/AppIcon.icns`，并由 `AppIcon-1024.png` 生成 README 用的 `docs/assets/icon.png`。
- 菜单栏图标：`Sources/Cubby/App/StatusBarIcon.swift` 按 `svg/MenuBarIconTemplate.svg` 用代码绘制（要画暂停状态与新版本蓝点的缺口）。
