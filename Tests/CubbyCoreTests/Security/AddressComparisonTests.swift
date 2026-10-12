import Foundation
import Testing
@testable import CubbyCore

@Suite("地址逐位比对与分组显示")
struct AddressComparisonTests {
    @Test("完全相同时没有不同区段")
    func identical() {
        #expect(AddressComparison.differingRanges(original: "abcdef", replaced: "abcdef").isEmpty)
        #expect(AddressComparison.differingCount(original: "abcdef", replaced: "abcdef") == 0)
        #expect(AddressComparison.differingRanges(original: "", replaced: "").isEmpty)
    }

    @Test("相邻的不同字符合并为一个区段")
    func mergesAdjacent() {
        let ranges = AddressComparison.differingRanges(original: "abcdefgh", replaced: "aXYdeZgW")
        #expect(ranges == [1..<3, 5..<6, 7..<8])
        #expect(AddressComparison.differingCount(original: "abcdefgh", replaced: "aXYdeZgW") == 4)
    }

    @Test("首尾相同、中间全不同")
    func middleDiffers() {
        let ranges = AddressComparison.differingRanges(original: "0x1234abcd5678", replaced: "0x1234ffff5678")
        #expect(ranges == [6..<10])
    }

    @Test("replaced 更长时多出的部分算不同，并与前面的不同区段合并")
    func longerReplaced() {
        #expect(AddressComparison.differingRanges(original: "abc", replaced: "abcde") == [3..<5])
        #expect(AddressComparison.differingRanges(original: "abc", replaced: "abXde") == [2..<5])
        #expect(AddressComparison.differingRanges(original: "", replaced: "ab") == [0..<2])
    }

    @Test("replaced 更短时只比较它自己的字符")
    func shorterReplaced() {
        #expect(AddressComparison.differingRanges(original: "abcde", replaced: "abc").isEmpty)
        #expect(AddressComparison.differingRanges(original: "abcde", replaced: "Xbc") == [0..<1])
    }

    @Test("按字符（不是 UTF-16）比较")
    func comparesCharacters() {
        #expect(AddressComparison.differingRanges(original: "a\u{1F600}c", replaced: "a\u{1F601}c") == [1..<2])
    }

    @Test("首尾各 4 位相同且整串不同")
    func sharesEnds() {
        #expect(AddressComparison.sharesEnds(original: "0x7a3F11119c21", replaced: "0x7a2222229c21"))
        #expect(AddressComparison.sharesEnds(original: "abcdwxyz", replaced: "abcdwxyz") == false)
        #expect(AddressComparison.sharesEnds(original: "abcd1234wxyz", replaced: "abcX1234wxyz") == false)
        #expect(AddressComparison.sharesEnds(original: "abcd1234wxyz", replaced: "abcd1234wxyX") == false)
        #expect(AddressComparison.sharesEnds(original: "abcd12wxyz", replaced: "abcd34wxyz"))
    }

    @Test("任一串不足 8 个字符时不算首尾相同")
    func sharesEndsNeedsLength() {
        #expect(AddressComparison.sharesEnds(original: "abcdxyz", replaced: "abcdQxyz") == false)
        #expect(AddressComparison.sharesEnds(original: "abcdQxyz", replaced: "abcdxyz") == false)
        #expect(AddressComparison.sharesEnds(original: "abcdwxyz", replaced: "abcdQwxyz"))
    }

    @Test("4 个字符一组，最后一组可以更短")
    func groups() {
        #expect(AddressComparison.groups("1A1zP1eP5QGefi") == ["1A1z", "P1eP", "5QGe", "fi"])
        #expect(AddressComparison.groups("abcdefgh") == ["abcd", "efgh"])
        #expect(AddressComparison.groups("abc") == ["abc"])
        #expect(AddressComparison.groups("").isEmpty)
    }

    @Test("0x 开头时 0x 并入第一组")
    func groupsHex() {
        #expect(
            AddressComparison.groups("0x7a3F9c21ab") == ["0x7a3F", "9c21", "ab"])
        #expect(AddressComparison.groups("0x") == ["0x"])
        #expect(AddressComparison.groups("0x12") == ["0x12"])
        #expect(AddressComparison.groups("0x1234") == ["0x1234"])
        #expect(AddressComparison.groups("0x12345") == ["0x1234", "5"])
    }

    @Test("缩写：超过 12 个字符时取前 6 后 4")
    func abbreviated() {
        #expect(
            AddressComparison.abbreviated("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") == "0x5aAe\u{2026}eAed")
        #expect(AddressComparison.abbreviated("abcdefghijkl") == "abcdefghijkl")
        #expect(AddressComparison.abbreviated("abcdefghijklm") == "abcdef\u{2026}jklm")
        #expect(AddressComparison.abbreviated("") == "")
    }
}
