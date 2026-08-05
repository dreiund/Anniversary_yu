import Foundation

/// 路线图数据纯函数（spec §六）：按约会日分组、组内按时间排序、每天序号 1 起。
struct RouteStopInput: Equatable {
    let momentID: UUID
    let dayIndex: Int32
    let happenedAt: Date
    let latitude: Double
    let longitude: Double
}

struct RouteStop: Equatable {
    let momentID: UUID
    let order: Int
    let latitude: Double
    let longitude: Double
}

struct RouteDay: Equatable {
    let dayIndex: Int32
    let stops: [RouteStop]
}

enum RouteBuilder {
    static func days(from inputs: [RouteStopInput]) -> [RouteDay] {
        Dictionary(grouping: inputs, by: \.dayIndex)
            .sorted { $0.key < $1.key }
            .map { dayIndex, items in
                let stops = items.sorted { $0.happenedAt < $1.happenedAt }
                    .enumerated()
                    .map { i, item in
                        RouteStop(momentID: item.momentID, order: i + 1,
                                  latitude: item.latitude, longitude: item.longitude)
                    }
                return RouteDay(dayIndex: dayIndex, stops: stops)
            }
    }
}
