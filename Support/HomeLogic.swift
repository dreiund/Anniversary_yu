import Foundation

enum HomeLogic {
    /// 在一起第 N 天：纪念日当天 = 第 1 天（含首日）
    static func daysTogether(anniversary: Date, today: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: anniversary)
        let to = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days + 1, 1)
    }

    /// 距目标日期还有几天（按自然日，当天=0，过期归 0）
    static func countdownDays(to target: Date, from today: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: today)
        let to = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(days, 0)
    }

    /// 距下一个周年纪念日的天数（当天=0）
    static func daysToNextAnniversary(anniversary: Date, today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let comps = calendar.dateComponents([.month, .day], from: anniversary)
        var next = calendar.nextDate(after: todayStart.addingTimeInterval(-1),
                                     matching: comps, matchingPolicy: .nextTime) ?? todayStart
        if calendar.startOfDay(for: next) < todayStart {
            next = calendar.date(byAdding: .year, value: 1, to: next) ?? next
        }
        return countdownDays(to: next, from: today, calendar: calendar)
    }
}
