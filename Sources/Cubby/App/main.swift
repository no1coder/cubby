import AppKit

// 菜单栏常驻应用：不显示 Dock 图标
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
