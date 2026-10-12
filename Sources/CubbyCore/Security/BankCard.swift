import Foundation

/// 银行卡号识别：13–19 位 ASCII 数字，Luhn 校验通过，且号段与长度属于某个卡组织（见 matchesNetwork）。
/// 像身份证号的 18 位数字不算（6 位地区码 + 19xx / 20xx 年的有效日期）。
/// 允许用单个空格或单个连字符把数字分组（组长不限，兼容 4-4-4-4、4-6-5 等写法），
/// 但整串只能用同一种分隔符：「4111 1111-1111 1111」这种混用更像随手拼的数字，不算
enum BankCard {
    static let digitCounts = 13...19

    /// 是银行卡号时返回去掉分隔符的数字串
    static func digits(_ text: String) -> String? {
        let bytes = Array(text.utf8)
        let separators = Set(bytes.filter { !isDigit($0) })
        guard separators.count <= 1 else { return nil }
        if let separator = separators.first {
            guard separator == UInt8(ascii: " ") || separator == UInt8(ascii: "-") else { return nil }
            // 每组至少一个数字：不能在开头、结尾或连续出现
            let groups = bytes.split(separator: separator, omittingEmptySubsequences: false)
            guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }
        }
        let digits = bytes.filter(isDigit)
        guard digitCounts.contains(digits.count), passesLuhn(digits) else { return nil }
        let number = String(decoding: digits, as: UTF8.self)
        guard matchesNetwork(number), !looksLikeChineseID(number) else { return nil }
        return number
    }

    /// 卡组织的号段与长度：IMEI、13 位毫秒时间戳、订单号等碰巧 Luhn 通过的数字因此不算。
    /// Visa 4（13 / 16 / 19）；Mastercard 51–55、2221–2720（16）；Amex 34 / 37（15）；银联 62（16–19）；
    /// Discover 6011、644–649、65（16–19）；JCB 3528–3589（16–19）；Diners 300–305、36、38、39（14–19）
    static func matchesNetwork(_ number: String) -> Bool {
        let length = number.count
        let prefix = { (count: Int) in Int(number.prefix(count)) ?? -1 }
        if number.hasPrefix("4") { return [13, 16, 19].contains(length) }
        if (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) { return length == 16 }
        if [34, 37].contains(prefix(2)) { return length == 15 }
        let long = 16...19
        if prefix(2) == 62 { return long.contains(length) }
        if prefix(4) == 6011 || (644...649).contains(prefix(3)) || prefix(2) == 65 { return long.contains(length) }
        if (3528...3589).contains(prefix(4)) { return long.contains(length) }
        if (300...305).contains(prefix(3)) || [36, 38, 39].contains(prefix(2)) { return (14...19).contains(length) }
        return false
    }

    private static let chineseIDLength = 18
    private static let chineseIDYears = 1900...2099

    /// 18 位数字、前 6 位像地区码（首位 1–8）、接着是 19xx / 20xx 年的有效日期：更像身份证号
    static func looksLikeChineseID(_ number: String) -> Bool {
        let digits = Array(number)
        guard digits.count == chineseIDLength, let first = digits.first, ("1"..."8").contains(first),
            let year = Int(String(digits[6..<10])), let month = Int(String(digits[10..<12])),
            let day = Int(String(digits[12..<14])), chineseIDYears.contains(year), (1...12).contains(month)
        else { return false }
        return (1...daysIn(month: month, year: year)).contains(day)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) || year.isMultiple(of: 400) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// Luhn：从右往左，偶数位乘 2（超过 9 减 9），总和是 10 的倍数
    static func passesLuhn(_ digits: [UInt8]) -> Bool {
        let sum = digits.reversed().enumerated().reduce(0) { total, element in
            let digit = Int(element.element - UInt8(ascii: "0"))
            guard element.offset.isMultiple(of: 2) else {
                let doubled = digit * 2
                return total + (doubled > 9 ? doubled - 9 : doubled)
            }
            return total + digit
        }
        return sum.isMultiple(of: 10)
    }
}
