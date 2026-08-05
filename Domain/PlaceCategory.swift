import Foundation

/// 地点七类（spec §二）。raw 已锁死：0 恒为「其他」，存量 categoryRaw=0 自动归此类。
/// 禁止改序、插入、删除——CloudKit 上的历史数据按 raw 解读。
enum PlaceCategory: Int16, CaseIterable {
    case other = 0
    case food = 1
    case cafe = 2
    case scenery = 3
    case shopping = 4
    case show = 5
    case stay = 6

    var label: String {
        switch self {
        case .other: return "其他"
        case .food: return "美食"
        case .cafe: return "咖啡甜品"
        case .scenery: return "景点公园"
        case .shopping: return "逛街"
        case .show: return "影展演出"
        case .stay: return "住宿"
        }
    }

    static func from(raw: Int16) -> PlaceCategory {
        PlaceCategory(rawValue: raw) ?? .other
    }
}
