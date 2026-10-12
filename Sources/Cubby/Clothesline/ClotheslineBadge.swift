import SwiftUI

/// 晾衣绳相关的图标与文案（各入口共用）
enum ClotheslineCopy {
    /// 挂在绳上的照片
    static let symbolName = "photo.on.rectangle.angled"

    static var hang: String {
        String(localized: "Hang on Clothesline", comment: "Context menu item and hover button for images")
    }

    static var takeDown: String {
        String(localized: "Take Down from Clothesline", comment: "Context menu item and hover button for images")
    }

    static func toggleTitle(isHanging: Bool) -> String {
        isHanging ? takeDown : hang
    }
}

/// 图片右上角的「晾着」徽标：半透明黑底胶囊 + 白字（两种外观相同，叠在图片上）
struct ClotheslineBadge: View {
    var body: some View {
        Label {
            Text("Hanging", comment: "Badge on an image that is on the clothesline")
        } icon: {
            Image(systemName: ClotheslineCopy.symbolName)
        }
        .labelStyle(.titleAndIcon)
        .font(.system(size: FontSize.caption2, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .padding(8)
    }
}
