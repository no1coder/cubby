import CoreGraphics

/// 冻结帧：触发瞬间某块屏幕的原生像素位图（sRGB），只存在于内存
///
/// `@unchecked Sendable` 的理由：CGImage 不可变，创建后可以安全地跨线程读取；
/// `CaptureScreen` 本身是 Sendable 值类型。
public struct FrozenFrame: @unchecked Sendable {
    /// 位图所属的屏幕
    public let screen: CaptureScreen
    /// 屏幕局部像素位图，左上角 = `screen.frame.origin`
    public let image: CGImage

    public init(screen: CaptureScreen, image: CGImage) {
        self.screen = screen
        self.image = image
    }
}
