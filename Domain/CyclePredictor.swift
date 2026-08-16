import Foundation

struct CyclePrediction: Equatable {
    let cycleLength: Int
    let periodLength: Int
    let isDefault: Bool
    let nextStarts: [Date]        // 3 个预测开始日(已顺延:无进行中段时首个不早于今天)
    let scheduledNextStart: Date? // 表定下次开始(未顺延)——落库「当时预测」/偏差统计的口径依据
    let overdueDays: Int?         // 已推迟 n 天(仅 n>0:无进行中段且今天已过表定开始日)
    let ongoingEnd: Date?         // 进行中段预计结束日(不早于今天)
}

/// 预测引擎（spec §五 / 主 spec §5.3）：完整周期 <2 用种子（用户设置值，缺省 28/7）。
/// R20：预测不留在过去——表定开始日已过而经期未来时，三个预测窗整体顺延锚到今天，
/// 后续月份与排卵窗（挂在 nextStarts 上）随之重算；「当时预测」仍记表定日，偏差/准时率口径不受顺延污染。
enum CyclePredictor {
    static func predict(cycles: [(start: Date, end: Date?)],
                        prefs: (cycleLength: Int?, periodLength: Int?) = (nil, nil),
                        today: Date, calendar: Calendar) -> CyclePrediction {
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
        let cycleLength = isDefault ? (prefs.cycleLength ?? 28)
            : Int((Double(intervals.suffix(6).reduce(0, +)) / Double(intervals.suffix(6).count)).rounded())
        let periodLength = isDefault ? (prefs.periodLength ?? 7)
            : Int((Double(durations.suffix(6).reduce(0, +)) / Double(durations.suffix(6).count)).rounded())
        let todayStart = calendar.startOfDay(for: today)
        var nextStarts: [Date] = []
        var scheduledNextStart: Date?
        var overdueDays: Int?
        var ongoingEnd: Date?
        if let latest = sorted.last {
            let base = calendar.startOfDay(for: latest.start)
            let scheduled = calendar.date(byAdding: .day, value: cycleLength, to: base) ?? base
            scheduledNextStart = scheduled
            var anchor = scheduled
            if latest.end == nil {
                let rawEnd = calendar.date(byAdding: .day, value: periodLength - 1, to: base) ?? base
                ongoingEnd = max(rawEnd, todayStart)
            } else if scheduled < todayStart {
                overdueDays = calendar.dateComponents([.day], from: scheduled, to: todayStart).day
                anchor = todayStart
            }
            nextStarts = (0...2).compactMap {
                calendar.date(byAdding: .day, value: cycleLength * $0, to: anchor)
            }
        }
        return CyclePrediction(cycleLength: cycleLength, periodLength: periodLength,
                               isDefault: isDefault, nextStarts: nextStarts,
                               scheduledNextStart: scheduledNextStart,
                               overdueDays: overdueDays, ongoingEnd: ongoingEnd)
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
    /// 排卵窗（反馈⑥ 1A）：排卵日=「下一次开始日」−14 天（黄体期恒定，卵泡期随周期伸缩——
    /// 周期长短、顺延与否都自动传导，无需按周期比例换算）；窗=前 5 后 4 共 10 天。
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
