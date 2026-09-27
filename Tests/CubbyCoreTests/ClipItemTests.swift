import Foundation
import Testing
@testable import CubbyCore

@Suite("ClipItem 标题、便捷访问与不可变更新")
struct ClipItemTests {
    // MARK: - title

    @Test("多行文本取首个非空行并去掉首尾空格")
    func titleUsesFirstNonEmptyLine() {
        let item = Fixtures.text("\n\n   \n  第一行内容  \n第二行")
        #expect(item.title == "第一行内容")
    }

    @Test("CRLF 换行同样按行拆分")
    func titleHandlesCRLF() {
        #expect(Fixtures.text("\r\nfoo\r\nbar").title == "foo")
    }

    @Test("超过 200 字符截断并追加省略号")
    func titleTruncatesLongLine() {
        let long = String(repeating: "长", count: 250)
        let title = Fixtures.text(long).title
        #expect(title == String(repeating: "长", count: 200) + "…")
    }

    @Test("恰好 200 字符不截断")
    func titleKeepsBoundaryLength() {
        let exact = String(repeating: "a", count: 200)
        #expect(Fixtures.text(exact).title == exact)
    }

    @Test("全空白文本标题为空串")
    func titleOfBlankText() {
        #expect(Fixtures.text(" \n\t\n").title.isEmpty)
    }

    @Test("图片标题包含像素尺寸")
    func titleOfImage() {
        #expect(Fixtures.image(name: "a.png", width: 640, height: 480).title == "Image 640×480")
    }

    @Test("单个文件显示文件名")
    func titleOfSingleFile() {
        #expect(Fixtures.files(["/Users/me/Documents/报告.pdf"]).title == "报告.pdf")
    }

    @Test("多个文件显示首个文件名与数量")
    func titleOfMultipleFiles() {
        let item = Fixtures.files(["/tmp/a.txt", "/tmp/b.txt", "/tmp/c.txt"])
        // 测试环境没有编译后的 String Catalog，使用键本身（含全部参数）；应用内英文为「a.txt and 2 more」
        #expect(item.title == "a.txt and 2 more (3 files)")
    }

    @Test("空文件列表显示占位标题")
    func titleOfEmptyFiles() {
        #expect(Fixtures.files([]).title == "Files")
    }

    @Test("MB 级文本只扫描开头即可得到首行")
    func titleOfHugeText() {
        let huge = "首行标题\n" + String(repeating: "正文内容\n", count: 400_000)
        #expect(Fixtures.text(huge).title == "首行标题")
    }

    @Test("超长单行（远超扫描窗口）仍截断为 200 字符加省略号")
    func titleOfHugeSingleLine() {
        let huge = String(repeating: "x", count: 1_000_000)
        #expect(Fixtures.text(huge).title == String(repeating: "x", count: 200) + "…")
    }

    @Test("开头空白超过扫描窗口（4000 字符）时标题为空串")
    func titleIgnoresContentBeyondScanWindow() {
        let text = String(repeating: "\n", count: 4_000) + "藏在后面"
        #expect(Fixtures.text(text).title.isEmpty)
        // 窗口内出现的内容仍可作为标题
        #expect(Fixtures.text(String(repeating: "\n", count: 3_990) + "可见").title == "可见")
    }

    // MARK: - 便捷访问

    @Test("便捷访问器只对对应载荷返回值")
    func payloadAccessors() {
        let text = Fixtures.text("t")
        let image = Fixtures.image(name: "i.png")
        let files = Fixtures.files(["/a"])

        #expect(text.text == "t")
        #expect(text.image == nil)
        #expect(text.filePaths.isEmpty)

        #expect(image.text == nil)
        #expect(image.image?.name == "i.png")
        #expect(image.filePaths.isEmpty)

        #expect(files.text == nil)
        #expect(files.image == nil)
        #expect(files.filePaths == ["/a"])
    }

    @Test("formatsName 默认为 nil")
    func formatsNameDefaultsToNil() {
        let item = ClipItem(
            kind: .text, payload: .text("x"), source: nil, createdAt: Fixtures.baseDate, contentHash: "h")
        #expect(item.formatsName == nil)
    }

    @Test("blobNames 汇总图片与富文本格式文件名")
    func blobNames() {
        #expect(Fixtures.text("plain").blobNames.isEmpty)
        #expect(Fixtures.text("rich", formatsName: "r.formats").blobNames == ["r.formats"])
        #expect(Fixtures.image(name: "i.png").blobNames == ["i.png"])
        #expect(Fixtures.files(["/a"]).blobNames.isEmpty)
        #expect(Fixtures.image(name: "i.png").withFormatsName("f.formats").blobNames == ["i.png", "f.formats"])
    }

    // MARK: - 不可变更新

    @Test("withFavorite 返回新值且不修改原值")
    func withFavoriteIsNonMutating() {
        let original = Fixtures.text("x")
        let favorited = original.withFavorite(true)

        #expect(!original.isFavorite)
        #expect(favorited.isFavorite)
        #expect(favorited.id == original.id)
        #expect(favorited.payload == original.payload)
        #expect(favorited.createdAt == original.createdAt)
        #expect(favorited.contentHash == original.contentHash)
    }

    @Test("touched 刷新时间与来源，不修改原值")
    func touchedIsNonMutating() {
        let oldSource = SourceApp(bundleID: "a", name: "A")
        let newSource = SourceApp(bundleID: "b", name: "B")
        let original = Fixtures.text("x", favorite: true, source: oldSource)
        let later = Fixtures.baseDate.addingTimeInterval(60)

        let touched = original.touched(at: later, source: newSource)

        #expect(original.createdAt == Fixtures.baseDate)
        #expect(original.source == oldSource)
        #expect(touched.createdAt == later)
        #expect(touched.source == newSource)
        #expect(touched.id == original.id)
        #expect(touched.isFavorite)
    }

    @Test("touched 未传来源时保留原来源")
    func touchedKeepsSourceWhenNil() {
        let source = SourceApp(bundleID: "a", name: "A")
        let touched = Fixtures.text("x", source: source).touched(at: Fixtures.baseDate)
        #expect(touched.source == source)
    }

    @Test("withFavorite 与 touched 保留 formatsName")
    func updatesKeepFormatsName() {
        let rich = Fixtures.text("x", formatsName: "a.formats")
        #expect(rich.withFavorite(true).formatsName == "a.formats")
        #expect(rich.touched(at: Fixtures.baseDate.addingTimeInterval(1)).formatsName == "a.formats")
    }

    @Test("withFormatsName 设置或清除格式名，其余字段不变且不修改原值")
    func withFormatsName() {
        let original = Fixtures.text("x", favorite: true, source: SourceApp(bundleID: "a", name: "A"))
        let rich = original.withFormatsName("f.formats")
        let cleared = rich.withFormatsName(nil)

        #expect(original.formatsName == nil)
        #expect(rich.formatsName == "f.formats")
        #expect(cleared.formatsName == nil)
        #expect(cleared == original)
    }

    // MARK: - replacing

    @Test("replacing 沿用旧 id 与收藏，其余字段取新值")
    func replacingKeepsIdentity() {
        let old = Fixtures.text(
            "x", favorite: true, source: SourceApp(bundleID: "old", name: "Old"), formatsName: "old.formats")
        let newSource = SourceApp(bundleID: "new", name: "New")
        let later = Fixtures.baseDate.addingTimeInterval(60)
        let fresh = Fixtures.text("x", source: newSource, at: later, formatsName: "new.formats")

        let merged = fresh.replacing(old)

        #expect(merged.id == old.id)
        #expect(merged.isFavorite)
        #expect(merged.source == newSource)
        #expect(merged.createdAt == later)
        #expect(merged.formatsName == "new.formats")
        #expect(merged.payload == fresh.payload)
        #expect(merged.kind == fresh.kind)
        #expect(merged.contentHash == fresh.contentHash)
    }

    @Test("replacing 新来源为空时沿用旧来源")
    func replacingKeepsOldSourceWhenNil() {
        let source = SourceApp(bundleID: "a", name: "A")
        let merged = Fixtures.text("x").replacing(Fixtures.text("x", source: source))
        #expect(merged.source == source)
    }

    @Test("replacing 以纯文本替换富文本时清除格式名")
    func replacingClearsFormats() {
        let old = Fixtures.text("x", formatsName: "old.formats")
        #expect(Fixtures.text("x").replacing(old).formatsName == nil)
    }

    @Test("replacing 不收藏的旧条目时结果也不收藏，且不修改原值")
    func replacingNonFavorite() {
        let old = Fixtures.text("x")
        let fresh = Fixtures.text("x", favorite: true)
        let merged = fresh.replacing(old)
        #expect(!merged.isFavorite)
        #expect(fresh.isFavorite)
        #expect(fresh.id != old.id)
    }
}
