import CubbyCore
import SwiftUI

/// 绳上的一张照片：白边相纸（底边留白更宽）+ 夹在顶边的木夹子。
/// 单击放大编辑（等双击判定超时后才执行）、双击复制、拖出发送图片文件副本、悬停时左上角 × 取下
struct ClotheslinePhotoView: View {
    let photo: ClotheslineLayout.Photo
    let entry: ClotheslineModel.Entry
    let isHovered: Bool
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let hoverScale: CGFloat = 1.04
    static let pinSize = CGSize(width: 10, height: 24)
    private static let closeSize: CGFloat = 22

    var body: some View {
        paper
            .overlay(alignment: .top) {
                Clothespin().frame(width: Self.pinSize.width, height: Self.pinSize.height).offset(y: -12)
            }
            .overlay(alignment: .topLeading) { if isHovered { closeButton.offset(x: -9, y: -9) } }
            .scaleEffect(isHovered && !reduceMotion ? Self.hoverScale : 1, anchor: .top)
            .animation(Motion.animation(.easeOut(duration: Motion.fade), reduceMotion: reduceMotion), value: isHovered)
            // 双击优先；单击要等双击判定超时才执行（ExclusiveGesture 先等前一个手势失败）
            .gesture(TapGesture(count: 2).onEnded(onCopy).exclusively(before: TapGesture().onEnded(onEdit)))
            .onDrag {
                DragProvider.provider(for: entry.item) {
                    SharedFiles.exportImage(entry.item, source: entry.imageSource)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Copy", comment: "Clothesline photo action"), onCopy)
            .accessibilityAction(named: Text("Edit", comment: "Clothesline photo action"), onEdit)
            .accessibilityAction(named: Text("Take Down", comment: "Clothesline photo action"), onRemove)
    }

    private var paper: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        return
            shape
            .fill(Color(red: 0.98, green: 0.97, blue: 0.95))
            .frame(width: photo.frame.width, height: photo.frame.height)
            .overlay(alignment: .topLeading) {
                AsyncThumbnail(source: entry.imageSource, maxPixelSize: ImageThumbnail.pixelSize, contentMode: .fill)
                    .frame(width: photo.imageFrame.width, height: photo.imageFrame.height)
                    .clipped()
                    .offset(x: photo.imageFrame.minX, y: photo.imageFrame.minY)
            }
            .overlay {
                if isHovered {
                    shape.stroke(Color.accentColor, lineWidth: 2).padding(-1)
                    shape.stroke(Color.accentColor.opacity(0.25), lineWidth: 4).padding(-4)
                }
            }
            .shadow(color: .black.opacity(isHovered ? 0.35 : 0.25), radius: isHovered ? 10 : 5, y: isHovered ? 6 : 3)
    }

    private var closeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: FontSize.caption2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Self.closeSize, height: Self.closeSize)
                .background(Circle().fill(Color.black.opacity(0.72)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(Text("Take Down", comment: "Clothesline photo action"))
    }

    private var accessibilityLabel: String {
        [entry.item.source?.name ?? TextStats.unknownSource, entry.item.title].joined(separator: " · ")
    }
}

/// 木夹子：两片木条，中间一道缝
struct Clothespin: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.84, green: 0.62, blue: 0.4), Color(red: 0.7, green: 0.5, blue: 0.3)],
                    startPoint: .leading, endPoint: .trailing)
            )
            .overlay(Rectangle().fill(Color.black.opacity(0.18)).frame(width: 1))
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}
