import Foundation

struct CyclePrediction: Equatable {
    let cycleLength: Int
    let periodLength: Int
    let isDefault: Bool
    let nextStarts: [Date]      // 3 个预测开始日；首个可能已过（推迟中）
    let ongoingEnd: Date?       // 进行中段预计结束日
}

/// 预测引擎（spec §五 / 主 spec §5.3）：完整周期 <2 用缺省 28/7
enum CyclePredictor {
    static func predict(cycles: [(start: Date, end: Date?)], calendar: Calendar) -> CyclePrediction {
        let sorted = cycles.sorted { $0.start < $1.start }
        let completed = sorted.filter { $0.end != nil }
        let intervals = zip(completed, completed.dropFirst()).map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.start),
                                    to: calendar.startOfDay(for: $1.start)).day ?? 0
        }
        let durations = completed.map {
            (calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.start),
                                     to: calendar.startOfDay(for: $0.end!)).day ?? 0) + 1
        }
        let isDefault = completed.count < 2
        let cycleLength = isDefault ? 28 : Int((Double(intervals.suffix(6).reduce(0, +))
                                                / Double(intervals.suffix(6).count)).rounded())
        let periodLength = isDefault ? 7 : Int((Double(durations.suffix(6).reduce(0, +))
                                                / Double(durations.suffix(6).count)).rounded())
        var nextStarts: [Date] = []
        var ongoingEnd: Date?
        if let latest = sorted.last {
            let base = calendar.startOfDay(for: latest.start)
            nextStarts = (1...3).compactMap { calendar.date(byAdding: .day, value: cycleLength * $0, to: base) }
            if latest.end == nil {
                ongoingEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: base)
            }
        }
        return CyclePrediction(cycleLength: cycleLength, periodLength: periodLength,
                               isDefault: isDefault, nextStarts: nextStarts, ongoingEnd: ongoingEnd)
    }

    /// 推迟 n 天：今天已过预测开始日、且无进行中段（spec §五）
    static func delayDays(nextStart: Date, hasOngoing: Bool, today: Date, calendar: Calendar) -> Int? {
        guard !hasOngoing else { return nil }
        let n = calendar.dateComponents([.day], from: calendar.startOfDay(for: nextStart),
                                        to: calendar.startOfDay(for: today)).day ?? 0
        return n > 0 ? n : nil
    }

    /// 偏差（徽标）：实际−当时预测，正=推迟 负=早来；无预测（补录）= nil
    static func deviationDays(predictedAtLogging: Date?, actualStart: Date, calendar: Calendar) -> Int? {
        guard let predicted = predictedAtLogging else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: predicted),
                                       to: calendar.startOfDay(for: actualStart)).day
    }
}

struct OvulationWindow: Equatable {
    let ovulationDay: Date
    let days: [Date]
}

extension CyclePredictor {
    /// 排卵窗（反馈⑥ 1A）：排卵日=「下一次开始日」−14 天；窗=前 5 后 4 共 10 天。
    /// 历史区间回填（相邻两段中后一段的实际开始日）+ 未来预测（nextStarts 逐个）。
    static func ovulationWindows(cycles: [(start: Date, end: Date?)],
                                 nextStarts: [Date], calendar: Calendar) -> [OvulationWindow] {
        let sortedStarts = cycles.map { calendar.startOfDay(for: $0.start) }.sorted()
        let anchors = Array(sortedStarts.dropFirst()) + nextStarts.map { calendar.startOfDay(for: $0) }
        return anchors.compactMap { nextStart in
            guard let ovulation = calendar.date(byAdding: .day, value: -14, to: nextStart) else { return nil }
            let days = (-5...4).compactMap { calendar.date(byAdding: .day, value: $0, to: ovulation) }
            return OvulationWindow(ovulationDay: ovulation, days: days)
        }
    }
}
