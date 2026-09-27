import CoreGraphics

/// 假名补识别（§3.2 第 3 步）：含假名的组以日文优先再识别「该段区域」，用识别结果替换该组。纯函数
///
/// 区域 = 组内各行外框的并集外扩半个（组内最小）行高。补识别只裁出所有区域的外接矩形来识别，不重识别整张图；
/// 补识别出的每一行只归入一个组（中心落在其区域内、与组外框重叠最多的那个），相距不到半行高的两组不会拿到同一行。
public enum KanaReplacement {
    /// 所有含假名的组的区域的外接矩形（像素，已与图像范围相交并取整）；没有含假名的组时为 nil
    public static func searchArea(for groups: [[OCRLine]], imageSize: CGSize) -> CGRect? {
        let union = regions(of: groups).values.reduce(CGRect.null) { $0.union($1.region) }
        let area = union.intersection(CGRect(origin: .zero, size: imageSize)).integral
        return area.isNull || area.isEmpty ? nil : area
    }

    /// 用补识别出的行（与 groups 同一坐标系）替换含假名的组；分不到行的组、不含假名的组保持原样
    public static func replacing(_ groups: [[OCRLine]], with japanese: [OCRLine]) -> [[OCRLine]] {
        let regions = regions(of: groups)
        var assigned: [Int: [OCRLine]] = [:]
        for line in japanese {
            let center = CGPoint(x: line.box.midX, y: line.box.midY)
            let candidates = regions.filter { $0.value.region.contains(center) }
            guard let owner = candidates.max(by: { isWorse($0, than: $1, for: line) })?.key else { continue }
            assigned[owner, default: []].append(line)
        }
        return groups.indices.map { index in
            guard let lines = assigned[index] else { return groups[index] }
            return lines.sorted { $0.box.minY != $1.box.minY ? $0.box.minY < $1.box.minY : $0.box.minX < $1.box.minX }
        }
    }

    // MARK: - 内部

    private struct Region {
        /// 组内各行外框的并集
        let bounds: CGRect
        /// 外扩半个行高后的搜索区域
        let region: CGRect
    }

    /// 含假名的组 → 区域（键为组下标）
    private static func regions(of groups: [[OCRLine]]) -> [Int: Region] {
        var result: [Int: Region] = [:]
        for (index, group) in groups.enumerated()
        where group.contains(where: { DocumentLineGrouping.containsKana($0.text) }) {
            let bounds = group.dropFirst().reduce(group[0].box) { $0.union($1.box) }
            let margin = 0.5 * (group.map(\.box.height).min() ?? 0)
            result[index] = Region(bounds: bounds, region: bounds.insetBy(dx: -margin, dy: -margin))
        }
        return result
    }

    /// 候选 lhs 是否比 rhs 更不适合拿到 line：先比与组外框的重叠面积，再比中心距离，最后比组下标（稳定）
    private static func isWorse(
        _ lhs: (key: Int, value: Region), than rhs: (key: Int, value: Region), for line: OCRLine
    )
        -> Bool
    {
        let left = overlap(line.box, lhs.value.bounds)
        let right = overlap(line.box, rhs.value.bounds)
        if left != right { return left < right }
        let leftDistance = distance(line.box, lhs.value.bounds)
        let rightDistance = distance(line.box, rhs.value.bounds)
        if leftDistance != rightDistance { return leftDistance > rightDistance }
        return lhs.key > rhs.key
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
    }
}
