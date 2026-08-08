import SwiftUI

enum CycleIntimacyMark { case none, protected, unprotected }

struct CycleDayMarks {
    var inPeriod = false
    var predicted = false
    var ovulation = false
    var isOvulationDay = false
    var painRaw: Int16 = 0
    var flowRaw: Int16 = 0
    var colorRaw: Int16 = 0
    var intimacy: CycleIntimacyMark = .none
}

/// 单月网格（spec §一.4）：浅粉=经期、虚线=预测、墨环=今天、数字下四点
struct CycleMonthGrid: View {
    let anchor: Date                       // 该月任意一天
    let marks: [Date: CycleDayMarks]       // key = startOfDay
    let onDayTap: (Date) -> Void

    private var cal: Calendar { .current }

    var body: some View {
        let days = monthDays()
        VStack(spacing: 4) {
            HStack {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                    Text($0).dsFootnote().frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                      spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                            .onTapGesture { onDayTap(day) }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let m = marks[day] ?? CycleDayMarks()
        let isToday = cal.isDateInToday(day)
        return VStack(spacing: 2) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 13, weight: m.inPeriod ? .semibold : .regular))
                .foregroundStyle(m.inPeriod || m.predicted ? DS.roseCycle : (m.ovulation ? DS.ovulationInk : DS.ink))
            if m.isOvulationDay {
                Text("🌸").font(.system(size: 7))
            }
            HStack(spacing: 2) {
                dot(for: m.painRaw)
                dot(for: m.flowRaw)
                dot(for: m.colorRaw)
                intimacyDot(m.intimacy)
            }
            .frame(height: 6)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background {
            if m.inPeriod {
                RoundedRectangle(cornerRadius: 9).fill(DS.roseCell)
            } else if m.ovulation {
                RoundedRectangle(cornerRadius: 9).fill(DS.ovulationBg)
            } else if m.predicted {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(DS.roseCycle, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 9).stroke(DS.ink, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dot(for raw: Int16) -> some View {
        if raw > 0 {
            Circle().fill([DS.dsGreen, DS.dsOrange, DS.dsRed][Int(raw) - 1])
                .frame(width: 5, height: 5)
        }
    }

    @ViewBuilder
    private func intimacyDot(_ mark: CycleIntimacyMark) -> some View {
        switch mark {
        case .none: EmptyView()
        case .protected: Circle().fill(DS.actionBlue).frame(width: 5, height: 5)
        case .unprotected: Circle().stroke(DS.actionBlue, lineWidth: 1.2).frame(width: 5, height: 5)
        }
    }

    /// 周一起始：前导 nil 补位 + 当月全部天
    private func monthDays() -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = interval.start
        let count = cal.range(of: .day, in: .month, for: anchor)?.count ?? 30
        let weekday = cal.component(.weekday, from: first)     // 1=周日 … 7=周六
        let leading = (weekday + 5) % 7                        // 周一起始的空位数
        return Array(repeating: nil, count: leading) + (0..<count).compactMap {
            cal.date(byAdding: .day, value: $0, to: first)
        }
    }
}
