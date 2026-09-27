import Foundation
import Testing
@testable import CubbyCore

@Suite("JSON Lines 译文解析")
struct TranslationLineParserTests {
    private let blocks = makeBlocks(["File", "Edit", "View"])

    private func parse(_ fragments: [String], blocks: [TextBlock]? = nil) -> [BlockTranslation] {
        var parser = TranslationLineParser(blocks: blocks ?? self.blocks)
        return fragments.flatMap { parser.consume($0) } + parser.finish()
    }

    @Test("逐字符到达也能在换行时交付完整的行")
    func characterByCharacter() {
        let output = #"{"id":0,"text":"文件"}"# + "\n" + #"{"id":1,"text":"编辑"}"# + "\n"
        var parser = TranslationLineParser(blocks: blocks)
        var delivered: [[BlockTranslation]] = []
        for character in output {
            delivered.append(parser.consume(String(character)))
        }
        #expect(delivered.flatMap { $0 }.map(\.text) == ["文件", "编辑"])
        // 第一行在它的换行到达时立即交付，不等流结束
        #expect(delivered.firstIndex { !$0.isEmpty } == #"{"id":0,"text":"文件"}"#.count)
        #expect(parser.deliveredCount == 2)
    }

    @Test("最后一行没有换行时在结束时交付")
    func lastLineWithoutNewline() {
        #expect(parse([#"{"id":2,"text":"视图"}"#]).map(\.blockID) == [2])
    }

    @Test("CRLF 与空白行")
    func crlf() {
        let output = "\r\n" + #"{"id":0,"text":"文件"}"# + "\r\n\r\n" + #"  {"id":1,"text":"编辑"}  "# + "\r\n"
        #expect(parse([output]).map(\.text) == ["文件", "编辑"])
    }

    @Test("代码块围栏与前后杂讯被跳过")
    func fencesAndNoise() {
        let output = "Here you go:\n```jsonl\n" + #"{"id":0,"text":"文件"}"# + "\n```\nDone!"
        #expect(parse([output]).map(\.text) == ["文件"])
    }

    @Test("JSON 数组：整行或每行一个元素")
    func arrays() {
        let single = #"[{"id":0,"text":"文件"},{"id":1,"text":"编辑"}]"#
        #expect(parse([single]).map(\.blockID) == [0, 1])

        let perLine = "[\n" + #"  {"id":0,"text":"文件"},"# + "\n" + #"  {"id":1,"text":"编辑"}"# + "\n]"
        #expect(parse([perLine]).map(\.blockID) == [0, 1])
    }

    @Test("数组中无效的项跳过，其余照常")
    func arrayWithInvalidItem() {
        let line = #"[{"id":0,"text":"文件"},{"id":"x","text":"坏"},{"id":2}]"#
        #expect(parse([line]).map(\.blockID) == [0])
    }

    @Test("跨多行排版的对象")
    func prettyPrinted() {
        let output = "{\n  \"id\": 1,\n  \"text\": \"编辑 {草稿}\"\n}\n" + #"{"id":2,"text":"视图"}"# + "\n"
        #expect(
            parse([output]) == [
                BlockTranslation(blockID: 1, text: "编辑 {草稿}"), BlockTranslation(blockID: 2, text: "视图"),
            ])
    }

    @Test("跨行对象的最后一行没有换行时在结束时闭合；始终未闭合的丢弃")
    func pendingAtFinish() {
        // 右花括号在字符串里不算闭合，最后一行（无换行）带来真正的闭合
        #expect(parse(["{\"id\": 0,\n\"text\": \"a}\"", "}"]).map(\.blockID) == [0])
        #expect(parse(["{\"id\": 1,\n\"text\": \"b\""]).isEmpty)
    }

    @Test("杂讯里的左花括号不会吞掉后面的完整行")
    func strayBraceDoesNotSwallow() {
        let output = "{ note: the following\n" + #"{"id":0,"text":"文件"}"# + "\n" + #"{"id":1,"text":"编辑"}"# + "\n"
        #expect(parse([output]).map(\.blockID) == [0, 1])
    }

    @Test("攒行超过上限后丢弃")
    func pendingOverflow() {
        let noise = "{\n" + String(repeating: "noise\n", count: TranslationLineParser.maxPendingLines + 2)
        #expect(parse([noise + #"{"id":0,"text":"文件"}"# + "\n"]).map(\.blockID) == [0])
    }

    @Test("<think> 推理段整段忽略（可跨行）")
    func thinking() {
        let output = "<think>用户想要 {\"id\":0,\"text\":\"错\"}\n继续思考</think>\n" + #"{"id":0,"text":"文件"}"# + "\n"
        #expect(parse([output]).map(\.text) == ["文件"])
        let inline = #"<think>x</think>{"id":1,"text":"编辑"}"# + "\n"
        #expect(parse([inline]).map(\.text) == ["编辑"])
    }

    @Test("id 可写成数字字符串；未知、重复、非数字 id 被忽略")
    func ids() {
        let output = [
            #"{"id":"0","text":"文件"}"#, #"{"id":0,"text":"重复"}"#, #"{"id":9,"text":"未知"}"#,
            #"{"id":"one","text":"坏"}"#, #"{"id":1}"#, #"{"id":1,"text":"编辑"}"#,
        ].joined(separator: "\n")
        #expect(
            parse([output]) == [BlockTranslation(blockID: 0, text: "文件"), BlockTranslation(blockID: 1, text: "编辑")])
    }

    @Test("控制字符与双向覆盖字符被去掉，换行与制表符变为空格，空译文不交付")
    func sanitizes() {
        let output = [
            #"{"id":0,"text":"文\u0007件‮"}"#, #"{"id":1,"text":"第一行\n第二行\t尾"}"#, #"{"id":2,"text":" \u0000 "}"#,
        ].joined(separator: "\n")
        #expect(
            parse([output]) == [
                BlockTranslation(blockID: 0, text: "文件"), BlockTranslation(blockID: 1, text: "第一行 第二行 尾"),
            ])
    }

    @Test("行 / 段分隔符变为空格，零宽与其他格式字符被去掉")
    func sanitizesSeparatorsAndFormatCharacters() {
        let text = "a\u{2028}b\u{2029}c\u{200B}d\u{FEFF}e\u{200D}f\u{00AD}g\u{2060}h"
        #expect(TranslationLineParser.sanitize(text, limit: 100) == "a b cdefgh")
    }

    @Test("长度上限按 Unicode 标量计算：叠加的组合符号无法绕过")
    func lengthCapCountsScalars() {
        let stacked = "e" + String(repeating: "\u{0301}", count: 5000)
        #expect(stacked.count == 1)
        let result = TranslationLineParser.sanitize(stacked, limit: 208)
        #expect(result.unicodeScalars.count == 208)

        let blocks = makeBlocks(["e" + String(repeating: "\u{0301}", count: 9)])
        let output = #"{"id":0,"text":"\#(stacked)"}"#
        #expect(parse([output], blocks: blocks).first?.text.unicodeScalars.count == 4 * 10 + 200)
    }

    @Test("一次到达大量行时按线性时间处理")
    func manyLinesInOneFragment() {
        let noise = String(repeating: "noise line that is not json\n", count: 20000)
        let started = ContinuousClock.now
        let result = parse([noise + #"{"id":0,"text":"文件"}"# + "\n"])
        #expect(result.map(\.blockID) == [0])
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("跨行对象逐行累积深度：很长的多行对象也能解析")
    func longPrettyPrinted() {
        let text = String(repeating: "长", count: 20000)
        let output = "{\n\"id\": 0,\n\"text\": \"\(text)\"\n}\n"
        let blocks = makeBlocks([String(repeating: "x", count: 20000)])
        #expect(parse([output], blocks: blocks).first?.text.count == 20000)
    }

    @Test("译文长度上限 4 × 原文 + 200")
    func lengthCap() {
        let blocks = makeBlocks(["Hi"])
        let long = String(repeating: "长", count: 1000)
        let result = parse([#"{"id":0,"text":"\#(long)"}"#], blocks: blocks)
        #expect(result.first?.text.count == 4 * 2 + 200)
    }

    @Test("超长的未换行缓冲被丢弃")
    func bufferOverflow() {
        var parser = TranslationLineParser(blocks: blocks)
        _ = parser.consume(String(repeating: "x", count: TranslationLineParser.maxBufferBytes + 1))
        #expect(parser.consume("\n" + #"{"id":0,"text":"文件"}"# + "\n").map(\.blockID) == [0])
    }

    @Test("花括号深度忽略字符串内的括号与转义引号")
    func braceDepth() {
        #expect(TranslationLineParser.braceDepth(#"{"a":"}\"{"}"#) == 0)
        #expect(TranslationLineParser.braceDepth(#"{"a":{"#) == 2)
    }
}

@Suite("SSE 与流事件解码")
struct LLMStreamDecodingTests {
    private func decode(_ text: String) -> [String] {
        var decoder = SSELineDecoder()
        var payloads = Array(text.utf8).compactMap { decoder.consume($0) }
        if let last = decoder.finish() { payloads.append(last) }
        return payloads
    }

    @Test("data 行逐行交付；有无空格、CRLF 均可；注释与其他字段忽略")
    func dataLines() {
        let text = ": comment\nevent: message\nid: 7\nretry: 100\ndata: {\"a\":1}\r\n\ndata:[DONE]\n"
        #expect(decode(text) == [#"{"a":1}"#, "[DONE]"])
    }

    @Test("最后一行没有换行时在结束时交付；多字节字符不被切坏")
    func finishAndUTF8() {
        #expect(decode("data: 你好") == ["你好"])
    }

    @Test("超长行整行丢弃，下一行照常")
    func overlongLine() {
        var decoder = SSELineDecoder()
        let long = Array(("data: " + String(repeating: "x", count: SSELineDecoder.maxLineBytes + 10)).utf8)
        #expect(long.compactMap { decoder.consume($0) }.isEmpty)
        #expect(decoder.consume(UInt8(ascii: "\n")) == nil)
        #expect(Array("data: ok\n".utf8).compactMap { decoder.consume($0) } == ["ok"])
    }

    @Test("流事件：增量文本、结束、忽略项")
    func events() {
        #expect(ChatStreamEvent.decode(" [DONE] ") == .done)
        #expect(ChatStreamEvent.decode(#"{"choices":[{"delta":{"content":"hi"}}]}"#) == .content("hi"))
        #expect(ChatStreamEvent.decode(#"{"choices":[{"delta":{"content":""}}]}"#) == .ignored)
        #expect(ChatStreamEvent.decode(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == .ignored)
        #expect(ChatStreamEvent.decode(#"{"choices":[{"delta":{"reasoning_content":"think"}}]}"#) == .ignored)
        #expect(ChatStreamEvent.decode(#"{"choices":[],"usage":{"total_tokens":3}}"#) == .ignored)
        #expect(ChatStreamEvent.decode("not json") == .ignored)
    }

    @Test("流中的错误：数字错误码按状态码映射，其他视为无法识别")
    func errorEvents() {
        #expect(ChatStreamEvent.decode(#"{"error":{"code":401,"message":"bad key"}}"#) == .failure(.unauthorized))
        #expect(ChatStreamEvent.decode(#"{"error":{"code":502}}"#) == .failure(.server(status: 502)))
        #expect(ChatStreamEvent.decode(#"{"error":{"code":"rate_limit"}}"#) == .failure(.invalidResponse))
        #expect(ChatStreamEvent.decode(#"{"error":{}}"#) == .failure(.invalidResponse))
    }

    @Test("非流式响应的完整文本")
    func completionContent() {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"x"}}]}"#.utf8)
        #expect(ChatStreamEvent.completionContent(data) == "x")
        #expect(ChatStreamEvent.completionContent(Data("{}".utf8)) == nil)
    }

    @Test("错误映射：取消、超时、网络、未知")
    func failureMapping() {
        #expect(LLMFailureMapping.failure(forStatus: 204) == nil)
        #expect(LLMFailureMapping.failure(forStatus: 307) == .server(status: 307))
        #expect(LLMFailureMapping.map(TranslationFailure.rateLimited) as? TranslationFailure == .rateLimited)
        #expect(LLMFailureMapping.map(CancellationError()) is CancellationError)
        #expect(LLMFailureMapping.map(URLError(.cancelled)) is CancellationError)
        #expect(LLMFailureMapping.map(URLError(.secureConnectionFailed)) as? TranslationFailure == .network)
        #expect(LLMFailureMapping.map(CaptureDeadline.TimedOut()) as? TranslationFailure == .network)
        #expect(LLMFailureMapping.map(CocoaError(.coderReadCorrupt)) as? TranslationFailure == .invalidResponse)
    }
}
