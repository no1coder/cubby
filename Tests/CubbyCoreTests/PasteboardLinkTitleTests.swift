import AppKit
import Testing
@testable import CubbyCore

/// 读取浏览器随链接一起写上剪贴板的网页标题（public.url-name / WebURLsWithTitlesPboardType）。
/// 只用独立命名的剪贴板，不碰系统剪贴板
@Suite("PasteboardReader 读取链接标题", .serializedPasteboardAccess, .timeLimit(.minutes(1)))
struct PasteboardLinkTitleTests {
    private static let url = "https://example.com/docs/intro"
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")
    private static let webURLsWithTitles = NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")

    /// 按浏览器的写法写入：纯文本 + 可选的 public.url / 标题 / 标题列表 / HTML。
    /// 用剪贴板级的 declareTypes 写入（与老应用相同）：WebURLsWithTitlesPboardType 不是合法 UTI，
    /// NSPasteboardItem 会拒绝写入，剪贴板级接口则会把它映射为 dyn. 类型，读取时按原名即可取回
    private func write(
        _ pasteboard: NSPasteboard,
        text: String = url,
        url: String? = url,
        urlName: String? = nil,
        titles: Any? = nil,
        html: String? = nil
    ) {
        let types: [NSPasteboard.PasteboardType?] = [
            .string, url.map { _ in .URL }, urlName.map { _ in Self.urlName },
            titles.map { _ in Self.webURLsWithTitles }, html.map { _ in .html },
        ]
        pasteboard.declareTypes(types.compactMap(\.self), owner: nil)
        #expect(pasteboard.setString(text, forType: .string))
        if let url { #expect(pasteboard.setString(url, forType: .URL)) }
        if let urlName { #expect(pasteboard.setString(urlName, forType: Self.urlName)) }
        if let titles { #expect(pasteboard.setPropertyList(titles, forType: Self.webURLsWithTitles)) }
        if let html { #expect(pasteboard.setData(Data(html.utf8), forType: .html)) }
    }

    @Test("Safari 的写法：public.url-name 作为标题，规范化后随内容交出")
    func readsURLName() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, urlName: "  Intro —\n Example  Docs ")
            #expect(
                PasteboardReader.capture(from: pasteboard)
                    == .content(.text(Self.url), linkTitle: "Intro — Example Docs"))
        }
    }

    @Test("WebURLsWithTitlesPboardType：取链接匹配的标题")
    func readsWebURLsWithTitles() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, titles: [["https://other.com", Self.url], ["Other", "Intro"]])
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url), linkTitle: "Intro"))
        }
    }

    @Test("两者都有时优先 public.url-name")
    func prefersURLName() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, urlName: "From name", titles: [[Self.url], ["From list"]])
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url), linkTitle: "From name"))
        }
    }

    @Test("url-name 只是链接本身时退到标题列表；都没有可用标题时为 nil")
    func uselessURLNameFallsBack() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, urlName: "example.com/docs/intro/", titles: [[Self.url], ["From list"]])
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url), linkTitle: "From list"))
            pasteboard.clearContents()
            write(pasteboard, urlName: Self.url)
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url)))
        }
    }

    @Test("文本链接带首尾空白时照样识别为链接并读取标题")
    func linkTextWithWhitespace() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, text: " \(Self.url)\n", urlName: "Intro")
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(" \(Self.url)\n"), linkTitle: "Intro"))
        }
    }

    @Test("没有 public.url 时也接受 url-name")
    func urlNameWithoutURLType() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, url: nil, urlName: "Intro")
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url), linkTitle: "Intro"))
        }
    }

    @Test("public.url 指向别的链接时，url-name 不属于这段文本，不采用")
    func mismatchedURLTypeIgnoresURLName() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, url: "https://other.com/page", urlName: "Other page")
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url)))
        }
    }

    @Test("文本不是链接时不读取标题", arguments: ["hello world", "#FF8800", "ftp://example.com/a"])
    func nonLinkTextHasNoTitle(text: String) {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, text: text, url: nil, urlName: "Title", titles: [[text], ["Title"]])
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(text)))
        }
    }

    @Test("带 HTML 的链接：富文本内容同样带上标题")
    func richTextLinkKeepsTitle() {
        let html = "<a href=\"\(Self.url)\">Intro</a>"
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, urlName: "Intro", html: html)
            let expected = PasteboardCapture.content(
                .richText(Self.url, formats: ["public.html": Data(html.utf8)]), linkTitle: "Intro")
            #expect(PasteboardReader.capture(from: pasteboard) == expected)
        }
    }

    @Test("标题列表结构损坏时忽略，不影响内容")
    func malformedTitleListIsIgnored() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, titles: ["not", "lists"])
            #expect(PasteboardReader.capture(from: pasteboard) == .content(.text(Self.url)))
        }
    }

    @Test("同步读取 read(from:) 只返回内容（标题只走剪贴板监听的记录路径）")
    func readReturnsContentOnly() {
        withTemporaryPasteboard { pasteboard in
            write(pasteboard, urlName: "Intro")
            #expect(PasteboardReader.read(from: pasteboard) == .text(Self.url))
        }
    }
}
