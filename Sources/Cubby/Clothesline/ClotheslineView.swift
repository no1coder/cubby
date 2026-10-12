import CubbyCore
import SwiftUI

/// 屏幕顶部的晾衣绳（docs/UI-UPGRADE-PLAN.md 第 5 节）：两端固定点 + 下垂的绳子、木夹子、白边相纸，
/// 静止倾角交替，微风摆动（减弱动态效果时静止）。悬停的照片放大 1.04、强调色外环、左上角 × 与下方提示胶囊
struct ClotheslineView: View {
    let model: ClotheslineModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 摆动的刷新频率
    private static let frameInterval: TimeInterval = 1.0 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: reduceMotion || !model.isShown)) {
            context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                Rope(layout: model.layout)
                ForEach(model.layout.photos) { photo in
                    if let entry = model.entry(for: photo.id) {
                        photoView(photo, entry: entry, time: time)
                    }
                }
                if let hovered = model.layout.photos.first(where: { $0.id == model.hoveredID }),
                    model.editingID == nil
                {
                    ClotheslineHint()
                        .position(x: hovered.frame.midX, y: hovered.frame.maxY + 26)
                        .transition(.opacity)
                }
            }
            .frame(width: model.layout.width, height: ClotheslineLayout.windowHeight, alignment: .topLeading)
        }
        .animation(
            Motion.animation(.easeOut(duration: Motion.fade), reduceMotion: reduceMotion), value: model.hoveredID
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Clothesline", comment: "Accessibility label of the clothesline window"))
    }

    @ViewBuilder
    private func photoView(_ photo: ClotheslineLayout.Photo, entry: ClotheslineModel.Entry, time: TimeInterval)
        -> some View
    {
        if model.editingID == photo.id {
            // 放大编辑中：原位置显示虚线空位
            RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(0.4))
                .frame(width: photo.frame.width * 0.3, height: photo.frame.height * 0.2)
                .position(x: photo.frame.midX, y: photo.frame.minY + photo.frame.height * 0.1 + 6)
        } else if model.editingID != nil {
            // 放大编辑中：其余照片收起，绳上只留夹子（不挡住编辑器的标题行）
            Clothespin()
                .frame(width: ClotheslinePhotoView.pinSize.width, height: ClotheslinePhotoView.pinSize.height)
                .position(x: photo.frame.midX, y: photo.frame.minY)
        } else {
            ClotheslinePhotoView(
                photo: photo, entry: entry, isHovered: model.hoveredID == photo.id,
                onCopy: { model.onCopy(entry.item) },
                onEdit: { model.onEdit(entry.item) },
                onRemove: { model.onRemove(entry.item) }
            )
            .rotationEffect(.degrees(angle(for: photo, time: time)), anchor: .top)
            .position(x: photo.frame.midX, y: photo.frame.midY)
        }
    }

    /// 静止倾角 + 微风摆动（刚挂上的额外衰减摆动）；减弱动态效果时只有静止倾角
    private func angle(for photo: ClotheslineLayout.Photo, time: TimeInterval) -> Double {
        guard !reduceMotion else { return photo.tilt }
        let sinceHung = model.hungAt[photo.id].map { ProcessInfo.processInfo.systemUptime - $0 }
        // 悬停时停住摆动，方便点击
        let breeze =
            model.hoveredID == photo.id
            ? 0 : ClotheslineGeometry.swing(time: time, index: photo.index, sinceHung: sinceHung)
        return photo.tilt + breeze
    }
}

/// 绳子与两端固定点：二次贝塞尔曲线的控制点取在正中 2 × 下垂处，曲线正中恰好下垂 sag
private struct Rope: View {
    let layout: ClotheslineLayout

    @Environment(\.colorScheme) private var colorScheme

    private static let anchorDiameter: CGFloat = 10

    var body: some View {
        let inset = ClotheslineGeometry.anchorInset
        let start = CGPoint(x: inset, y: ClotheslineLayout.anchorY)
        let end = CGPoint(x: layout.width - inset, y: ClotheslineLayout.anchorY)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: start)
                path.addQuadCurve(
                    to: end,
                    control: CGPoint(x: layout.width / 2, y: ClotheslineLayout.anchorY + ClotheslineLayout.sag * 2))
            }
            .stroke(ropeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            ForEach([start, end], id: \.x) { point in
                Circle()
                    .fill(Color.gray.opacity(0.85))
                    .overlay(Circle().fill(Color.white.opacity(0.6)).padding(3))
                    .frame(width: Self.anchorDiameter, height: Self.anchorDiameter)
                    .position(point)
            }
        }
        .accessibilityHidden(true)
    }

    private var ropeColor: Color {
        colorScheme == .dark ? Color(red: 0.84, green: 0.8, blue: 0.72) : Color(red: 0.62, green: 0.56, blue: 0.47)
    }
}

/// 悬停提示：「单击 放大编辑 | 双击 复制 | 拖到应用」
private struct ClotheslineHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Click to edit", comment: "Clothesline hover hint")
            divider
            Text("Double-click to copy", comment: "Clothesline hover hint")
            divider
            Text("Drag to an app", comment: "Clothesline hover hint")
        }
        .font(.system(size: FontSize.caption, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.72)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 12)
    }
}
