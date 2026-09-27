import SwiftUI
import CubbyCore

/// 列表为空时的说明：区分首次使用、搜索无结果、收藏为空与分类为空，并给出下一步
struct EmptyStateView: View {
    let searchText: String
    let category: ClipCategory
    let hotKey: HotKey
    /// 翻译可用：搜索无结果时说明译文也会被搜索
    var searchesTranslations = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: FontSize.callout, weight: .semibold))
            Text(message)
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if isFirstRun {
                HStack(spacing: 3) {
                    ForEach(hotKey.keySymbols, id: \.self) { KeyCap(text: $0, prominent: true) }
                    Text("Open from anywhere", comment: "Shown after the global shortcut key caps in the empty panel")
                        .font(.system(size: FontSize.caption))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isFirstRun: Bool {
        searchText.isEmpty && category == .all
    }

    private var symbolName: String {
        if !searchText.isEmpty { return "magnifyingglass" }
        return category == .favorite ? "star" : "doc.on.clipboard"
    }

    private var title: String {
        if !searchText.isEmpty {
            return String(localized: "No results for “\(searchText)”", comment: "Empty panel: search without results")
        }
        return switch category {
        case .all: String(localized: "No clipboard history yet", comment: "Empty panel title")
        case .favorite: String(localized: "No favorites yet", comment: "Empty panel title")
        case .text: String(localized: "No text items", comment: "Empty panel title for the Text category")
        case .link: String(localized: "No links", comment: "Empty panel title for the Links category")
        case .image: String(localized: "No images", comment: "Empty panel title for the Images category")
        case .file: String(localized: "No files", comment: "Empty panel title for the Files category")
        case .color: String(localized: "No colors", comment: "Empty panel title for the Colors category")
        }
    }

    private var message: String {
        if !searchText.isEmpty {
            return searchesTranslations
                ? String(
                    localized: "Translations of translated items are searched too. Press esc to clear the search.",
                    comment: "Empty panel message when translation is available")
                : String(
                    localized: "Try a different search, or press esc to clear it.",
                    comment: "Empty panel message"
                )
        }
        return switch category {
        case .all:
            String(localized: "Copy any text, image or file and it will show up here.", comment: "Empty panel message")
        case .favorite:
            String(
                localized: "Select an item and press ⌘P to favorite it. Favorites are never removed automatically.",
                comment: "Empty panel message"
            )
        default:
            // 同时照顾键盘与鼠标用户
            String(
                localized: "Press ⇥ or click a tab above to switch categories.",
                comment: "Empty panel message for an empty category"
            )
        }
    }
}
