import CoreGraphics
import CubbyCore
import Foundation

/// 晾衣绳窗口里的排布（窗口坐标，原点在左上角）：绳子两端固定、中间下垂，照片按宽度均匀挂在绳上，
/// 夹子夹在照片顶边与绳子相交处。绘制与指针命中（窗口不是 key，悬停由控制器轮询计算）共用这一份结果
struct ClotheslineLayout: Equatable {
    struct Photo: Equatable, Identifiable {
        let id: UUID
        let index: Int
        /// 相纸（含白边）未旋转时的位置
        let frame: CGRect
        /// 图片在相纸里的位置（相对相纸左上角）
        let imageFrame: CGRect
        /// 静止倾角（度）
        let tilt: Double
    }

    /// 窗口高度：绳子 + 最高的照片 + 悬停提示
    static let windowHeight: CGFloat = 270
    /// 两端固定点离窗口顶边的距离
    static let anchorY: CGFloat = 40
    /// 绳子正中下垂多少
    static let sag: CGFloat = 26
    /// 图片的最大宽高（不含白边）
    static let maxImageWidth: CGFloat = 168
    static let maxImageHeight: CGFloat = 132
    /// 相纸白边：上、左、右 6，底边留白更宽
    static let border: CGFloat = 6
    static let bottomBorder: CGFloat = 22
    /// 照片顶边比绳子高一点，夹子盖住相交处
    static let pinOverlap: CGFloat = 6

    let width: CGFloat
    let photos: [Photo]

    /// - Parameter items: 绳上的条目（从左到右）与图片的像素尺寸
    init(items: [(id: UUID, pixelSize: CGSize)], width: CGFloat) {
        self.width = width
        let centers = ClotheslineGeometry.centers(count: items.count, width: width)
        let maxWidth = ClotheslineGeometry.photoWidth(
            count: items.count, width: width, maxWidth: Self.maxImageWidth + Self.border * 2)
        photos = zip(items, centers).enumerated().map { index, pair in
            Self.photo(
                id: pair.0.id, pixelSize: pair.0.pixelSize, index: index, centerX: pair.1, maxWidth: maxWidth,
                width: width)
        }
    }

    /// 绳子上 x 处的高度（窗口坐标）
    func ropeY(at x: CGFloat) -> CGFloat {
        Self.anchorY + ClotheslineGeometry.ropeDrop(at: x, width: width, sag: Self.sag)
    }

    /// 指针下的照片：放宽到盖住悬停放大 1.04 与左上角伸出的 ×（22pt，偏移 −9）
    func photo(at point: CGPoint) -> Photo? {
        photos.last { $0.frame.insetBy(dx: -Self.hitSlop, dy: -Self.hitSlop).contains(point) }
    }

    private static let hitSlop: CGFloat = 13

    /// 照片与悬停提示占据的区域（指针离开它 0.6 秒后收起）
    var occupiedHeight: CGFloat {
        (photos.map(\.frame.maxY).max() ?? Self.anchorY) + 44
    }

    private static func photo(
        id: UUID, pixelSize: CGSize, index: Int, centerX: CGFloat, maxWidth: CGFloat, width: CGFloat
    ) -> Photo {
        let imageSize = ClotheslineGeometry.photoSize(
            pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height),
            maxWidth: max(maxWidth - border * 2, 1), maxHeight: maxImageHeight)
        let size = CGSize(width: imageSize.width + border * 2, height: imageSize.height + border + bottomBorder)
        let top = anchorY + ClotheslineGeometry.ropeDrop(at: centerX, width: width, sag: sag) - pinOverlap
        return Photo(
            id: id, index: index,
            frame: CGRect(x: centerX - size.width / 2, y: top, width: size.width, height: size.height),
            imageFrame: CGRect(origin: CGPoint(x: border, y: border), size: imageSize),
            tilt: ClotheslineGeometry.restingTilt(index: index))
    }
}
