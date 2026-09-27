// 调试场景只在 Debug 构建中编译（Release 不含预置会话与假窗口布局）
#if DEBUG
import CoreGraphics

/// 调试场景里的光标落点：在拓扑中找「假窗口」与重叠窗口
enum ScenarioWindows {
    /// 取样网格：窗口可见区域内的 3 × 3 个点（按比例）
    private static let samples: [CGFloat] = [0.5, 0.25, 0.75]
    private static let minimumSide: CGFloat = 2

    /// 光标落在第二个普通窗口（没有则第一个）可命中的位置；没有窗口时为屏幕中心
    static func hoverPoint(on screen: CaptureScreen, topology: ScreenTopology) -> CGPoint {
        let windows = eligibleWindows(on: screen, topology: topology)
        let preferred = windows.count > 1 ? Array(windows[1...]) + [windows[0]] : windows
        for window in preferred {
            let visible = window.frame.intersection(screen.frame)
            let hit = samplePoints(in: visible).first {
                WindowHitTester.hoverTarget(at: $0, topology: topology)?.windowID == window.id
            }
            if let hit {
                return hit
            }
        }
        return CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    }

    /// 至少两个窗口重叠处的点（候选栈 ≥ 3 层）；没有重叠时为 nil
    static func overlapPoint(on screen: CaptureScreen, topology: ScreenTopology) -> CGPoint? {
        let windows = eligibleWindows(on: screen, topology: topology)
        for (index, front) in windows.enumerated() {
            for back in windows.dropFirst(index + 1) {
                let overlap = front.frame.intersection(back.frame).intersection(screen.frame)
                let hit = samplePoints(in: overlap).first {
                    WindowHitTester.candidates(at: $0, in: topology).count > 2
                }
                if let hit {
                    return hit
                }
            }
        }
        return nil
    }

    /// 与 WindowHitTester 相同的过滤规则，且在该屏幕上可见
    private static func eligibleWindows(on screen: CaptureScreen, topology: ScreenTopology) -> [WindowCandidate] {
        topology.windows.filter { window in
            let visible = window.frame.standardized.intersection(screen.frame)
            return window.layer == 0 && window.alpha > 0 && window.ownerPID != topology.ownPID
                && !visible.isNull && visible.width >= minimumSide && visible.height >= minimumSide
        }
    }

    private static func samplePoints(in rect: CGRect) -> [CGPoint] {
        guard !rect.isNull, !rect.isEmpty else { return [] }
        return samples.flatMap { fy in
            samples.map { fx in CGPoint(x: rect.minX + rect.width * fx, y: rect.minY + rect.height * fy) }
        }
    }
}

/// annotating 场景的标注：每种工具一个，外加 3 个序号；位置相对选区左上角（仅供截图走查的布局数据）
enum ScenarioAnnotations {
    private static let text = "Cubby"
    private static let textOffset = CGPoint(x: 40, y: 250)

    /// 形状均相对选区左上角 (0, 0)
    private static let shapes: [AnnotationShape] = [
        .rectangle(CGRect(x: 30, y: 30, width: 120, height: 80)),
        .ellipse(CGRect(x: 180, y: 30, width: 120, height: 80)),
        .arrow(from: CGPoint(x: 340, y: 110), to: CGPoint(x: 440, y: 40)),
        .pen([
            CGPoint(x: 40, y: 170), CGPoint(x: 70, y: 150), CGPoint(x: 100, y: 180),
            CGPoint(x: 130, y: 155), CGPoint(x: 160, y: 185),
        ]),
        .highlighter([CGPoint(x: 200, y: 170), CGPoint(x: 320, y: 170)]),
        // 盖住 Editor 窗口正文 "The quick brown fox" 这几个词（fixture 中正文行在全局 y ≈ 277，x 从 492 开始），
        // 走查时看得到像素化效果（评审 P2-11）
        .mosaic([CGPoint(x: 292, y: 128), CGPoint(x: 352, y: 128), CGPoint(x: 412, y: 128)]),
        .text(text, origin: textOffset, maxWidth: 0),
        .number(center: CGPoint(x: 400, y: 270)),
        .number(center: CGPoint(x: 450, y: 270)),
        .number(center: CGPoint(x: 500, y: 270)),
    ]

    static func make(styles: ToolStyles, selection: CGRect) -> [Annotation] {
        let offset = CGVector(dx: selection.minX, dy: selection.minY)
        let textWidth = selection.width - textOffset.x
        return shapes.enumerated().map { index, local in
            let placed = local.translated(by: offset)
            let shape: AnnotationShape
            if case .text(let content, let origin, _) = placed {
                shape = .text(content, origin: origin, maxWidth: textWidth)
            } else {
                shape = placed
            }
            return Annotation(
                id: AnnotationDrafting.annotationID(serial: index + 1),
                shape: shape,
                style: styles.style(for: shape.tool)
            )
        }
    }
}
#endif
