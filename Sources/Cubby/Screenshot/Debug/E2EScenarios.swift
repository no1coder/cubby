#if DEBUG
import AppKit
import CubbyCore

/// 全部端到端脚本（按运行顺序）。坐标为主屏局部点；fixture 的假窗口（前 → 后）：
/// 9001 Editor (340, 200, 460 × 300)、9002 Preview (560, 140, 420 × 320)、9003 Terminal (200, 110, 520 × 260)，
/// 三者在 (600, 300) 附近共同重叠；x 在 1000...1950、y 在 100...700 的区域是空桌面
@MainActor
enum E2EScenarios {
    static var all: [E2EScenario] {
        [
            windowClick, dragSelect, selectionGestures, toolbar, annotate, annotationDetails, text, escapeConfirm,
            hoverCycle, windowCapture, windowCaptureFailure, save, pin, extractText, colorPick, hotKeyAgain, paused,
            edgeCases, extractNoText, miscellaneous, annotationExport, finishingHotKey, keyboardState, textCursor,
            arrowMagnet, selectionMagnet, arrowEndpoints, shiftLine, styleKeys, saveCancel, saveDirect, pinSave,
            saveOverlayCancelled,
        ] + translationScenarios
    }

    /// 截图翻译（macOS 26+ 才有翻译）
    static var translationScenarios: [E2EScenario] {
        guard #available(macOS 26, *) else { return [] }
        return [
            translate, translatePeek, translateWipe, translateExport, translateUndo, translateEscape, translateLanguage,
            translateResolve, translateSaveCancel, translatePartial, translateCopy, translateExtract,
            translateSelection,
            translateFailures, translateVision,
        ]
    }

    /// 空桌面上的一点（不在任何假窗口内）
    static let desktop = E2EPoint.at(1500, 700)
    static let editorOnly = E2EPoint.at(400, 450)
    static let editorFrame = CGRect(x: 340, y: 200, width: 460, height: 300)
    /// 标注类脚本共用的选区（空桌面）
    static let canvasStart = E2EPoint.at(1050, 150)
    static let canvasEnd = E2EPoint.at(1950, 650)

    /// 在空桌面上拖出标准选区，进入 adjusting
    static var selectCanvas: [E2EStep] {
        [.start(at: desktop), .drag([canvasStart, canvasEnd]), .expectPhase(.adjusting)]
    }

    static var windowClick: E2EScenario {
        E2EScenario(
            name: "window-click",
            summary: "hover window 9001, click to select it, Return copies it",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .move(editorOnly),
                .expectEqual("hover target is window 9001", 9001) { try $0.requireSession().hover?.windowID },
                .expectEqual("hover depth is 0", 0) { try $0.requireSession().hoverDepth },
                .click(editorOnly),
                .expectPhase(.adjusting),
                .expectEqual("selection equals the window frame", { $0.globalRect(editorFrame) }) {
                    try $0.requireSession().selection
                },
                .key(.returnKey),
                .expectIdle,
                .expectPNG("pasteboard PNG has the window's pixel size") {
                    $0.pixelSize(of: $0.globalRect(editorFrame))
                },
                .expectHistoryDelta(1),
                .expectScreenshotHistoryItem,
                .expectHUD(containing: E2EText.copied),
            ]
        )
    }

    static var dragSelect: E2EScenario {
        let start = CGPoint(x: 1100.25, y: 300.75)
        let end = CGPoint(x: 1500.6, y: 620.4)
        return E2EScenario(
            name: "drag-select",
            summary: "drag with fractional points, shift square, size label, nudges, all 8 handles",
            steps: [
                .markOutputs,
                .start(at: desktop),
                .drag([.at(start.x, start.y), .at(end.x, end.y)]),
                .expectPhase(.adjusting),
                .expect("selection follows the fractional drag within one pixel") { context in
                    let selection = try context.requireSelection()
                    let wanted = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
                    let tolerance = 1 / context.scale
                    return abs(selection.minX - wanted.minX) <= tolerance
                        && abs(selection.minY - wanted.minY) <= tolerance
                        && abs(selection.maxX - wanted.maxX) <= tolerance * 2
                        && abs(selection.maxY - wanted.maxY) <= tolerance * 2
                },
                .expectPixelAligned,
                .expectSizeLabelMatchesSelection,
                // 选区外按住 ⇧ 拖：新选区为正方形（边长取较短的一边）
                .hold(.shift),
                .drag([.at(1700, 200), .at(1900, 300)]),
                .releaseModifiers,
                .expectSelection("shift-drag makes a 100 x 100 square") {
                    $0.globalRect(CGRect(x: 1700, y: 200, width: 100, height: 100))
                },
                .expectSizeLabelMatchesSelection,
            ] + nudgeSteps + handleSteps + [
                .remember("size label") { context in
                    context.strings["label"] =
                        context.world.overlay?.debugScreenViews
                        .compactMap(\.debugSizeLabelText).first
                },
                .key(.returnKey),
                .expectIdle,
                .expectEqual("exported PNG size equals the size label", { $0.strings["label"] }) { context in
                    context.pasteboardImage.map { "\($0.width) \u{00D7} \($0.height)" }
                },
                .expectHistoryDelta(1),
            ]
        )
    }

    /// 方向键 1 pt、⇧+方向键 10 pt
    private static var nudgeSteps: [E2EStep] {
        let moves: [(E2EKey, NSEvent.ModifierFlags, CGVector)] = [
            (.rightArrow, [], CGVector(dx: 1, dy: 0)),
            (.downArrow, .shift, CGVector(dx: 0, dy: 10)),
            (.leftArrow, .shift, CGVector(dx: -10, dy: 0)),
            (.upArrow, [], CGVector(dx: 0, dy: -1)),
        ]
        return moves.flatMap { key, flags, delta -> [E2EStep] in
            let title = "nudge \(key)\(flags.isEmpty ? "" : " with shift") moves by (\(delta.dx), \(delta.dy))"
            return [
                .rememberSelection,
                .key(key, flags),
                .expectSelection(title) { try $0.rememberedSelection().offsetBy(dx: delta.dx, dy: delta.dy) },
            ]
        }
    }

    /// 依次拖动 8 个手柄，只有对应的边移动
    private static var handleSteps: [E2EStep] {
        let offset: CGFloat = 12
        return SelectionHandle.allCases.flatMap { handle -> [E2EStep] in
            let dx = handle.movesLeftEdge ? -offset : (handle.movesRightEdge ? offset : 0)
            let dy = handle.movesTopEdge ? -offset : (handle.movesBottomEdge ? offset : 0)
            return [
                .rememberSelection,
                .drag([.handle(handle), .handle(handle, dx: dx, dy: dy)]),
                .expectSelection("drag handle \(handle) by (\(dx), \(dy))") { context in
                    let before = try context.rememberedSelection()
                    let minX = before.minX + (handle.movesLeftEdge ? dx : 0)
                    let minY = before.minY + (handle.movesTopEdge ? dy : 0)
                    let maxX = before.maxX + (handle.movesRightEdge ? dx : 0)
                    let maxY = before.maxY + (handle.movesBottomEdge ? dy : 0)
                    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                },
            ]
        }
    }
}

/// 界面文案（与被测代码相同的英文键，按当前本地化取值）
enum E2EText {
    static var copied: String { localized("Copied to clipboard") }

    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

extension E2EContext {
    func globalRect(_ local: CGRect) -> CGRect {
        local.offsetBy(dx: world.screen.frame.minX, dy: world.screen.frame.minY)
    }

    /// 导出后的像素尺寸（与 ScreenshotExporter 相同的 integral 规则）
    func pixelSize(of rect: CGRect) -> CGSize {
        world.screen.pixelRect(rect).size
    }

    var pasteboardImage: E2EImage? {
        world.pasteboardPNG.flatMap(E2EImage.init(png:))
    }

    func rememberedSelection() throws -> CGRect {
        guard let rect = rects["selection"] else { throw E2EScriptError.missing("selection") }
        return rect
    }

    /// 最后一个标注
    func lastAnnotation() throws -> Annotation {
        guard let annotation = try requireSession().document.annotations.last else {
            throw E2EScriptError.missing("annotation")
        }
        return annotation
    }
}

extension E2EStep {
    /// 剪贴板里有合法 PNG，且像素尺寸等于 expected
    static func expectPNG(_ title: String, _ expected: @escaping @MainActor (E2EContext) throws -> CGSize) -> E2EStep {
        eventually(title) { context in
            guard let image = context.pasteboardImage, let size = try? expected(context) else { return false }
            return image.width == Int(size.width) && image.height == Int(size.height)
        } detail: { context in
            let size = context.pasteboardImage.map { "\($0.width)x\($0.height)" } ?? "no PNG"
            let wanted = (try? expected(context)).map { "\(Int($0.width))x\(Int($0.height))" } ?? "?"
            return "expected \(wanted), got \(size)"
        }
    }

    /// 最新的历史条目是截图来源的图片，尺寸与剪贴板 PNG 一致
    static var expectScreenshotHistoryItem: E2EStep {
        expect("newest history item is a screenshot image") { context in
            guard let item = context.world.history.first, let image = item.image,
                let png = context.pasteboardImage
            else { return false }
            return item.kind == .image && item.source?.name == ScreenshotOutputService.screenshotSource.name
                && image.width == png.width && image.height == png.height
        }
    }

    static var rememberSelection: E2EStep {
        remember("selection") { context in context.rects["selection"] = try context.requireSelection() }
    }

    /// 选区等于 expected（容差 0.01 pt）
    static func expectSelection(_ title: String, _ expected: @escaping @MainActor (E2EContext) throws -> CGRect)
        -> E2EStep
    {
        E2EStep(title: title, kind: .check) { context in
            do {
                let wanted = try expected(context)
                let got = try context.requireSelection()
                let close = [
                    (wanted.minX, got.minX), (wanted.minY, got.minY), (wanted.width, got.width),
                    (wanted.height, got.height),
                ].allSatisfy { abs($0 - $1) < 0.01 }
                context.record(title, close, detail: "expected \(wanted), got \(got)")
            } catch {
                context.record(title, false, detail: "\(error)")
            }
        }
    }

    /// 选区四边都落在设备像素上（显示的就是导出的）
    static var expectPixelAligned: E2EStep {
        expect("selection is aligned to device pixels") { context in
            let selection = try context.requireSelection()
            return [selection.minX, selection.minY, selection.width, selection.height].allSatisfy { value in
                let pixels = value * context.scale
                return abs(pixels - pixels.rounded()) < 0.001
            }
        }
    }

    /// 尺寸标签的文本 = 选区导出的像素尺寸
    static var expectSizeLabelMatchesSelection: E2EStep {
        expectEqual(
            "size label shows the export pixel size",
            { context in
                let size = context.pixelSize(of: try context.requireSelection())
                return "\(Int(size.width)) \u{00D7} \(Int(size.height))"
            },
            { $0.world.overlay?.debugScreenViews.compactMap(\.debugSizeLabelText).first }
        )
    }
}
#endif
