import CoreGraphics

/// 选区的 8 个手柄：4 角 + 4 边中点（全局点坐标，y 向下，top = minY）
public enum SelectionHandle: CaseIterable, Sendable, Hashable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    /// 拖动时是否移动左边（minX）
    public var movesLeftEdge: Bool {
        switch self {
        case .topLeft, .bottomLeft, .left: true
        default: false
        }
    }

    /// 拖动时是否移动右边（maxX）
    public var movesRightEdge: Bool {
        switch self {
        case .topRight, .bottomRight, .right: true
        default: false
        }
    }

    /// 拖动时是否移动上边（minY）
    public var movesTopEdge: Bool {
        switch self {
        case .topLeft, .top, .topRight: true
        default: false
        }
    }

    /// 拖动时是否移动下边（maxY）
    public var movesBottomEdge: Bool {
        switch self {
        case .bottomLeft, .bottom, .bottomRight: true
        default: false
        }
    }

    /// 是否为角手柄（同时移动一条竖边和一条横边）
    public var isCorner: Bool {
        (movesLeftEdge || movesRightEdge) && (movesTopEdge || movesBottomEdge)
    }

    /// 手柄在矩形上的中心点
    public func center(in rect: CGRect) -> CGPoint {
        let box = rect.standardized
        let x = movesLeftEdge ? box.minX : (movesRightEdge ? box.maxX : box.midX)
        let y = movesTopEdge ? box.minY : (movesBottomEdge ? box.maxY : box.midY)
        return CGPoint(x: x, y: y)
    }

    /// 由横向（左 / 右）与纵向（上 / 下）命中的边组合出手柄；两者都为 nil 时返回 nil
    static func from(x xSide: EdgeSide?, y ySide: EdgeSide?) -> SelectionHandle? {
        switch (xSide, ySide) {
        case (.low, .low): .topLeft
        case (.low, .high): .bottomLeft
        case (.low, nil): .left
        case (.high, .low): .topRight
        case (.high, .high): .bottomRight
        case (.high, nil): .right
        case (nil, .low): .top
        case (nil, .high): .bottom
        case (nil, nil): nil
        }
    }
}

/// 某一轴上的边：low = 左 / 上（较小坐标），high = 右 / 下（较大坐标）
enum EdgeSide: Sendable {
    case low
    case high
}

/// 某一点相对选区的命中结果
public enum SelectionHitRegion: Equatable, Sendable {
    /// 手柄或边带（边带映射为同侧的边手柄，角落映射为角手柄）
    case handle(SelectionHandle)
    case inside
    case outside
}

/// 方向键微调方向（全局点坐标，y 向下）
public enum NudgeDirection: Sendable {
    case up
    case down
    case left
    case right

    /// 单位位移向量
    public var vector: CGVector {
        switch self {
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }
}
