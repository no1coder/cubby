import AppKit
import SwiftUI
import CubbyCore

/// 键帽样式的快捷键标签（与设置页 ShortcutKeyCap 同一视觉语言，玻璃上不加投影）
struct KeyCap: View {
    let text: String
    var prominent = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
        Text(text)
            .font(.system(size: FontSize.caption2, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(shape.fill(Color.primary.opacity(prominent ? 0.14 : 0.07)))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
            .foregroundStyle(prominent ? .primary : .secondary)
            // 「⇧↩」之类的符号读屏器读不好：朗读为「Shift Return」
            .accessibilityLabel(KeySpeech.spoken(text))
    }
}

/// 快捷键 + 说明
struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(text: keys)
            Text(label)
                .font(.system(size: FontSize.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 应用图标。应用未安装或来源未知时：提供了 fallbackSymbol 则显示类型符号底板（一眼可辨），
/// 否则显示系统通用应用图标
struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = PanelMetrics.sourceIconSize
    var fallbackSymbol: String?
    /// 彩色 / 代码卡传入卡片前景色；nil 时用标准配色（primary 0.7 粗体符号 + primary 0.14 底板，
    /// 此前 secondary 符号叠 secondary 0.14 底板几乎看不清）
    var fallbackTint: Color?

    var body: some View {
        if let icon = ImageCache.shared.appIcon(bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else if let fallbackSymbol {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(fallbackTint ?? Color.primary.opacity(0.7))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * Radius.iconRatio, style: .continuous)
                        .fill(fallbackTint.map { $0.opacity(0.18) } ?? Color.primary.opacity(0.14))
                )
        } else {
            Image(nsImage: ImageCache.shared.genericAppIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

/// 异步加载的缩略图：命中缓存时同步显示，否则后台解码。
/// 解码请求属于视图的 .task：视图消失（快速滚过的卡片）或 url 变化时，排队中的解码随之取消
struct AsyncThumbnail: View {
    let url: URL?
    let maxPixelSize: Int
    var contentMode: ContentMode = .fit

    /// 已加载的图及其来源 url：url 变化后不沿用旧图
    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        let image =
            loaded.flatMap { $0.url == url ? $0.image : nil }
            ?? url.flatMap { ImageCache.shared.cachedThumbnail(for: $0, maxPixelSize: maxPixelSize) }
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.primary.opacity(0.05))
            }
        }
        .task(id: url) {
            guard let url, loaded?.url != url else { return }
            // 命中缓存也记下：缓存在面板隐藏后被清空或被淘汰时，视图重算不会退回占位（.task 不会重跑）
            if let cached = ImageCache.shared.cachedThumbnail(for: url, maxPixelSize: maxPixelSize) {
                loaded = (url, cached)
                return
            }
            let thumbnail = await ImageCache.shared.thumbnail(for: url, maxPixelSize: maxPixelSize)
            // 已被取消（视图消失或 url 已变）的请求不再写回状态
            guard !Task.isCancelled, let thumbnail else { return }
            loaded = (url, thumbnail)
        }
    }
}

/// 关键词高亮与摘要
enum TextHighlighter {
    private static let maxMatchesPerKeyword = 50
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func attributed(_ text: String, keywords: [String], tint: Color) -> AttributedString {
        var attributed = AttributedString(text)
        for keyword in keywords where !keyword.isEmpty {
            var searchStart = text.startIndex
            for _ in 0..<maxMatchesPerKeyword {
                guard let range = text.range(of: keyword, options: options, range: searchStart..<text.endIndex),
                    let attributedRange = Range(range, in: attributed)
                else { break }
                attributed[attributedRange].backgroundColor = tint.opacity(0.28)
                attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    /// 首个命中位置靠后时，从命中处前几个字符开始截取，保证卡片里能看到关键词
    static func snippet(_ text: String, keywords: [String], maxLength: Int) -> String {
        let head = String(text.prefix(maxLength))
        let firstMatch =
            keywords
            .compactMap { head.range(of: $0, options: options)?.lowerBound }
            .min()
        guard let firstMatch, head.distance(from: head.startIndex, to: firstMatch) > 60 else {
            return head
        }
        let start = head.index(firstMatch, offsetBy: -24, limitedBy: head.startIndex) ?? head.startIndex
        return "…" + head[start...].replacingOccurrences(of: "\n", with: " ")
    }
}

/// 卡片的配色方案：普通 / 代码 / 颜色
struct CardPalette {
    let background: Color
    let primary: Color
    let secondary: Color
    let stroke: Color
    let isCustom: Bool

    /// 「增强对比度」下的描边：原先 0.06 的描边在玻璃上几乎不可见
    private static let increasedContrastStroke = 0.25
    /// 接近纯白的颜色：在深色面板里是一块刺眼的白，加深描边、文字略收
    private static let nearWhiteLuminance = 0.9
    /// 面板玻璃的大致亮度，用于判断半透明颜色卡上的文字颜色
    private static let darkBackdropLuminance = 0.15
    private static let lightBackdropLuminance = 0.9

    static func standard(_ scheme: ColorScheme, increasedContrast: Bool = false) -> CardPalette {
        CardPalette(
            background: scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.78),
            primary: .primary,
            secondary: increasedContrast ? Color.primary.opacity(0.8) : .secondary,
            stroke: Color.primary.opacity(increasedContrast ? increasedContrastStroke : 0.06),
            isCustom: false
        )
    }

    /// 代码卡：浅色模式为深色底；深色模式在玻璃上更深一级并加亮描边，与普通卡拉开层次
    static func code(_ scheme: ColorScheme, increasedContrast: Bool = false) -> CardPalette {
        CardPalette(
            background: scheme == .dark ? Color.black.opacity(0.38) : Color(red: 0.12, green: 0.12, blue: 0.14),
            primary: Color.white.opacity(0.9),
            secondary: Color.white.opacity(increasedContrast ? 0.8 : 0.55),
            stroke: increasedContrast
                ? Color.primary.opacity(increasedContrastStroke)
                : Color.white.opacity(scheme == .dark ? 0.10 : 0.0),
            isCustom: true
        )
    }

    /// 颜色卡：背景即颜色，文字按亮度选择黑 / 白。带透明度的颜色叠在面板上显示，
    /// 按当前外观的底色混合后再判断（深色面板上半透明的深紫应配白字，而不是按白底算出黑字）
    static func color(_ rgba: RGBAColor, scheme: ColorScheme, increasedContrast: Bool = false) -> CardPalette {
        let backdrop = scheme == .dark ? darkBackdropLuminance : lightBackdropLuminance
        let isLight = luminance(rgba) * rgba.alpha + backdrop * (1 - rgba.alpha) > 0.6
        let isNearWhite = isNearWhite(rgba)
        let foreground = isLight ? Color.black : Color.white
        // 接近纯白的卡片用深色描边：深色模式下 primary 是白色，白描边落在白卡上看不见
        let stroke =
            increasedContrast
            ? Color.primary.opacity(increasedContrastStroke)
            : (isNearWhite ? Color.black.opacity(0.2) : Color.primary.opacity(0.08))
        return CardPalette(
            background: rgba.swiftUIColor,
            primary: foreground.opacity(isNearWhite && !increasedContrast ? 0.75 : 0.88),
            secondary: foreground.opacity(increasedContrast ? 0.8 : 0.7),
            stroke: stroke,
            isCustom: true
        )
    }

    /// 颜色是否接近纯白（不透明且亮度 > 0.9；颜色预览的色块同样需要更明显的描边）
    static func isNearWhite(_ rgba: RGBAColor) -> Bool {
        rgba.alpha >= 1 && luminance(rgba) > nearWhiteLuminance
    }

    private static func luminance(_ rgba: RGBAColor) -> Double {
        0.299 * rgba.red + 0.587 * rgba.green + 0.114 * rgba.blue
    }
}

/// 键帽符号的朗读名称：VoiceOver 把「⇧↩」读成「Shift Return」而不是逐个念符号
enum KeySpeech {
    static func spoken(_ keys: String) -> String {
        var words: [String] = []
        var literal = ""
        func flush() {
            if !literal.isEmpty { words.append(literal) }
            literal = ""
        }
        for character in keys {
            if let name = name(of: character) {
                flush()
                words.append(name)
            } else if character == " " {
                flush()
            } else {
                literal.append(character)
            }
        }
        flush()
        return words.joined(separator: " ")
    }

    private static func name(of symbol: Character) -> String? {
        switch symbol {
        case "⌘": String(localized: "Command", comment: "Key name read by VoiceOver")
        case "⇧": String(localized: "Shift", comment: "Key name read by VoiceOver")
        case "⌥": String(localized: "Option", comment: "Key name read by VoiceOver")
        case "⌃": String(localized: "Control", comment: "Key name read by VoiceOver")
        case "↩": String(localized: "Return", comment: "Key name read by VoiceOver")
        case "⇥": String(localized: "Tab", comment: "Key name read by VoiceOver")
        case "⌫": String(localized: "Delete", comment: "Key name read by VoiceOver")
        case "↑": String(localized: "Up Arrow", comment: "Key name read by VoiceOver")
        case "↓": String(localized: "Down Arrow", comment: "Key name read by VoiceOver")
        case "⇞": String(localized: "Page Up", comment: "Key name read by VoiceOver")
        case "⇟": String(localized: "Page Down", comment: "Key name read by VoiceOver")
        default: nil
        }
    }
}

extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// 胶囊按钮：在非 key window（预览面板、引导窗口）中也保持稳定外观。
/// 系统 `.borderedProminent` 在窗口失去 key 状态时会变灰，因此统一使用本样式。
struct CapsuleButtonStyle: ButtonStyle {
    enum Size {
        /// 面板内的紧凑按钮
        case regular
        /// 窗口主操作（与系统 large 按钮同高）
        case large
    }

    var isPrimary = true
    var size: Size = .regular

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                .system(
                    size: size == .large ? FontSize.body : FontSize.footnote,
                    weight: size == .large ? .medium : .semibold)
            )
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .lineLimit(1)
            .padding(.horizontal, size == .large ? 16 : 14)
            .frame(minWidth: size == .large ? 120 : nil, minHeight: size == .large ? 28 : 24)
            .background(Capsule().fill(isPrimary ? Color.accentColor : Color.primary.opacity(0.08)))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .animation(.easeOut(duration: Motion.fade), value: configuration.isPressed)
    }
}
