import AppKit
import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("TranslationPlacer 版面（合成位图）")
struct TranslationPlacerTests {
    private let hans = "\u{50A8}\u{5B58}\u{7A7A}\u{95F4}"
    private let white = CGColor.srgb(0xFFFFFF)

    private func text(
        _ string: String, x: CGFloat = 40, y: CGFloat = 40, size: CGFloat = 13,
        weight: NSFont.Weight = .regular, color: UInt32 = 0x000000
    ) -> TranslationTestScene.Text {
        TranslationTestScene.Text(
            string: string, origin: CGPoint(x: x, y: y), size: size, weight: weight, color: .srgb(color))
    }

    private func scene(
        _ texts: [TranslationTestScene.Text], background: TranslationTestScene.Background? = nil,
        size: CGSize = CGSize(width: 400, height: 120), scale: CGFloat = 2,
        extra: ((CGContext) -> Void)? = nil
    ) -> TranslationTestScene {
        TranslationTestScene(
            size: size, scale: scale, background: background ?? .solid(white), texts: texts, extra: extra)
    }

    private func solidColor(_ block: TranslatedBlock) -> PixelColor? {
        if case .solid(let color) = block.backdrop { return color }
        return nil
    }

    private func isPlate(_ block: TranslatedBlock) -> Bool {
        if case .plate = block.backdrop { return true }
        return false
    }

    // MARK: - 背景与文字色

    @Test("白底黑字：纯色填白、文字色为黑、逐行抹除矩形盖住墨迹并对齐像素")
    func solidLight() {
        let label = text("Storage settings")
        let scene = scene([label])
        let placed = TranslationPlacer.place(scene.block([label]), translation: hans, in: scene.frame)
        #expect(solidColor(placed) == .white)
        #expect(placed.textColor.relativeLuminance < 0.01)
        #expect(placed.eraseRects.count == 1)
        let ink = CTLineGetBoundsWithOptions(TranslationTestScene.line(label), .useGlyphPathBounds)
        let inkRect = CGRect(x: 40 + ink.minX, y: 40 - ink.maxY, width: ink.width, height: ink.height)
        #expect(placed.eraseRects[0].contains(inkRect.insetBy(dx: 0.5, dy: 0.5)))
        for rect in placed.eraseRects {
            #expect((rect.minX * 2).rounded() == rect.minX * 2 && (rect.height * 2).rounded() == rect.height * 2)
        }
        #expect(placed.eraseFrame.contains(placed.textFrame))
        #expect(placed.language == "zh-Hans")
        #expect(placed.text == hans)
        #expect(placed.blockID == 0)
    }

    @Test("深色背景白字、彩色按钮白字：背景色取环带中位数，文字色取最远的墨迹")
    func darkAndColored() {
        for (background, foreground) in [
            (UInt32(0x1E1E1E), UInt32(0xFFFFFF)), (0x007AFF, 0xFFFFFF), (0xF5F5F7, 0x6E6E73),
        ] {
            let label = text("Continue", color: foreground)
            let scene = scene([label], background: .solid(.srgb(background)))
            let placed = TranslationPlacer.place(scene.block([label]), translation: hans, in: scene.frame)
            let expected = PixelColor(
                red: Double((background >> 16) & 0xFF) / 255, green: Double((background >> 8) & 0xFF) / 255,
                blue: Double(background & 0xFF) / 255)
            #expect(solidColor(placed) == expected)
            let ink = placed.textColor
            #expect(abs(ink.red * 255 - Double((foreground >> 16) & 0xFF)) <= 3)
            #expect(abs(ink.blue * 255 - Double(foreground & 0xFF)) <= 3)
        }
    }

    @Test("渐变、棋盘等复杂背景：衬底，外扩 6 pt，带模糊背景")
    func complexUsesPlate() {
        let label = text("Get 2 TB free", size: 20, weight: .bold, color: 0xFFFFFF)
        for background in [
            TranslationTestScene.Background.gradient(.srgb(0x5E5CE6), .srgb(0x0A84FF)),
            .checker(.srgb(0x223344), .srgb(0x556677), cell: 3),
        ] {
            let scene = scene([label], background: background)
            let block = scene.block([label])
            let placed = TranslationPlacer.place(block, translation: hans, in: scene.frame)
            #expect(isPlate(placed))
            #expect(placed.plateImage != nil)
            #expect(placed.eraseRects == [placed.eraseFrame])
            #expect(placed.eraseFrame.minX < block.frame.minX - 5)
            #expect(placed.textColor.relativeLuminance > 0.8)
            #expect(placed.alignment == .leading)
        }
    }

    @Test("对比度不足：沿原有明暗方向加深到 3:1，不翻转；绿底白字保持白字")
    func contrastGuard() {
        let gray = text("Search messages", color: 0xD8D8D8)
        let light = scene([gray])
        let placed = TranslationPlacer.place(light.block([gray]), translation: hans, in: light.frame)
        #expect(placed.textColor.contrastRatio(with: .white) >= 2.99)
        #expect(placed.textColor.relativeLuminance > 0.05, "only darkened as much as needed, not black")
        let install = text("Install", weight: .semibold, color: 0xFFFFFF)
        let green = scene([install], background: .solid(.srgb(0x34C759)))
        let button = TranslationPlacer.place(green.block([install]), translation: hans, in: green.frame)
        #expect(button.textColor == .white)
    }

    // MARK: - 字号与粗细

    @Test("字号按墨迹估计：拉丁 13 / 20 pt、CJK 13 pt 误差 ≤ 1 pt；1x 同样")
    func fontSize() {
        for (string, size, scale) in [
            ("General", CGFloat(13), CGFloat(2)), ("Recommendations", 20, 2), ("Storage", 13, 1),
        ] {
            let label = text(string, size: size)
            let scene = scene([label], scale: scale)
            let placed = TranslationPlacer.place(scene.block([label]), translation: hans, in: scene.frame)
            #expect(abs(placed.fontSize - size) <= 1, "\(string) \(size)pt @\(scale)x → \(placed.fontSize)")
        }
        let cjk = text(hans, size: 13)
        let cjkScene = scene([cjk])
        let placed = TranslationPlacer.place(
            cjkScene.block([cjk], ideographic: true), translation: "Storage", in: cjkScene.frame)
        #expect(abs(placed.fontSize - 13) <= 1)
        #expect(placed.language == nil)
    }

    @Test("粗细：常规判为非粗体，semibold / bold 判为粗体")
    func boldDetection() {
        for (weight, bold) in [(NSFont.Weight.regular, false), (.semibold, true), (.bold, true)] {
            let label = text("Recommendations", size: 17, weight: weight)
            let scene = scene([label])
            let placed = TranslationPlacer.place(scene.block([label]), translation: hans, in: scene.frame)
            #expect(placed.isBold == bold, "\(weight)")
        }
    }

    // MARK: - 放不下

    @Test("① 右侧有同色空白：不缩字，排版框向右扩展")
    func extendsIntoFreeSpace() {
        let label = text("Mail")
        let scene = scene([label])
        let block = scene.block([label])
        let placed = TranslationPlacer.place(block, translation: "Electronic mail settings", in: scene.frame)
        #expect(placed.fontSize == 13)
        #expect(placed.textFrame.maxX > block.frame.maxX + 40)
        #expect(placed.lines.count == 1)
    }

    @Test("扩展不越过 limit（选区）")
    func extensionRespectsLimit() {
        let label = text("Mail")
        let scene = scene([label])
        let block = scene.block([label])
        let limit = CGRect(x: 0, y: 0, width: block.frame.maxX + 10, height: block.frame.maxY + 3)
        let placed = TranslationPlacer.place(
            block, translation: "Electronic mail settings", in: scene.frame, within: limit)
        #expect(placed.textFrame.maxX <= limit.maxX + 1)
        #expect(placed.fontSize < 13)
        #expect(placed.lines.count == 1)
    }

    /// 灰框按钮（点坐标 x…x+w），文字居中
    private func button(width: CGFloat, label: String) -> (TranslationTestScene, TextBlock) {
        let line = TranslationTestScene.line(text(label))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let item = text(label, x: 100 + (width - advance) / 2, y: 64)
        let scene = scene([item]) { context in
            context.setFillColor(CGColor.srgb(0xE5E5EA))
            context.addPath(
                CGPath(
                    roundedRect: CGRect(x: 100, y: 45, width: width, height: 28), cornerWidth: 7, cornerHeight: 7,
                    transform: nil))
            context.fillPath()
        }
        return (scene, scene.block([item]))
    }

    @Test("按钮：左右止于按钮边缘且对称 → 居中；② 放不下时以 0.5 pt 步长缩字，不低于 75%")
    func shrinksInsideButton() {
        let (scene, block) = button(width: 90, label: "Cancel")
        let short = TranslationPlacer.place(block, translation: "\u{53D6}\u{6D88}", in: scene.frame)
        #expect(short.alignment == .center)
        #expect(solidColor(short) == PixelColor(red: 229.0 / 255, green: 229.0 / 255, blue: 234.0 / 255))
        #expect(abs(short.textFrame.midX - 145) <= 1)
        let long = TranslationPlacer.place(block, translation: "Abbrechen jetzt", in: scene.frame)
        #expect(long.fontSize < 13 && long.fontSize >= 13 * 0.75)
        #expect((long.fontSize * 2).rounded() == long.fontSize * 2)
        #expect(long.textFrame.minX >= 100 && long.textFrame.maxX <= 190)
    }

    @Test("③ 缩到 75% 仍放不下：末尾省略号")
    func ellipsis() {
        let (scene, block) = button(width: 90, label: "Cancel")
        let placed = TranslationPlacer.place(
            block, translation: "Papierkorb sofort endgültig entleeren", in: scene.frame)
        #expect(placed.fontSize == 9.75 || placed.fontSize == 10)
        #expect(placed.lines.count == 1)
        #expect(placed.lines[0].text.hasSuffix(TranslationTypesetter.ellipsis))
    }

    @Test("多行段落：沿用原行距，首行位置不变，左对齐于原文笔位")
    func multiLine() {
        let lines = (0..<3).map { text("Optimize storage to free up space \($0)", x: 30, y: 30 + 19 * CGFloat($0)) }
        let scene = scene(lines, size: CGSize(width: 400, height: 140))
        let placed = TranslationPlacer.place(
            scene.block(lines), translation: String(repeating: hans, count: 10), in: scene.frame)
        #expect(placed.lines.count >= 2)
        let pitches = zip(placed.lines.dropFirst(), placed.lines).map { $0.origin.y - $1.origin.y }
        #expect(pitches.allSatisfy { abs($0 - 19) <= 0.6 })
        #expect(abs(placed.lines[0].origin.x - 30) <= 1)
        #expect(abs(placed.lines[0].origin.y - 30) <= 1.5)
        #expect(placed.eraseRects.count == 3)
    }

    @Test("多行放不下时向下方同色空白多排几行")
    func multiLineExtendsDown() {
        let lines = (0..<2).map { text("Optimize storage to free up space", x: 30, y: 30 + 19 * CGFloat($0)) }
        let scene = scene(lines, size: CGSize(width: 300, height: 200))
        let placed = TranslationPlacer.place(
            scene.block(lines), translation: String(repeating: "Optimize the storage ", count: 5), in: scene.frame)
        #expect(placed.lines.count > 2)
        #expect(placed.fontSize == 13)
    }

    @Test("单行长句：一行缩到 75% 仍放不下且下方有空白时折行，不省略")
    func singleLineWraps() {
        let label = text("\u{4F60}\u{53EF}\u{4EE5}\u{5728}\u{8FD9}\u{91CC}\u{7BA1}\u{7406}", x: 30, y: 30)
        let scene = scene([label], size: CGSize(width: 220, height: 200))
        let placed = TranslationPlacer.place(
            scene.block([label], ideographic: true),
            translation: "Manage software updates and the items that open when you log in.", in: scene.frame,
            within: CGRect(x: 0, y: 0, width: 150, height: 200))
        #expect(placed.lines.count >= 2)
        #expect(!placed.lines.contains { $0.text.hasSuffix(TranslationTypesetter.ellipsis) })
    }

    // MARK: - 对齐

    @Test("分块给出的右对齐 / 居中对单行块直接生效；右侧紧贴、左侧空旷时推断为右对齐")
    func alignmentSources() {
        let value = text("Yesterday", x: 300, y: 40)
        let scene = scene([value]) { context in
            context.setFillColor(CGColor.srgb(0x888888))
            context.fill(CGRect(x: 364, y: 20, width: 2, height: 40))
        }
        let base = scene.block([value])
        let trailing = TextBlock(id: 0, lines: base.lines, alignment: .trailing, text: base.text)
        let placed = TranslationPlacer.place(trailing, translation: "\u{6628}\u{5929}", in: scene.frame)
        #expect(placed.alignment == .trailing)
        let right = TranslationTypesetter.bearings(of: "y", style: .init(fontSize: 13, isBold: false, language: nil))
            .right
        #expect(abs(placed.textFrame.maxX - (base.frame.maxX + right)) <= 1.5)
        let inferred = TranslationPlacer.place(base, translation: "\u{6628}\u{5929}", in: scene.frame)
        #expect(inferred.alignment == .trailing)
    }

    // MARK: - 边界情况

    @Test("空译文：不排文字，只抹除；块在帧外：按白底黑字兜底")
    func edgeCases() {
        let label = text("Storage")
        let scene = scene([label])
        let empty = TranslationPlacer.place(scene.block([label]), translation: "  ", in: scene.frame)
        #expect(empty.lines.isEmpty)
        #expect(empty.eraseFrame.contains(empty.textFrame))
        #expect(empty.textFrame.intersects(scene.block([label]).frame))
        let outside = TextBlock(
            id: 3, lines: [RecognizedLine(text: "Far away", frame: CGRect(x: 5000, y: 5000, width: 60, height: 14))],
            alignment: .leading, text: "Far away")
        let placed = TranslationPlacer.place(outside, translation: hans, in: scene.frame)
        #expect(solidColor(placed) == .white)
        #expect(placed.textColor == .black)
        #expect(placed.blockID == 3)
    }

    @Test("可在后台线程调用，结果与主线程一致")
    func offMainThread() async {
        let label = text("Storage")
        let scene = scene([label])
        let block = scene.block([label])
        let frame = scene.frame
        let background = await Task.detached {
            TranslationPlacer.place(block, translation: "\u{50A8}\u{5B58}", in: frame)
        }.value
        #expect(background.lines == TranslationPlacer.place(block, translation: "\u{50A8}\u{5B58}", in: frame).lines)
    }

    @Test("没有行的块不崩溃：不抹除、不排字，外框为块外框（没有行时为零矩形）")
    func zeroLineBlock() {
        let label = text("Storage")
        let scene = scene([label])
        let placed = TranslationPlacer.place(
            TextBlock(id: 9, lines: [], alignment: .center, text: ""), translation: " \u{50A8}\u{5B58} ",
            in: scene.frame)
        #expect(placed.blockID == 9 && placed.lines.isEmpty && placed.eraseRects.isEmpty)
        #expect(placed.eraseFrame == .zero && placed.textFrame == .zero)
        #expect(placed.text == "\u{50A8}\u{5B58}" && placed.alignment == .center)
    }

    @Test("剪贴板图片的合成帧：屏幕 id 0、原点 (0,0)、2x；只用帧的图像与 frame / scale，版面与绘制照常")
    func syntheticHistoryFrame() throws {
        let label = text("Optimize Storage", x: 20, y: 30)
        let rendered = scene([label], size: CGSize(width: 200, height: 60))
        let synthetic = FrozenFrame(
            screen: CaptureScreen(id: 0, frame: CGRect(x: 0, y: 0, width: 200, height: 60), scale: 2),
            image: rendered.frame.image)
        let block = rendered.block([label])
        let placed = TranslationPlacer.place(block, translation: hans, in: synthetic)
        #expect(solidColor(placed) == .white && placed.lines.count == 1)
        #expect(CGRect(x: 0, y: 0, width: 200, height: 60).contains(placed.eraseFrame))
        let canvas = TestCanvas(image: synthetic.image)
        let environment = RenderEnvironment(
            origin: .zero, scale: 2, targetPixelSize: CGSize(width: 400, height: 120), pixelatedFrame: nil,
            frameOrigin: .zero)
        TranslationPainter.draw([placed], in: canvas.context, environment: environment)
        let ink = CTLineGetBoundsWithOptions(TranslationTestScene.line(label), .useGlyphPathBounds)
        #expect(canvas.pixel(x: Int((20 + ink.maxX) * 2) - 2, y: Int((30 - ink.midY) * 2)).isWhite)
        #expect(canvas.countPixels { $0.red < 100 } > 20)
    }
}
