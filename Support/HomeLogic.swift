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

    /// 距下一个周年纪念日的天数（当天=0）；2/29 纪念日在非闰年按 2/28 计（既定政策，测试锁死）
    static func daysToNextAnniversary(anniversary: Date, today: Date, calendar: Calendar) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let annComps = calendar.dateComponents([.month, .day], from: anniversary)
        let year = calendar.component(.year, from: todayStart)

        func candidate(inYear y: Int) -> Date? {
            var comps = DateComponents(year: y, month: annComps.month, day: annComps.day)
            if let d = calendar.date(from: comps),
               calendar.dateComponents([.month, .day], from: d) == annComps {
                return calendar.startOfDay(for: d)
            }
            // 2/29 在非闰年会溢出成 3/1：按政策回落到 2/28
            if annComps.month == 2, annComps.day == 29 {
                comps.day = 28
                return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
            }
            return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
        }

        let thisYear = candidate(inYear: year)
        let next: Date
        if let thisYear, thisYear >= todayStart {
            next = thisYear
        } else {
            next = candidate(inYear: year + 1) ?? todayStart
        }
        return countdownDays(to: next, from: today, calendar: calendar)
    }
}
