import AppKit

/// 菜单栏的红色「地址被替换」胶囊（TamperAlert 设计稿右上）：红底、白色盾牌与文字，不是模板图（不随菜单栏反色）
@MainActor
enum StatusItemTamperPill {
    private static let red = NSColor(red: 1, green: 0.271, blue: 0.227, alpha: 1)
    private static let height: CGFloat = 18
    private static let horizontalPadding: CGFloat = 7
    private static let iconSpacing: CGFloat = 4

    static func image() -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let text = NSAttributedString(
            string: SecurityCopy.statusPill, attributes: [.font: font, .foregroundColor: NSColor.white])
        let symbol = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: nil)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
        let iconSize = symbol?.size ?? .zero
        let textSize = text.size()
        let width = ceil(horizontalPadding * 2 + iconSize.width + iconSpacing + textSize.width)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            red.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            symbol?.draw(
                in: NSRect(
                    x: horizontalPadding, y: (rect.height - iconSize.height) / 2, width: iconSize.width,
                    height: iconSize.height))
            text.draw(
                at: NSPoint(
                    x: horizontalPadding + iconSize.width + iconSpacing, y: (rect.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = SecurityCopy.statusPill
        return image
    }
}
