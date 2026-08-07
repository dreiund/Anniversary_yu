import Foundation

/// 统计口径（spec §四）：准时率 |偏差|≤2（徽标仍 ±0，两口径并存）
enum CycleStats {
    static func painRate(painRaws: [Int16]) -> Double? {
        let logged = painRaws.filter { $0 > 0 }
        guard !logged.isEmpty else { return nil }
        return Double(logged.filter { $0 >= 2 }.count) / Double(logged.count)
    }

    static func onTimeRate(deviations: [Int?]) -> Double? {
        let samples = deviations.compactMap { $0 }
        guard !samples.isEmpty else { return nil }
        return Double(samples.filter { abs($0) <= 2 }.count) / Double(samples.count)
    }
}
