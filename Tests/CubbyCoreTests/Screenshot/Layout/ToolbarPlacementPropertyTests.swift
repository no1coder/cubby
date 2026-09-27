import CoreGraphics
import Testing
@testable import CubbyCore

/// ToolbarPlacement 对任意输入成立的性质（§2.6：右对齐选区，下 → 上 → 内三档兜底，始终夹紧在屏幕内）
@Suite("ToolbarPlacement · 性质测试（任意输入）")
struct ToolbarPlacementPropertyTests {
    private static let iterations = FuzzBudget.scaled(4000)
    private typealias Gen = FuzzGeometry

    /// 常见工具栏 / 样式条尺寸，外加零尺寸与比屏幕还大的尺寸
    private func barSize(_ rng: inout FuzzRandom, screen: CGRect) -> CGSize {
        switch rng.int(below: 5) {
        case 0: return CGSize(width: 520, height: 36)
        case 1: return CGSize(width: rng.value(in: 0, 800), height: rng.value(in: 0, 60))
        case 2: return .zero
        case 3:
            return CGSize(
                width: screen.width * rng.value(in: 0.5, 2), height: screen.height * rng.value(in: 0.01, 1.5))
        default: return CGSize(width: rng.value(in: 100, 700), height: 28)
        }
    }

    @Test("工具栏与样式条永远完整位于屏幕内（选区可在屏幕内、贴边、跨边或为整屏）")
    func alwaysInsideScreen() {
        var rng = FuzzRandom(seed: 0x7001_0001)
        var failures = PropertyFailures()
        for _ in 0..<Self.iterations {
            let screen = Gen.bounds(&rng)
            let selection: CGRect
            switch rng.int(below: 4) {
            case 0: selection = screen
            case 1: selection = Gen.rect(&rng, around: screen)
            default: selection = Gen.insideRect(&rng, in: screen)
            }
            let toolbarSize = barSize(&rng, screen: screen)
            let styleSize = rng.chance(0.5) ? barSize(&rng, screen: screen) : nil
            let gap: CGFloat = rng.pick([8, 0, 20])
            let layout = ToolbarPlacement.layout(
                toolbarSize: toolbarSize, styleBarSize: styleSize, selection: selection, screen: screen, gap: gap)
            let context = "toolbar \(toolbarSize) style \(String(describing: styleSize)) sel \(selection) in \(screen)"
            failures.check(Gen.contains(screen, layout.toolbar), "toolbar \(layout.toolbar) outside: \(context)")
            if let styleBar = layout.styleBar {
                failures.check(Gen.contains(screen, styleBar), "style bar \(styleBar) outside: \(context)")
            }
            failures.check((layout.styleBar == nil) == (styleSize == nil), "style bar presence: \(context)")
            failures.check(
                Gen.close(layout.toolbar.width, min(toolbarSize.width, screen.width))
                    && Gen.close(layout.toolbar.height, min(toolbarSize.height, screen.height)),
                "toolbar size changed: \(context) → \(layout.toolbar)")
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }

    @Test("档位语义：below 在选区下方 gap 处、above 在上方 gap 处；放得下时右对齐选区；样式条在远离选区一侧")
    func sideSemantics() {
        var rng = FuzzRandom(seed: 0x7001_0002)
        var failures = PropertyFailures()
        let toolbar = CGSize(width: 520, height: 36)
        let style = CGSize(width: 300, height: 30)
        for _ in 0..<Self.iterations {
            let screen = CGRect(
                x: CGFloat(rng.int(below: 4001) - 2000), y: CGFloat(rng.int(below: 2001) - 1000),
                width: CGFloat(rng.int(below: 2000) + 800), height: CGFloat(rng.int(below: 1200) + 300))
            let selection = Gen.insideRect(&rng, in: screen)
            let withStyle = rng.chance(0.5)
            let layout = ToolbarPlacement.layout(
                toolbarSize: toolbar, styleBarSize: withStyle ? style : nil, selection: selection, screen: screen)
            let context = "sel \(selection) in \(screen) style \(withStyle) → \(layout)"
            switch layout.side {
            case .below:
                failures.check(Gen.close(layout.toolbar.minY, selection.maxY + 8), "below gap: \(context)")
            case .above:
                failures.check(Gen.close(layout.toolbar.maxY, selection.minY - 8), "above gap: \(context)")
            case .inside:
                failures.check(
                    Gen.close(layout.toolbar.maxY, selection.maxY - 8) || layout.toolbar.minY == screen.minY
                        || Gen.close(layout.toolbar.maxY, screen.maxY),
                    "inside inset: \(context)")
            }
            if selection.width < toolbar.width {
                // 选区比工具栏窄：以选区中心对齐（放得下时）
                let minX = selection.midX - toolbar.width / 2
                if minX >= screen.minX && minX + toolbar.width <= screen.maxX {
                    failures.check(Gen.close(layout.toolbar.midX, selection.midX), "not centered: \(context)")
                }
            } else {
                let rightEdge = layout.side == .inside ? selection.maxX - 8 : selection.maxX
                if rightEdge - toolbar.width >= screen.minX && rightEdge <= screen.maxX {
                    failures.check(Gen.close(layout.toolbar.maxX, rightEdge), "not right-aligned: \(context)")
                }
            }
            if let styleBar = layout.styleBar, layout.side == .below {
                failures.check(styleBar.minY >= layout.toolbar.maxY - Gen.tolerance, "style bar not below: \(context)")
            }
            if let styleBar = layout.styleBar, layout.side == .above {
                failures.check(styleBar.maxY <= layout.toolbar.minY + Gen.tolerance, "style bar not above: \(context)")
            }
        }
        #expect(failures.count == 0, "\(failures.summary)")
    }
}
