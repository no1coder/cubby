import CoreGraphics
import Foundation
import ImageIO
@testable import CubbyCore

/// 导出测试用的小屏幕与帧（坐标图：R = 像素 x，G = 像素 y）
enum ExportFixtures {
    /// 100×80 pt @2x 于 (0, 0) → 帧 200×160 像素
    static let retina = CaptureScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
    /// 120×90 pt @1x 于 (1440, −180)
    static let external = CaptureScreen(id: 2, frame: CGRect(x: 1440, y: -180, width: 120, height: 90), scale: 1)

    static func frame(_ screen: CaptureScreen) -> FrozenFrame {
        FrozenFrame(
            screen: screen,
            image: TestImage.coordinates(width: Int(screen.pixelSize.width), height: Int(screen.pixelSize.height))
        )
    }

    /// PNG 元数据中的 DPI
    static func dpi(of png: Data) -> (width: Double, height: Double)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyDPIWidth] as? Double,
            let height = properties[kCGImagePropertyDPIHeight] as? Double
        else { return nil }
        return (width, height)
    }
}
