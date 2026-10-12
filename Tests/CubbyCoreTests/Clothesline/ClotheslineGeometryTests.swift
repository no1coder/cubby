import CoreGraphics
import Foundation
import Testing
@testable import CubbyCore

/// 晾衣绳的几何（docs/UI-UPGRADE-PLAN.md 第 5 节「外观」）：绳子下垂、照片分布与尺寸、倾角与摆动
@Suite("ClotheslineGeometry 晾衣绳几何")
struct ClotheslineGeometryTests {
    private let width: CGFloat = 1440
    private let inset = ClotheslineGeometry.anchorInset

    // MARK: - 绳子

    @Test("两端固定点处不下垂，正中下垂 sag")
    func ropeEndsAndMiddle() {
        #expect(ClotheslineGeometry.ropeDrop(at: inset, width: width, sag: 30) == 0)
        #expect(ClotheslineGeometry.ropeDrop(at: width - inset, width: width, sag: 30) == 0)
        #expect(ClotheslineGeometry.ropeDrop(at: width / 2, width: width, sag: 30) == 30)
    }

    @Test("左右对称，越靠近中间越低", arguments: [CGFloat(100), 300, 500])
    func ropeSymmetric(_ offset: CGFloat) {
        let left = ClotheslineGeometry.ropeDrop(at: inset + offset, width: width, sag: 30)
        let right = ClotheslineGeometry.ropeDrop(at: width - inset - offset, width: width, sag: 30)
        #expect(abs(left - right) < 1e-9)
        let nearer = ClotheslineGeometry.ropeDrop(at: inset + offset + 50, width: width, sag: 30)
        #expect(nearer > left)
    }

    @Test("固定点之外按固定点处理", arguments: [CGFloat(0), -50, 1440, 2000])
    func ropeOutsideAnchors(_ x: CGFloat) {
        #expect(ClotheslineGeometry.ropeDrop(at: x, width: width, sag: 30) == 0)
    }

    @Test("窗口窄于两端留白时不下垂", arguments: [CGFloat(0), 40, 56])
    func ropeDegenerate(_ narrow: CGFloat) {
        #expect(ClotheslineGeometry.ropeDrop(at: narrow / 2, width: narrow, sag: 30) == 0)
    }

    // MARK: - 照片分布

    @Test("没有照片时没有位置")
    func centersEmpty() {
        #expect(ClotheslineGeometry.centers(count: 0, width: width).isEmpty)
    }

    @Test("一张照片居中")
    func centersSingle() {
        #expect(ClotheslineGeometry.centers(count: 1, width: width) == [width / 2])
    }

    @Test("多张照片等分两端之间，每张居中于自己那段")
    func centersEvenlySpaced() {
        let centers = ClotheslineGeometry.centers(count: 4, width: 1056)
        // 两端之间 1000，每段 250
        #expect(centers == [153, 403, 653, 903])
    }

    @Test("窗口过窄时所有照片落在左端固定点")
    func centersNarrow() {
        #expect(ClotheslineGeometry.centers(count: 3, width: 20) == [inset, inset, inset])
    }

    @Test("照片宽度：放得下时取上限")
    func photoWidthFits() {
        #expect(ClotheslineGeometry.photoWidth(count: 4, width: width, maxWidth: 180) == 180)
    }

    @Test("照片宽度：放不下时按段宽减去间距缩小")
    func photoWidthShrinks() {
        // 两端之间 1000，12 张每段 83.33，减去 18
        let shrunk = ClotheslineGeometry.photoWidth(count: 12, width: 1056, maxWidth: 180)
        #expect(abs(shrunk - (1000.0 / 12 - ClotheslineGeometry.minimumGap)) < 1e-9)
    }

    @Test("照片宽度不小于下限")
    func photoWidthMinimum() {
        #expect(ClotheslineGeometry.photoWidth(count: 12, width: 400, maxWidth: 180) == 56)
        #expect(ClotheslineGeometry.photoWidth(count: 12, width: 400, maxWidth: 180, minimumWidth: 40) == 40)
    }

    @Test("没有照片时照片宽度为上限")
    func photoWidthEmpty() {
        #expect(ClotheslineGeometry.photoWidth(count: 0, width: width, maxWidth: 180) == 180)
    }

    // MARK: - 照片尺寸

    @Test("横图受宽度限制，保持宽高比")
    func photoSizeLandscape() {
        let size = ClotheslineGeometry.photoSize(pixelWidth: 1600, pixelHeight: 1000, maxWidth: 160, maxHeight: 140)
        #expect(size == CGSize(width: 160, height: 100))
    }

    @Test("竖图受高度限制，保持宽高比")
    func photoSizePortrait() {
        let size = ClotheslineGeometry.photoSize(pixelWidth: 1000, pixelHeight: 2000, maxWidth: 160, maxHeight: 140)
        #expect(size == CGSize(width: 70, height: 140))
    }

    @Test("尺寸取整")
    func photoSizeRounded() {
        let size = ClotheslineGeometry.photoSize(pixelWidth: 1000, pixelHeight: 3000, maxWidth: 160, maxHeight: 100)
        #expect(size == CGSize(width: 33, height: 100))
    }

    @Test("像素尺寸未知时按 4:3 占满宽度", arguments: [(0, 100), (100, 0), (-1, -1)])
    func photoSizeUnknown(_ pixelWidth: Int, _ pixelHeight: Int) {
        let size = ClotheslineGeometry.photoSize(
            pixelWidth: pixelWidth, pixelHeight: pixelHeight, maxWidth: 160, maxHeight: 140)
        #expect(size == CGSize(width: 160, height: 120))
    }

    // MARK: - 倾角与摆动

    @Test("静止倾角左右交替，不超过上限，每 8 张循环")
    func restingTilt() {
        let tilts = (0..<8).map { ClotheslineGeometry.restingTilt(index: $0) }
        for (current, next) in zip(tilts, tilts.dropFirst()) {
            #expect(current.sign != next.sign)
        }
        #expect(tilts.allSatisfy { abs($0) <= 2.5 })
        #expect(ClotheslineGeometry.restingTilt(index: 9) == tilts[1])
        #expect(ClotheslineGeometry.restingTilt(index: 1, maxDegrees: 5) == 2 * tilts[1])
    }

    @Test("静止倾角的具体值（度）")
    func restingTiltValues() {
        #expect(ClotheslineGeometry.restingTilt(index: 0) == -0.6 * 2.5)
        #expect(ClotheslineGeometry.restingTilt(index: 3) == 1.0 * 2.5)
    }

    @Test("负数序号按循环取值，不越界", arguments: [-1, -8, -9])
    func restingTiltNegativeIndex(_ index: Int) {
        let wrapped = (index % 8 + 8) % 8
        #expect(ClotheslineGeometry.restingTilt(index: index) == ClotheslineGeometry.restingTilt(index: wrapped))
    }

    @Test("没刚挂上时只有微风摆动，幅度不超过 amplitude", arguments: [0.0, 0.7, 3.3, 120.5])
    func breezeOnly(_ time: Double) {
        for index in 0..<4 {
            let angle = ClotheslineGeometry.swing(time: time, index: index, sinceHung: nil)
            #expect(abs(angle) <= 1.2)
        }
    }

    @Test("不同照片的摆动相位不同")
    func breezePhases() {
        let first = ClotheslineGeometry.swing(time: 1, index: 0, sinceHung: nil)
        let second = ClotheslineGeometry.swing(time: 1, index: 1, sinceHung: nil)
        #expect(first != second)
    }

    @Test("挂上的时间为负数时按未挂上处理")
    func negativeSinceHung() {
        let breeze = ClotheslineGeometry.swing(time: 2, index: 1, sinceHung: nil)
        #expect(ClotheslineGeometry.swing(time: 2, index: 1, sinceHung: -0.5) == breeze)
    }

    @Test("刚挂上时额外摆动，随后衰减回微风摆动")
    func settleDecays() {
        let breeze = ClotheslineGeometry.swing(time: 2, index: 1, sinceHung: nil)
        let early = ClotheslineGeometry.swing(time: 2, index: 1, sinceHung: 0.15)
        let late = ClotheslineGeometry.swing(time: 2, index: 1, sinceHung: 5)
        #expect(abs(early - breeze) > 3)
        #expect(abs(late - breeze) < 0.001)
    }
}
