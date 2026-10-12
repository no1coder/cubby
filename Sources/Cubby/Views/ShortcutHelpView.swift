import SwiftUI
import CubbyCore

/// 快捷键帮助浮层：盖住整个面板，顶部标题与关闭按钮、中间分组、底部「完整使用说明…」与「按 esc 关闭」；
/// 点击空白处、关闭按钮或按 esc 关闭
struct HelpOverlay: View {
    let content: ShortcutHelpContent
    /// 底部「完整使用说明…」链接；nil 时不显示
    var onOpenUserGuide: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PanelChrome.cornerRadius, style: .continuous)
                .fill(.thickMaterial)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                header
                sectionsArea
                Divider().opacity(0.6)
                footer
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Keyboard Shortcuts", comment: "Shortcut help title")
                .font(.system(size: FontSize.title, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(Text("Close (esc)", comment: "Shortcut help: tooltip of the close button"))
            .accessibilityLabel(Text("Close help", comment: "Shortcut help: close button"))
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 6, trailing: 14))
    }

    /// 放得下时直接显示；放不下（浮动面板行数多、底部横条只有 304 高）时中间这段可以滚动，标题与底栏不动
    private var sectionsArea: some View {
        ViewThatFits(in: .vertical) {
            sections
            ScrollView { sections }
                .scrollIndicators(.automatic)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 宽的面板（底部横条）各组并排成列，窄的面板上下排成一列
    private var sections: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) {
                ForEach(content.sections) { section in
                    HelpSectionView(section: section).frame(width: 340)
                }
            }
            // 横条放不下四列时（如 1440pt 宽的屏幕）先排成两列，再退成单列
            HStack(alignment: .top, spacing: 32) {
                ForEach(Self.halves(of: content.sections), id: \.first?.id) { column in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(column) { HelpSectionView(section: $0) }
                    }
                    .frame(width: 340)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(content.sections) { section in
                    HelpSectionView(section: section)
                }
            }
            .frame(maxWidth: 440)
        }
        .padding(EdgeInsets(top: 2, leading: 18, bottom: 10, trailing: 18))
        .frame(maxWidth: .infinity)
    }

    /// 把分组按顺序分成前后两半（两列排布）
    private static func halves(of sections: [ShortcutHelpContent.Section]) -> [[ShortcutHelpContent.Section]] {
        let middle = (sections.count + 1) / 2
        return [Array(sections[..<middle]), Array(sections[middle...])].filter { !$0.isEmpty }
    }

    private var footer: some View {
        HStack {
            if let onOpenUserGuide {
                Button("Full user guide…", action: onOpenUserGuide)
                    .buttonStyle(.link)
                    .font(.system(size: FontSize.footnote))
            }
            Spacer(minLength: 12)
            Text("Press esc to close", comment: "Shortcut help footer")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(Color.primary.opacity(0.6))
                .e2eAnchor("help.footer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

/// 帮助浮层的一组：小标题（图片组带「新」徽标）+ 各行「说明 … 键帽」
private struct HelpSectionView: View {
    let section: ShortcutHelpContent.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(.system(size: FontSize.caption, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .accessibilityAddTraits(.isHeader)
                if section.isNew {
                    Text("New", comment: "Badge next to a shortcut help section with new features")
                        .font(.system(size: FontSize.caption2, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.25)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            ForEach(section.rows) { row in
                HelpRowView(row: row)
            }
        }
    }
}

private struct HelpRowView: View {
    let row: ShortcutHelpContent.Row

    var body: some View {
        HStack(spacing: 10) {
            Text(row.label)
                .font(.system(size: FontSize.footnote))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(row.keys, id: \.self) { KeyCap(text: $0, prominent: true) }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .e2eAnchor("help.\(row.id)")
    }
}
