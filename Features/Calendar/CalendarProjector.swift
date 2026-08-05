import Foundation

/// 日历双投影纯函数（spec §三）。Core Data 无关，单测直调。
enum CalendarMode { case natural, dateDay }

struct CalMomentInput: Equatable {
    let happenedDay: Date        // happenedAt 的自然日 0 点
    let dateDayDay: Date?        // 归属 CDDateDay(openedAt) 的自然日 0 点；nil 按 happenedDay
}

struct CalMoodInput: Equatable {
    let day: Date                // 自然日 0 点
    let isMine: Bool
    let emoji: String
}

struct CalMeetingInput: Equatable {
    let index: Int32
    let firstDay: Date           // 首个自然日 0 点（startedAt 归日）
    let lastDay: Date            // 末个自然日 0 点（endedAt 归日；进行中传 today）
}

enum BandPosition: Equatable { case single, start, middle, end }

struct CalCell: Equatable {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let myEmoji: String?
    let partnerEmoji: String?
    let hasMoment: Bool
    let band: BandPosition?
    let bandLabel: String?       // "第 n 次"，该见面带在当月的首格才有
    let dTag: String?            // "D1"，仅约会日模式的见面天
    let faded: Bool              // 聚焦压灰：仅约会日模式的非见面日
}

struct CalSummary: Equatable {
    let daysTogether: Int
    let momentCount: Int
}

enum CalendarProjector {
    private static func mondayFirst(_ base: Calendar) -> Calendar {
        var c = base
        c.firstWeekday = 2
        return c
    }

    static func cells(monthAnchor: Date, today: Date, mode: CalendarMode,
                      moments: [CalMomentInput], moods: [CalMoodInput],
                      meetings: [CalMeetingInput], calendar: Calendar) -> [CalCell] {
        let cal = mondayFirst(calendar)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor))!
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)!.count
        let leading = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let total = Int((Double(leading + dayCount) / 7.0).rounded(.up)) * 7
        let gridStart = cal.date(byAdding: .day, value: -leading, to: monthStart)!

        // 记忆按模式归日
        var momentDays = Set<Date>()
        for m in moments {
            let key = mode == .dateDay ? (m.dateDayDay ?? m.happenedDay) : m.happenedDay
            momentDays.insert(cal.startOfDay(for: key))
        }
        // 心情恒自然日
        var myMood = [Date: String](), partnerMood = [Date: String]()
        for mood in moods {
            let key = cal.startOfDay(for: mood.day)
            if mood.isMine { myMood[key] = mood.emoji } else { partnerMood[key] = mood.emoji }
        }

        return (0..<total).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: gridStart)!
            let inMonth = cal.isDate(day, equalTo: monthStart, toGranularity: .month)
            let meeting = meetings.first { $0.firstDay <= day && day <= $0.lastDay }
            var band: BandPosition?
            var bandLabel: String?
            var dTag: String?
            if let meeting {
                if meeting.firstDay == meeting.lastDay { band = .single }
                else if cal.isDate(day, inSameDayAs: meeting.firstDay) { band = .start }
                else if cal.isDate(day, inSameDayAs: meeting.lastDay) { band = .end }
                else { band = .middle }
                let firstInMonth = max(meeting.firstDay, monthStart)
                if inMonth, cal.isDate(day, inSameDayAs: firstInMonth) {
                    bandLabel = "第 \(meeting.index) 次"
                }
                if mode == .dateDay {
                    let d = cal.dateComponents([.day], from: meeting.firstDay, to: day).day! + 1
                    dTag = "D\(d)"
                }
            }
            return CalCell(day: day,
                           inMonth: inMonth,
                           isToday: cal.isDate(day, inSameDayAs: today),
                           myEmoji: myMood[day],
                           partnerEmoji: partnerMood[day],
                           hasMoment: momentDays.contains(day),
                           band: band,
                           bandLabel: bandLabel,
                           dTag: dTag,
                           faded: mode == .dateDay && meeting == nil && inMonth)
        }
    }

    static func summary(monthAnchor: Date, moments: [CalMomentInput],
                        meetings: [CalMeetingInput], calendar: Calendar) -> CalSummary {
        let cal = mondayFirst(calendar)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: monthAnchor))!
        let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart)!
        var togetherDays = Set<Date>()
        for m in meetings {
            var day = max(m.firstDay, monthStart)
            while day <= m.lastDay && day < nextMonth {
                togetherDays.insert(day)
                day = cal.date(byAdding: .day, value: 1, to: day)!
            }
        }
        let count = moments.filter {
            let key = cal.startOfDay(for: $0.dateDayDay ?? $0.happenedDay)
            return key >= monthStart && key < nextMonth
        }.count
        return CalSummary(daysTogether: togetherDays.count, momentCount: count)
    }
}
