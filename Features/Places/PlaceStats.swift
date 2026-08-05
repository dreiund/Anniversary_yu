import Foundation

/// 地点统计口径（spec §五）：来过 = 去重约会日数；均分 = 星均值（无评价为 nil）。
enum PlaceStats {
    static func visitCount(dateDayIDs: [UUID?]) -> Int {
        Set(dateDayIDs.compactMap { $0 }).count
    }

    static func average(_ stars: [Int16]) -> Double? {
        guard !stars.isEmpty else { return nil }
        return Double(stars.reduce(0) { $0 + Int($1) }) / Double(stars.count)
    }
}
