import CoreGraphics
@testable import CubbyCore

/// 偏向边界的坐标生成：屏幕边缘、两屏交界、负坐标、屏幕间空隙、窗口边缘、选区手柄、标注关键点、小数坐标
enum FuzzPoints {
    // 下面的候选表每次现建：static let 数组会被所有并行分片共享，频繁 retain / release 造成缓存行争用

    /// 贴近边缘的偏移（点）：覆盖手柄容差 8、边带半宽 3、拖拽阈值 4 以及半像素
    private static var edgeOffsets: [CGFloat] {
        [
            -10, -8.25, -8, -6, -4, -3.5, -3, -1, -0.5, -0.25, 0, 0.25, 0.5, 1, 2.999, 3, 4, 6, 7.75, 8, 8.5, 10,
        ]
    }

    /// 小数部分：半像素、四分之一像素与接近整数的值
    private static var fractions: [CGFloat] {
        [0, 0, 0, 0.25, 0.5, 0.75, 0.1, 0.3, 0.999, 0.001]
    }

    private enum Source {
        case selection
        case annotation
        case windowEdge
        case screenEdge
        case junction
        case gap
        case insideScreen
        case anywhere
        case far
    }

    /// 一个「有意思」的点
    static func interesting(
        _ rng: inout FuzzRandom,
        session: ScreenshotSession,
        topology: ScreenTopology
    ) -> CGPoint {
        let hasSelection = session.selection != nil
        let hasAnnotations = !session.document.annotations.isEmpty
        let source: Source = rng.weighted([
            (hasSelection ? 26 : 0, .selection),
            // 有选中标注时更常点它：选中箭头后拖端点这类状态需要连续命中同一标注
            (hasAnnotations ? (session.selectedAnnotation != nil ? 40 : 16) : 0, .annotation),
            (14, .windowEdge),
            (12, .screenEdge),
            (6, .junction),
            (3, .gap),
            (22, .insideScreen),
            (3, .anywhere),
            (1, .far),
        ])
        switch source {
        case .selection: return selectionPoint(&rng, session.selection ?? .zero)
        case .annotation: return annotationPoint(&rng, session: session)
        case .windowEdge: return windowEdgePoint(&rng, topology: topology)
        case .screenEdge: return screenEdgePoint(&rng, topology: topology)
        case .junction: return junctionPoint(&rng, topology: topology)
        case .gap: return gapPoint(&rng, topology: topology)
        case .insideScreen: return insideScreenPoint(&rng, topology: topology)
        case .anywhere: return anywherePoint(&rng, topology: topology)
        case .far: return CGPoint(x: rng.value(in: -6000, 9000), y: rng.value(in: -6000, 6000))
        }
    }

    /// 从 origin 出发的一步拖动：阈值以下的小步、恰好阈值、中等位移或跳到有意思的点
    static func dragStep(
        _ rng: inout FuzzRandom,
        from origin: CGPoint,
        session: ScreenshotSession,
        topology: ScreenTopology
    ) -> CGPoint {
        switch rng.int(below: 20) {
        case 0..<6:
            let angle = rng.value(in: 0, 2 * .pi)
            let length = rng.value(in: 0.05, 3.95)
            return CGPoint(x: origin.x + cos(angle) * length, y: origin.y + sin(angle) * length)
        case 6..<8:
            let vectors: [CGVector] = [
                CGVector(dx: 4, dy: 0), CGVector(dx: 0, dy: -4), CGVector(dx: -3.99, dy: 0),
                CGVector(dx: 2.83, dy: 2.83), CGVector(dx: 0, dy: 4.01), CGVector(dx: -2.5, dy: -3.5),
            ]
            let vector = rng.pick(vectors)
            return CGPoint(x: origin.x + vector.dx, y: origin.y + vector.dy)
        case 8..<15:
            return CGPoint(
                x: origin.x + rng.value(in: -80, 80) + rng.pick(fractions),
                y: origin.y + rng.value(in: -80, 80) + rng.pick(fractions)
            )
        default:
            return interesting(&rng, session: session, topology: topology)
        }
    }

    // MARK: - 各类来源

    private static func offset(_ rng: inout FuzzRandom) -> CGFloat {
        rng.pick(edgeOffsets) + (rng.chance(0.2) ? rng.value(in: -0.5, 0.5) : 0)
    }

    /// 手柄中心附近、边带、选区内部与紧邻外侧
    private static func selectionPoint(_ rng: inout FuzzRandom, _ selection: CGRect) -> CGPoint {
        switch rng.int(below: 4) {
        case 0, 1:
            let center = rng.pick(SelectionHandle.allCases).center(in: selection)
            return CGPoint(x: center.x + offset(&rng), y: center.y + offset(&rng))
        case 2:
            return CGPoint(
                x: selection.minX + selection.width * rng.unit(),
                y: selection.minY + selection.height * rng.unit()
            )
        default:
            let outer = selection.insetBy(dx: -30, dy: -30)
            return CGPoint(x: outer.minX + outer.width * rng.unit(), y: outer.minY + outer.height * rng.unit())
        }
    }

    /// 标注的关键点（端点、角、中心）附近，含命中容差边界
    private static func annotationPoint(_ rng: inout FuzzRandom, session: ScreenshotSession) -> CGPoint {
        // 一半概率落在选中的标注上：走到「选中箭头 → 拖端点」这类需要连续命中同一标注的状态
        let annotation =
            session.selectedAnnotationValue.flatMap { rng.chance(0.5) ? $0 : nil }
            ?? rng.pick(session.document.annotations)
        let anchors = keyPoints(of: annotation.shape)
        let anchor = anchors.isEmpty ? CGPoint(x: session.cursor.x, y: session.cursor.y) : rng.pick(anchors)
        let spread: CGFloat = rng.chance(0.5) ? 0 : 7
        return CGPoint(
            x: anchor.x + rng.value(in: -spread, spread + 0.001),
            y: anchor.y + rng.value(in: -spread, spread + 0.001)
        )
    }

    private static func keyPoints(of shape: AnnotationShape) -> [CGPoint] {
        switch shape {
        case .rectangle(let rect), .ellipse(let rect):
            let box = rect.standardized
            return [
                CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY),
                CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.minX, y: box.midY),
                CGPoint(x: box.midX, y: box.midY),
            ]
        case .arrow(let from, let to):
            return [from, to, CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)]
        case .pen(let points), .highlighter(let points), .mosaic(let points):
            return points
        case .text(_, let origin, _):
            return [origin, CGPoint(x: origin.x + 10, y: origin.y + 8)]
        case .number(let center):
            return [center, CGPoint(x: center.x + 13, y: center.y)]
        }
    }

    /// 任意窗口（包括不合格的窗口）的边缘附近
    private static func windowEdgePoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        guard !topology.windows.isEmpty else { return insideScreenPoint(&rng, topology: topology) }
        let frame = rng.pick(topology.windows).frame.standardized
        return edgePoint(&rng, of: frame)
    }

    private static func screenEdgePoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        guard !topology.screens.isEmpty else { return anywherePoint(&rng, topology: topology) }
        return edgePoint(&rng, of: rng.pick(topology.screens).frame)
    }

    /// 矩形某条边（或某个角）附近的点
    private static func edgePoint(_ rng: inout FuzzRandom, of frame: CGRect) -> CGPoint {
        let alongX = frame.minX + frame.width * rng.unit()
        let alongY = frame.minY + frame.height * rng.unit()
        switch rng.int(below: 5) {
        case 0: return CGPoint(x: frame.minX + offset(&rng), y: alongY)
        case 1: return CGPoint(x: frame.maxX + offset(&rng), y: alongY)
        case 2: return CGPoint(x: alongX, y: frame.minY + offset(&rng))
        case 3: return CGPoint(x: alongX, y: frame.maxY + offset(&rng))
        default:
            let cornerX = rng.chance(0.5) ? frame.minX : frame.maxX
            let corner = CGPoint(x: cornerX, y: rng.chance(0.5) ? frame.minY : frame.maxY)
            return CGPoint(x: corner.x + offset(&rng), y: corner.y + offset(&rng))
        }
    }

    /// 两屏交界：任取两块屏幕，落在一块屏幕的边线上、纵坐标跨越另一块屏幕的范围
    private static func junctionPoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        guard topology.screens.count >= 2 else { return screenEdgePoint(&rng, topology: topology) }
        let first = rng.pick(topology.screens).frame
        let second = rng.pick(topology.screens).frame
        let lineX = rng.pick([first.minX, first.maxX, second.minX, second.maxX])
        let lineY = rng.pick([first.minY, first.maxY, second.minY, second.maxY])
        let span = first.union(second)
        let tiny = rng.pick([-0.5, -0.25, -0.001, 0, 0, 0.001, 0.25, 0.5] as [CGFloat])
        if rng.chance(0.5) {
            return CGPoint(x: lineX + tiny, y: span.minY + span.height * rng.unit())
        }
        if rng.chance(0.5) {
            return CGPoint(x: span.minX + span.width * rng.unit(), y: lineY + tiny)
        }
        return CGPoint(x: lineX + tiny, y: lineY + tiny)
    }

    /// 屏幕间的空隙（拒绝采样；找不到时退回任意点）
    private static func gapPoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        let bounds = unionBounds(topology)
        for _ in 0..<12 {
            let point = CGPoint(x: bounds.minX + bounds.width * rng.unit(), y: bounds.minY + bounds.height * rng.unit())
            if topology.screen(containing: point) == nil {
                return point
            }
        }
        return anywherePoint(&rng, topology: topology)
    }

    /// 某块屏幕内的点，带小数部分
    private static func insideScreenPoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        guard !topology.screens.isEmpty else { return anywherePoint(&rng, topology: topology) }
        let frame = rng.pick(topology.screens).frame
        return CGPoint(
            x: (frame.minX + (frame.width - 1) * rng.unit()).rounded(.down) + rng.pick(fractions),
            y: (frame.minY + (frame.height - 1) * rng.unit()).rounded(.down) + rng.pick(fractions)
        )
    }

    private static func anywherePoint(_ rng: inout FuzzRandom, topology: ScreenTopology) -> CGPoint {
        let bounds = unionBounds(topology).insetBy(dx: -120, dy: -120)
        return CGPoint(x: bounds.minX + bounds.width * rng.unit(), y: bounds.minY + bounds.height * rng.unit())
    }

    private static func unionBounds(_ topology: ScreenTopology) -> CGRect {
        topology.screens.map(\.frame).reduce(CGRect?.none) { $0?.union($1) ?? $1 }
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
