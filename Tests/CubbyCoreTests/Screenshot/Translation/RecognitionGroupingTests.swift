import CoreGraphics
import Testing
@testable import CubbyCore

@Suite("RecognitionTiling 大选区分片")
struct RecognitionTilingTests {
    @Test("不超过上限：一个分片，负责整张图")
    func singleTile() {
        let tiles = RecognitionTiling.tiles(for: CGSize(width: 1600, height: 1000))
        #expect(
            tiles == [
                RecognitionTile(
                    rect: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                    core: CGRect(x: 0, y: 0, width: 1600, height: 1000))
            ])
    }

    @Test("5K 横图：分片不超过上限、相邻重叠 ≥ 256 像素，core 互不重叠且铺满整张图")
    func largeLandscape() {
        let size = CGSize(width: 5120, height: 2880)
        let tiles = RecognitionTiling.tiles(for: size)
        #expect(tiles.count == 6)
        for tile in tiles {
            #expect(tile.rect.width <= 2560 && tile.rect.height <= 1600)
            #expect(tile.rect.contains(tile.core))
        }
        let area = tiles.reduce(CGFloat(0)) { $0 + $1.core.width * $1.core.height }
        #expect(area == size.width * size.height)
        for (index, tile) in tiles.enumerated() {
            for other in tiles[(index + 1)...] {
                let overlap = tile.core.intersection(other.core)
                #expect(overlap.isNull || overlap.width * overlap.height == 0)
                let shared = tile.rect.intersection(other.rect)
                if !shared.isNull, shared.width > 0, shared.height > 0, tile.rect.minY == other.rect.minY {
                    #expect(shared.width >= RecognitionTiling.minimumOverlap)
                }
            }
        }
    }

    @Test("竖图按竖向上限（宽高互换）分片")
    func portrait() {
        let tiles = RecognitionTiling.tiles(for: CGSize(width: 1500, height: 3000))
        #expect(tiles.count == 2)
        #expect(tiles.allSatisfy { $0.rect.width == 1500 && $0.rect.height == 2560 })
    }
}

@Suite("DocumentLineGrouping 文档识别结果分组")
struct DocumentLineGroupingTests {
    private func line(_ text: String, x: CGFloat = 0, y: CGFloat, width: CGFloat = 100, words: [OCRWord] = [])
        -> OCRLine
    {
        OCRLine(text: text, box: CGRect(x: x, y: y, width: width, height: 20), words: words)
    }

    @Test("单词按中心落在哪一行分给各行，并按从左到右排序")
    func assignsWords() {
        let words = [
            OCRWord(text: "b", box: CGRect(x: 50, y: 30, width: 10, height: 20)),
            OCRWord(text: "a", box: CGRect(x: 10, y: 2, width: 10, height: 16)),
            OCRWord(text: "c", box: CGRect(x: 5, y: 30, width: 10, height: 20)),
        ]
        let lines = DocumentLineGrouping.lines(
            [("a", CGRect(x: 0, y: 0, width: 100, height: 20)), ("c b", CGRect(x: 0, y: 28, width: 100, height: 24))],
            words: words)
        #expect(lines[0].words.map(\.text) == ["a"])
        #expect(lines[1].words.map(\.text) == ["c", "b"])
    }

    @Test("同一行出现在多个容器里时归入行数最少的容器，组保持容器顺序")
    func smallestContainer() {
        let title = line("Title", y: 0)
        let body = [line("First", y: 30), line("Second", y: 60)]
        let groups = DocumentLineGrouping.smallestContainers([[title] + body, [title], body])
        #expect(groups == [[title], body])
    }

    @Test("分片结果换算到整张图坐标，只保留中心落在该分片 core 内的行")
    func tileGroups() {
        let tile = RecognitionTile(
            rect: CGRect(x: 1000, y: 0, width: 1000, height: 500), core: CGRect(x: 1200, y: 0, width: 800, height: 500))
        let groups = DocumentLineGrouping.groups(
            [[line("Left", x: 50, y: 10)], [line("Right", x: 400, y: 10), line("Also", x: 400, y: 40)]], from: tile)
        #expect(groups.count == 1)
        #expect(groups[0].map(\.box.minX) == [1400, 1400])
    }

    @Test("项目符号行另起一组，去掉符号并把行框收窄到正文第一个单词")
    func bullets() {
        let words = [
            OCRWord(text: "\u{2022}", box: CGRect(x: 0, y: 0, width: 8, height: 20)),
            OCRWord(text: "Store", box: CGRect(x: 18, y: 0, width: 40, height: 20)),
        ]
        let groups = DocumentLineGrouping.splittingListItems([
            line("\u{2022} Store in iCloud", y: 0, width: 200, words: words), line("and free up space", x: 18, y: 24),
            line("\u{2022} Optimize", y: 48),
        ])
        #expect(groups.map { $0.map(\.text) } == [["Store in iCloud", "and free up space"], ["Optimize"]])
        #expect(groups[0][0].box.minX == 18)
        #expect(groups[0][0].box.maxX == 200)
        #expect(groups[0][0].words.map(\.text) == ["Store"])
    }

    @Test("编号、日文「・」（可与正文粘连）；没有单词框时按字符比例估计正文起点")
    func numbersAndGlued() {
        let numbered = DocumentLineGrouping.splittingListItems([line("1. Open Cubby", y: 0, width: 130)])
        #expect(numbered[0][0].text == "Open Cubby")
        #expect(abs(numbered[0][0].box.minX - 30) < 0.01)
        let glued = OCRWord(text: "\u{30FB}iCloud", box: CGRect(x: 0, y: 0, width: 70, height: 20))
        let japanese = DocumentLineGrouping.splittingListItems([line("\u{30FB}iCloud", y: 0, width: 70, words: [glued])]
        )
        #expect(japanese[0][0].text == "iCloud")
        #expect(abs(japanese[0][0].box.minX - 10) < 0.01)
    }

    @Test("破折号只在列表里算符号：段落续行以破折号开头时不拆开")
    func dashes() {
        let paragraph = DocumentLineGrouping.splittingListItems([
            line("Store in iCloud", y: 0), line("\u{2014} Keep files", y: 24),
        ])
        #expect(paragraph.count == 1)
        let list = DocumentLineGrouping.splittingListItems([line("- Copy", y: 0), line("- Paste", y: 24)])
        #expect(list.map { $0.map(\.text) } == [["Copy"], ["Paste"]])
        #expect(DocumentLineGrouping.splittingListItems([line("\u{2022}", y: 0)]) == [[line("\u{2022}", y: 0)]])
    }

    @Test("假名检测")
    func kana() {
        #expect(DocumentLineGrouping.containsKana("\u{30B9}\u{30C8}\u{30EC}\u{30FC}\u{30B8}"))
        #expect(DocumentLineGrouping.containsKana("iCloud \u{306B}\u{4FDD}\u{5B58}"))
        #expect(!DocumentLineGrouping.containsKana("\u{50A8}\u{5B58}\u{7A7A}\u{95F4}"))
    }
}

@Suite("ColumnAlignment 单行块按同列推断对齐")
struct ColumnAlignmentTests {
    private func cell(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> [RecognizedLine] {
        [RecognizedLine(text: text, frame: CGRect(x: x, y: y, width: width, height: 14))]
    }

    @Test("右缘齐、左缘不齐的一列数值 → trailing；左缘齐的标签 → leading")
    func tableColumns() {
        let blocks = TextBlockBuilder.blocks(from: [
            cell("Documents", x: 20, y: 10, width: 70), cell("12.4 GB", x: 200, y: 10, width: 50),
            cell("Photos", x: 20, y: 40, width: 45), cell("1,284", x: 215, y: 40, width: 35),
            cell("Trash", x: 20, y: 70, width: 40), cell("Yesterday", x: 185, y: 70, width: 65),
        ])
        #expect(blocks.map(\.alignment) == [.leading, .trailing, .leading, .trailing, .leading, .trailing])
    }

    @Test("只有一个相邻块碰巧右缘齐时不采信；上下相隔太远的不算相邻")
    func singleCoincidence() {
        let blocks = TextBlockBuilder.blocks(from: [
            cell("Send me news", x: 20, y: 10, width: 120), cell("Cancel", x: 95, y: 40, width: 45),
            cell("Far below", x: 60, y: 400, width: 80),
        ])
        #expect(blocks.allSatisfy { $0.alignment == .leading })
    }

    @Test("中线齐的一串（标题、副标题、按钮、链接）→ center")
    func centeredStack() {
        let blocks = TextBlockBuilder.blocks(from: [
            cell("Welcome", x: 150, y: 10, width: 100), cell("A tidy clipboard", x: 110, y: 40, width: 180),
            cell("Get Started", x: 160, y: 80, width: 80), cell("Not Now", x: 172, y: 110, width: 56),
        ])
        #expect(blocks.allSatisfy { $0.alignment == .center })
    }
}

@Suite("KanaReplacement 假名补识别只针对该段区域")
struct KanaReplacementTests {
    private let kana = "\u{30B9}\u{30C8}\u{30EC}\u{30FC}\u{30B8}"

    private func line(_ text: String, x: CGFloat = 0, y: CGFloat, width: CGFloat = 100) -> OCRLine {
        OCRLine(text: text, box: CGRect(x: x, y: y, width: width, height: 20))
    }

    @Test("搜索区域 = 含假名各组外扩半行高的并集，与图像相交；没有假名时为 nil")
    func searchArea() {
        let groups = [[line("English", y: 0)], [line(kana, x: 50, y: 100)], [line(kana, x: 300, y: 300)]]
        let area = KanaReplacement.searchArea(for: groups, imageSize: CGSize(width: 390, height: 1000))
        #expect(area == CGRect(x: 40, y: 90, width: 350, height: 240))
        #expect(
            KanaReplacement.searchArea(for: [[line("English", y: 0)]], imageSize: CGSize(width: 500, height: 500))
                == nil)
    }

    @Test("相距不到半行高的两组：每条补识别的行只归入重叠最多的那一组，不会重复")
    func uniqueAssignment() {
        let upper = [line(kana, y: 0)]
        let lower = [line(kana, y: 26)]
        let english = [line("Keep", y: 60)]
        let japanese = [line("A", y: 1), line("B", y: 25), line("stray", y: 500)]
        let result = KanaReplacement.replacing([upper, lower, english], with: japanese)
        #expect(result.map { $0.map(\.text) } == [["A"], ["B"], ["Keep"]])
    }

    @Test("区域内没有补识别结果的组保留原行；替换后的行按从上到下排序")
    func keepsWhenEmpty() {
        let group = [line(kana, y: 0), line(kana, y: 22)]
        #expect(KanaReplacement.replacing([group], with: []) == [group])
        let replaced = KanaReplacement.replacing([group], with: [line("second", y: 22), line("first", y: 0)])
        #expect(replaced == [[line("first", y: 0), line("second", y: 22)]])
    }

    @Test("落在两组区域的空隙里（与两组外框都不重叠）时归入中心更近的组；距离相同取前一组")
    func tieBreaks() {
        let upper = [line(kana, y: 0)]
        let lower = [line(kana, y: 30)]
        let nearUpper = OCRLine(text: "near", box: CGRect(x: 0, y: 20.5, width: 100, height: 2))
        let middle = OCRLine(text: "middle", box: CGRect(x: 0, y: 24, width: 100, height: 2))
        let result = KanaReplacement.replacing([upper, lower], with: [nearUpper, middle])
        #expect(result.map { $0.map(\.text) } == [["near", "middle"], [kana]])
    }
}
