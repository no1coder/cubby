import CoreGraphics

/// 放大镜摆放（§2.4）：默认光标右下，右 / 下放不下时分别翻到左 / 上，结果完整在屏幕内
public enum MagnifierPlacement {
    /// 光标右下偏移 offset；溢出则分别翻转 x / y；结果完整在 screen 内
    public static func frame(size: CGSize, cursor: CGPoint, screen: CGRect, offset: CGFloat = 20) -> CGRect {
        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)

        let preferredX = cursor.x + offset
        let x = preferredX + width > screen.maxX ? cursor.x - offset - width : preferredX
        let preferredY = cursor.y + offset
        let y = preferredY + height > screen.maxY ? cursor.y - offset - height : preferredY

        return SelectionGeometry.clamped(CGRect(x: x, y: y, width: width, height: height), to: screen)
    }
}
