import SwiftUI
import CubbyCore

/// 「守护的内容」：每种类型一个可切换的标签，选中为蓝色淡底（设计稿），未选为中性淡底
struct GuardedKindChips: View {
    @Bindable var settings: AppSettings

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(SensitiveKind.allCases, id: \.self) { kind in
                chip(kind)
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ kind: SensitiveKind) -> some View {
        let isOn = settings.guardedKinds.contains(kind)
        return Button {
            settings.guardedKinds =
                isOn ? settings.guardedKinds.subtracting([kind]) : settings.guardedKinds.union([kind])
        } label: {
            Text(SecurityCopy.chipTitle(kind))
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 自动换行的横向排列
private struct ChipFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
