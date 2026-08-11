import Foundation

// raw 值会写入数据库并跨设备同步：只许追加，禁止修改或删除已有 case。

enum MeetingStatus: Int16 {
    case planned = 0, ongoing = 1, finished = 2
}

enum MomentType: Int16, CaseIterable {
    case restaurant = 0, sight = 1, activity = 2, stay = 3, other = 4

    var title: String {
        switch self {
        case .restaurant: "餐厅"
        case .sight: "景点"
        case .activity: "活动"
        case .stay: "住宿"
        case .other: "其他"
        }
    }
}

enum LedgerCategory: Int16, CaseIterable {
    case praise = 0, complaint = 1, like = 2, trigger = 3

    var title: String {
        switch self {
        case .praise: "积极"
        case .complaint: "消极"
        case .like: "喜欢"
        case .trigger: "雷区"
        }
    }
}

enum EntryVisibility: Int16 {
    case sharedImmediately = 0, privateUntilRevealed = 1
}

enum FlowLevel: Int16, CaseIterable {
    case none = 0, light = 1, medium = 2, heavy = 3, veryHeavy = 4

    var title: String {
        switch self {
        case .none: "无"
        case .light: "少"
        case .medium: "中"
        case .heavy: "多"
        case .veryHeavy: "极多"
        }
    }
}

enum PainLevel: Int16, CaseIterable {
    case none = 0, mild = 1, moderate = 2, severe = 3

    var title: String {
        switch self {
        case .none: "无"
        case .mild: "轻"
        case .moderate: "中"
        case .severe: "重"
        }
    }
}

enum CycleColor: Int16, CaseIterable {
    case brightRed = 0, darkRed = 1, brown = 2, pink = 3, other = 4

    var title: String {
        switch self {
        case .brightRed: "鲜红"
        case .darkRed: "暗红"
        case .brown: "褐色"
        case .pink: "粉"
        case .other: "其他"
        }
    }
}

extension MomentType {
    /// 反馈⑧:计划转回忆时按地点类目推记忆类型
    init(placeCategory: PlaceCategory) {
        switch placeCategory {
        case .food, .cafe: self = .restaurant
        case .scenery: self = .sight
        case .shopping, .show: self = .activity
        case .stay: self = .stay
        case .travel: self = .activity   // 反馈⑬③:出行类计划转回忆归「活动」
        case .other: self = .other
        }
    }
}
