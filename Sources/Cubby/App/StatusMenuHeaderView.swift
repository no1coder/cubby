import AppKit

/// 菜单栏菜单顶部的头部：应用图标 + 「Cubby」+ 状态行（正在记录 · 128 条 / 已暂停 · 128 条 / 红色「地址被替换」）
@MainActor
final class StatusMenuHeaderView: NSView {
    /// 状态行的内容与是否为警示（红色）
    struct StatusLine: Equatable {
        let text: String
        let isAlert: Bool
    }

    private static let size = NSSize(width: 240, height: 48)
    private static let iconSize: CGFloat = 30

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "Cubby")
    private let statusField = NSTextField(labelWithString: "")

    var statusLine = StatusLine(text: "", isAlert: false) {
        didSet {
            statusField.stringValue = statusLine.text
            statusField.textColor = statusLine.isAlert ? .systemRed : .secondaryLabelColor
            setAccessibilityLabel("Cubby, \(statusLine.text)")
        }
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        autoresizingMask = [.width]
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.lineBreakMode = .byTruncatingTail
        layoutSubviewsOnce()
        // 整个头部对读屏器是一个静态文本（不可点击）
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 状态行：有未处理的地址替换时优先显示红色「地址被替换」，否则「正在记录 / 已暂停 · N 条」
    static func statusLine(paused: Bool, itemCount: Int, tamperPending: Bool) -> StatusLine {
        if tamperPending { return StatusLine(text: SecurityCopy.statusPill, isAlert: true) }
        let text =
            paused
            ? String(
                localized: "Paused · \(itemCount) items",
                comment: "Status menu header while recording is paused. %lld = number of items in history")
            : String(
                localized: "Recording · \(itemCount) items",
                comment: "Status menu header while recording. %lld = number of items in history")
        return StatusLine(text: text, isAlert: false)
    }

    private func layoutSubviewsOnce() {
        let labels = NSStackView(views: [titleField, statusField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        let row = NSStackView(views: [iconView, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        // 与菜单项文字左缘大致对齐（菜单项左侧留有勾选列）
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
