import CoreGraphics
import CubbyCore
import Foundation
import Vision

/// macOS 26 的 Vision 文档识别（RecognizeDocumentsRequest，minimumTextHeightFraction = 0，语言自动检测）
@available(macOS 26, *)
enum DocumentTextReader {
    /// 假名补识别的语言（§3.1：日文优先）
    private static let kanaLanguages = ["ja-JP", "en-US"]

    /// 选区内的行，按最小容器分组（全局点）；没有文字或选区为空时为空数组
    static func lineGroups(in frame: FrozenFrame, selection: CGRect) async throws -> [[RecognizedLine]] {
        guard let canvas = RecognitionCanvas(frame: frame, selection: selection) else { return [] }
        var groups = try await recognize(canvas.image, languages: nil)
        let size = CGSize(width: canvas.image.width, height: canvas.image.height)
        if let area = KanaReplacement.searchArea(for: groups, imageSize: size),
            let crop = canvas.image.cropping(to: area)
        {
            // 只以日文优先重识别含假名的那些段落所在的区域（裁剪图坐标 → 选区裁剪图坐标）
            let japanese = try await recognize(crop, languages: kanaLanguages).flatMap { $0 }.map {
                $0.offsetBy(dx: area.minX, dy: area.minY)
            }
            groups = KanaReplacement.replacing(groups, with: japanese)
        }
        return groups.flatMap(DocumentLineGrouping.splittingListItems).map { group in
            group.map { RecognizedLine(text: $0.text, frame: canvas.globalRect($0.box)) }
        }
    }

    /// 整张图（必要时分片）识别，返回按最小容器分组的行（裁剪图像素坐标）
    private static func recognize(_ image: CGImage, languages: [String]?) async throws -> [[OCRLine]] {
        var groups: [[OCRLine]] = []
        for tile in RecognitionTiling.tiles(for: CGSize(width: image.width, height: image.height)) {
            try Task.checkCancellation()
            guard let piece = image.cropping(to: tile.rect) else { continue }
            let containers = try await containers(in: piece, languages: languages)
            groups += DocumentLineGrouping.groups(containers, from: tile)
        }
        return groups
    }

    /// 一张图里的全部文字容器：标题、段落、列表项、表格单元格（互相可能包含同一行）
    private static func containers(in image: CGImage, languages: [String]?) async throws -> [[OCRLine]] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.minimumTextHeightFraction = 0
        if let languages {
            request.textRecognitionOptions.automaticallyDetectLanguage = false
            request.textRecognitionOptions.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
        } else {
            request.textRecognitionOptions.automaticallyDetectLanguage = true
        }
        let size = CGSize(width: image.width, height: image.height)
        return try await request.perform(on: image).flatMap { observation in
            texts(of: observation.document).map { lines(of: $0, size: size) }
        }
    }

    private static func texts(of document: DocumentObservation.Container) -> [DocumentObservation.Container.Text] {
        func contents(_ container: DocumentObservation.Container) -> [DocumentObservation.Container.Text] {
            container.paragraphs.isEmpty ? [container.text] : container.paragraphs
        }
        let items = document.lists.flatMap(\.items).flatMap { contents($0.content) }
        let cells = document.tables.flatMap(\.rows).flatMap { $0 }.flatMap { contents($0.content) }
        return [document.title].compactMap { $0 } + document.paragraphs + items + cells
    }

    private static func lines(of text: DocumentObservation.Container.Text, size: CGSize) -> [OCRLine] {
        let words = (text.words ?? []).map {
            OCRWord(text: $0.transcript, box: $0.boundingBox.toImageCoordinates(size, origin: .upperLeft))
        }
        let lines = text.lines.map { ($0.transcript, $0.boundingBox.toImageCoordinates(size, origin: .upperLeft)) }
        return DocumentLineGrouping.lines(lines, words: words)
    }
}
