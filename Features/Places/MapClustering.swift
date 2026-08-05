import Foundation
import CoreGraphics

struct ClusterInput: Equatable {
    let id: UUID
    let point: CGPoint
}

enum ClusterOutput: Equatable {
    case pin(id: UUID, point: CGPoint)
    case cluster(ids: [UUID], point: CGPoint)
}

/// 屏幕空间贪心聚合（spec §4.1：视觉重叠即合并）。
/// 输入顺序决定分组种子，调用方需先按稳定键排序保证确定性。
enum MapClusterer {
    static func cluster(_ items: [ClusterInput], threshold: CGFloat) -> [ClusterOutput] {
        var groups: [[ClusterInput]] = []
        for item in items.sorted(by: { ($0.point.y, $0.point.x, $0.id.uuidString) < ($1.point.y, $1.point.x, $1.id.uuidString) }) {
            if let i = groups.firstIndex(where: { group in
                let seed = group[0].point
                return hypot(seed.x - item.point.x, seed.y - item.point.y) <= threshold
            }) {
                groups[i].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.map { group in
            if group.count == 1 {
                return .pin(id: group[0].id, point: group[0].point)
            }
            let cx = group.map(\.point.x).reduce(0, +) / CGFloat(group.count)
            let cy = group.map(\.point.y).reduce(0, +) / CGFloat(group.count)
            return .cluster(ids: group.map(\.id), point: CGPoint(x: cx, y: cy))
        }
    }
}
