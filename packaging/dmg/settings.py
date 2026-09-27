# dmgbuild 配置：DMG 安装窗口的外观（由 scripts/make-dmg.sh 调用，不单独使用）
#
# dmgbuild 以 exec 方式执行本文件，模块级变量即配置项；路径由 make-dmg.sh 通过 -D 传入：
#   app          待打包的 .app
#   app_name     .app 在 DMG 中的文件名（如 Cubby.app）
#   background   1x 背景图（同目录下的 @2x 版本会被自动合并为多分辨率 TIFF）
#   volume_icon  卷图标（.icns，写入 .VolumeIcon.icns）
#   layout       packaging/dmg/layout.json（窗口尺寸、图标位置，与背景生成脚本共用）
# 配置项说明：https://dmgbuild.readthedocs.io/en/latest/settings.html
import json
import os.path

app = defines["app"]  # noqa: F821 （dmgbuild 注入）
app_name = defines.get("app_name") or os.path.basename(app.rstrip("/"))  # noqa: F821
with open(defines["layout"], encoding="utf-8") as fp:  # noqa: F821
    layout = json.load(fp)

# 与原 hdiutil 流程一致：HFS+ 文件系统、LZFSE 压缩（macOS 10.11+ 可挂载）
format = "ULFO"
filesystem = "HFS+"

files = [(app, app_name)]
symlinks = {"Applications": "/Applications"}
# 不设置 hide_extensions：它会给 .app 根目录写 FinderInfo 扩展属性，
# 使 codesign --verify --strict 报 "Finder information ... not allowed"；Finder 默认本就隐藏 .app 后缀
hide_extensions = []

icon = defines["volume_icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

# 窗口：只保留图标视图，隐藏工具栏、侧边栏、路径栏、状态栏与标签页栏
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
include_list_view_settings = False

window = layout["window"]
# ((x, y), (宽, 高))：位置以屏幕左下角为原点，大致落在常见笔记本屏幕的中央；
# Finder 把尺寸当作整个窗口（含标题栏），内容区 = 背景 1x 尺寸（不含出血）。
# macOS 26 无工具栏窗口的标题栏为 32pt，旧版本 28pt 时多出的几 pt 由背景底部出血填满
window_rect = (
    (400, 260),
    (window["width"], window["height"] + window["titleBarHeight"]),
)

arrange_by = None
show_icon_preview = False
show_item_info = False
label_pos = "bottom"
icon_size = float(layout["iconSize"])
text_size = float(layout["textSize"])
# 图标中心点坐标（以窗口内容区左上角为原点，单位 pt）
icon_locations = {
    app_name: (layout["app"]["x"], layout["app"]["y"]),
    "Applications": (layout["applications"]["x"], layout["applications"]["y"]),
}
