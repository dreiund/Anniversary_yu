import Foundation

/// 地点七类（spec §二）。raw 已锁死：0 恒为「其他」，存量 categoryRaw=0 自动归此类。
/// 禁止改序、插入、删除——CloudKit 上的历史数据按 raw 解读。
enum PlaceCategory: Int16, CaseIterable {
    case other = 0
    case food = 1
    case cafe = 2      // 反馈⑬③归并进「美食」展示,不再新写(旧数据按 raw 解读不动)
    case scenery = 3
    case shopping = 4
    case show = 5      // 反馈⑬③归并进「逛街」展示,不再新写
    case stay = 6
    case travel = 7    // 反馈⑬③新增「出行」(车站/机场/码头等;新 raw 追加不动旧值,零 schema)

    var label: String {
        switch self {
        case .other: return "其他"
        case .food: return "美食"
        case .cafe: return "咖啡甜品"
        case .scenery: return "景点公园"
        case .shopping: return "逛街"
        case .show: return "影展演出"
        case .stay: return "住宿"
        case .travel: return "出行"
        }
    }

    /// 反馈⑬③:对外展示/筛选的类目(用户定稿顺序);cafe/show 不再单列
    static let displayCases: [PlaceCategory] = [.other, .travel, .food, .scenery, .shopping, .stay]

    /// 展示类目所涵盖的 raw 集合:美食⊇咖啡甜品,逛街⊇影展演出(旧数据自动归并)
    var mergedRaws: Set<Int16> {
        switch self {
        case .food: return [PlaceCategory.food.rawValue, PlaceCategory.cafe.rawValue]
        case .shopping: return [PlaceCategory.shopping.rawValue, PlaceCategory.show.rawValue]
        default: return [rawValue]
        }
    }

    static func from(raw: Int16) -> PlaceCategory {
        PlaceCategory(rawValue: raw) ?? .other
    }
}
