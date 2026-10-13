import AppKit
import CubbyCore
import Observation

/// 晾衣绳窗口的状态：绳上的照片、悬停（窗口不是 key，由控制器轮询指针得出）、正在放大编辑的照片与新挂上的时刻
@MainActor
@Observable
final class ClotheslineModel {
    struct Entry: Identifiable, Equatable {
        let item: ClipItem
        let imageSource: ClipImageSource?

        var id: UUID {
            item.id
        }

        /// 图片的像素尺寸（排布按宽高比计算）
        var pixelSize: CGSize {
            guard case .image(let ref) = item.payload else { return .zero }
            return CGSize(width: ref.width, height: ref.height)
        }
    }

    private(set) var entries: [Entry] = []
    private(set) var layout = ClotheslineLayout(items: [], width: 0)
    var hoveredID: UUID?
    /// 正在放大编辑的照片：绳上原位置显示虚线空位
    var editingID: UUID?
    /// 是否显示中（隐藏时暂停摆动的逐帧刷新）
    var isShown = false
    /// 新挂上的照片与挂上的时刻（单调时钟秒）：带一次衰减摆动
    private(set) var hungAt: [UUID: TimeInterval] = [:]

    @ObservationIgnored var onCopy: (ClipItem) -> Void = { _ in }
    @ObservationIgnored var onEdit: (ClipItem) -> Void = { _ in }
    @ObservationIgnored var onRemove: (ClipItem) -> Void = { _ in }

    func update(entries newEntries: [Entry], width: CGFloat) {
        let newLayout = ClotheslineLayout(items: newEntries.map { ($0.id, $0.pixelSize) }, width: width)
        if newEntries != entries { entries = newEntries }
        if newLayout != layout { layout = newLayout }
        if let hoveredID, !newEntries.contains(where: { $0.id == hoveredID }) { self.hoveredID = nil }
        hungAt = hungAt.filter { id, _ in newEntries.contains { $0.id == id } }
    }

    func markHung(_ id: UUID, at time: TimeInterval) {
        hungAt[id] = time
    }

    func entry(for id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }
}
