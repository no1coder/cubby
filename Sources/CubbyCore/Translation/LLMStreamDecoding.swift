import Foundation

/// SSE（text/event-stream）按字节解码：每个 `data:` 行即一个事件的数据。
/// 兼容 OpenAI 的服务每个事件只有一行 data，因此逐行交付，不等空行；注释行（`:` 开头，
/// 如 OpenRouter 的保活）与 event / id / retry 字段忽略。超长的行整行丢弃，避免异常响应占满内存
public struct SSELineDecoder: Sendable {
    /// 单行上限（字节）
    public static let maxLineBytes = 1 << 20

    private var line: [UInt8] = []
    private var isDiscardingLine = false

    public init() {}

    /// 喂入一个字节；一个 data 行完整时返回其内容
    public mutating func consume(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            if !isDiscardingLine {
                line.append(byte)
                if line.count > Self.maxLineBytes {
                    line.removeAll()
                    isDiscardingLine = true
                }
            }
            return nil
        }
        return endLine()
    }

    /// 流结束：交付最后一行（末尾没有换行时）
    public mutating func finish() -> String? {
        endLine()
    }

    private mutating func endLine() -> String? {
        defer {
            line.removeAll(keepingCapacity: true)
            isDiscardingLine = false
        }
        guard !isDiscardingLine else { return nil }
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let prefix = Array("data:".utf8)
        guard line.starts(with: prefix) else { return nil }
        var payload = line.dropFirst(prefix.count)
        if payload.first == UInt8(ascii: " ") { payload = payload.dropFirst() }
        return String(decoding: payload, as: UTF8.self)
    }
}

/// 流式响应中一个事件的含义
public enum ChatStreamEvent: Equatable, Sendable {
    /// 增量文本
    case content(String)
    /// `[DONE]`：正常结束
    case done
    /// 服务端在流中报告的错误
    case failure(TranslationFailure)
    /// 与译文无关（角色、推理内容、用量统计、无法解析的杂讯）
    case ignored

    public static func decode(_ payload: String) -> ChatStreamEvent {
        let trimmed = payload.trimmingCharacters(in: .whitespaces)
        if trimmed == "[DONE]" { return .done }
        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(trimmed.utf8)) else {
            return .ignored
        }
        if let error = chunk.error {
            return .failure(error.code.flatMap(LLMFailureMapping.failure(forStatus:)) ?? .invalidResponse)
        }
        guard let content = chunk.choices?.first?.delta?.content, !content.isEmpty else { return .ignored }
        return .content(content)
    }

    /// 非流式响应（服务忽略 stream: true 时）的完整文本
    public static func completionContent(_ data: Data) -> String? {
        let response = try? JSONDecoder().decode(CompletionResponse.self, from: data)
        return response?.choices.first?.message.content
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        let choices: [Choice]?
        let error: StreamError?
    }

    private struct StreamError: Decodable {
        /// 只采用数字形式的错误码（与 HTTP 状态码同义）；文字错误码视为无法识别
        let code: Int?

        enum CodingKeys: String, CodingKey {
            case code
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try? container.decode(Int.self, forKey: .code)
        }
    }

    private struct CompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }
}

/// HTTP 状态与网络错误到 TranslationFailure 的映射（§3.6「错误映射」）
public enum LLMFailureMapping {
    /// 2xx 返回 nil；401 / 403 → 密钥无效；402 / 429 → 额度或频率受限；其余 → 服务端错误（带状态码）
    public static func failure(forStatus status: Int) -> TranslationFailure? {
        switch status {
        case 200..<300: nil
        case 401, 403: .unauthorized
        case 402, 429: .rateLimited
        default: .server(status: status)
        }
    }

    /// 任意错误 → 交给界面的错误：取消保持为 CancellationError；超时与 URLError → 网络；
    /// TranslationFailure 原样返回；其他未知错误视为返回内容无法识别
    public static func map(_ error: any Error) -> any Error {
        switch error {
        case let failure as TranslationFailure: return failure
        case is CancellationError: return error
        case let urlError as URLError:
            return urlError.code == .cancelled ? CancellationError() : TranslationFailure.network
        case is CaptureDeadline.TimedOut: return TranslationFailure.network
        default: return TranslationFailure.invalidResponse
        }
    }
}
