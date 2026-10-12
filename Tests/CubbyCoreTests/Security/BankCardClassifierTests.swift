import Foundation
import Testing
@testable import CubbyCore

@Suite("敏感内容识别：银行卡号")
struct BankCardClassifierTests {
    @Test(
        "13–19 位、Luhn 通过；值只保留数字",
        arguments: [
            ("4111 1111 1111 1111", "4111111111111111"),
            ("4111-1111-1111-1111", "4111111111111111"),
            ("5555555555554444", "5555555555554444"),
            ("6222 0212 3456 7890 128", "6222021234567890128"),
            ("378282246310005", "378282246310005"),
            ("3782 822463 10005", "378282246310005"),
            ("4222222222222", "4222222222222"),
            ("  4111111111111111\n", "4111111111111111"),
        ])
    func valid(text: String, digits: String) {
        #expect(SensitiveTextClassifier.classify(text) == SensitiveValue(kind: .bankCard, value: digits))
    }

    @Test(
        "Luhn 不通过、位数不对、含字母或分隔符不规范时不算",
        arguments: [
            "4111111111111112",  // Luhn 失败
            "411111111117",  // 12 位（Luhn 通过）
            "41111111111111111115",  // 20 位（Luhn 通过）
            "4111 1111 1111 111a",
            "4111 1111-1111 1111",  // 空格与连字符混用
            "4111  1111 1111 1111",  // 连续两个空格
            "4111--1111-1111-1111",
            " -4111111111111111",
            "4111111111111111-",
            "+4111111111111111",
            "4111.1111.1111.1111",
            "\u{FF14}111111111111111",  // 全角数字
            "\u{0664}111111111111111",  // 阿拉伯-印度数字
        ])
    func invalid(text: String) {
        #expect(SensitiveTextClassifier.classify(text, kinds: [.bankCard]) == nil)
    }

    @Test(
        "各卡组织的号段与长度",
        arguments: [
            "4222222222222",  // Visa 13
            "5555555555554444",  // Mastercard 51–55
            "2221000000000009",  // Mastercard 2221–2720
            "378282246310005",  // Amex
            "622202123456789012",  // 银联 18 位（日期部分不是有效日期）
            "6011111111111117",  // Discover
            "3530111333300000",  // JCB
            "30569309025904",  // Diners 14
        ])
    func networks(number: String) {
        #expect(SensitiveTextClassifier.classify(number, kinds: [.bankCard])?.value == number)
    }

    @Test(
        "Luhn 通过但不是银行卡：号段或长度不对、像身份证号",
        arguments: [
            "490154203237518",  // IMEI（15 位，4 开头但 Visa 没有 15 位）
            "1700000000004",  // 13 位毫秒时间戳
            "620102199001010000",  // 像身份证号：地区码 + 1990-01-01
            "41111111111114",  // Visa 14 位
            "5555555555554444000",  // Mastercard 19 位（Luhn 未必通过，号段长度也不对）
            "9111111111111111",  // 9 开头
            "34000000000000009",  // Amex 17 位
        ])
    func notCards(number: String) {
        #expect(SensitiveTextClassifier.classify(number, kinds: [.bankCard]) == nil)
    }

    @Test("身份证号的判断：日期必须有效、首位 1–8、正好 18 位")
    func chineseIDShape() {
        #expect(BankCard.looksLikeChineseID("620102199001010000"))
        #expect(BankCard.looksLikeChineseID("110101200002290000"))  // 2000 年是闰年
        #expect(!BankCard.looksLikeChineseID("110101190002290000"))  // 1900 年不是闰年
        #expect(!BankCard.looksLikeChineseID("110101199002300000"))
        #expect(!BankCard.looksLikeChineseID("110101199004310000"))
        #expect(!BankCard.looksLikeChineseID("110101199013010000"))
        #expect(!BankCard.looksLikeChineseID("110101180001010000"))
        #expect(!BankCard.looksLikeChineseID("910101199001010000"))
        #expect(!BankCard.looksLikeChineseID("62010219900101000"))
    }

    @Test("关闭银行卡类型时不识别")
    func disabled() {
        #expect(SensitiveTextClassifier.classify("4111111111111111", kinds: [.bitcoin, .solana]) == nil)
    }
}
