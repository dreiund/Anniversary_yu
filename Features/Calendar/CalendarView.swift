import SwiftUI
import CoreData

/// 足迹·日历段（spec §三）。数据自取：本 couple 全量记忆/心情/见面，交给 CalendarProjector 投影。
struct CalendarView: View {
    let onDayTap: (Date, CalendarMode) -> Void
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMoment.happenedAt)])
    private var moments: FetchedResults<CDMoment>
    @FetchRequest(sortDescriptors: []) private var moods: FetchedResults<CDDailyMood>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index)])
    private var meetings: FetchedResults<CDMeeting>
    @AppStorage("footprintsCycleTintOn") private var cycleTintOn = true
    @FetchRequest(sortDescriptors: []) private var cyclesFetch: FetchedResults<CDCycle>

    @State private var monthOffset = 0
    @State private var mode: CalendarMode = .natural

    private var cal: Calendar { Calendar.current }

    /// 当前显示月锚点：由 monthOffset 派生（反馈⑥ T7，配合 TabView(.page) 分页与回今天同步；本视图无 ‹› 步进钮）
    private var monthAnchor: Date {
        cal.date(byAdding: .month, value: monthOffset, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private var isCurrentMonth: Bool {
        cal.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.sm) {
                modeToggle
                Text(monthTitle).dsCaption()
                calendarCard
                if mode == .dateDay { summaryCard }
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .toolbar {
            if !isCurrentMonth {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今天") {
                        withAnimation(.snappy) { monthOffset = 0 }
                    }
                    .font(.system(size: 14))
                }
            }
        }
    }

    private var monthTitle: String {
        let c = cal.dateComponents([.year, .month], from: monthAnchor)
        return "\(c.year!) 年 \(c.month!) 月"
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleHalf("自然日", .natural, leading: true)
            toggleHalf("约会日", .dateDay, leading: false)
        }
        .fixedSize()
    }

    private func toggleHalf(_ title: String, _ target: CalendarMode, leading: Bool) -> some View {
        Button {
            withAnimation(.snappy) { mode = target }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: mode == target ? .semibold : .regular))
                .foregroundStyle(mode == target ? .white : DS.inkMuted)
                .padding(.vertical, 5).padding(.horizontal, 14)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: leading ? 999 : 0, bottomLeadingRadius: leading ? 999 : 0,
                        bottomTrailingRadius: leading ? 0 : 999, topTrailingRadius: leading ? 0 : 999)
                        .fill(mode == target ? DS.actionBlue : DS.canvas)
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: leading ? 999 : 0, bottomLeadingRadius: leading ? 999 : 0,
                        bottomTrailingRadius: leading ? 0 : 999, topTrailingRadius: leading ? 0 : 999)
                        .stroke(mode == target ? DS.actionBlue : DS.chipBorder, lineWidth: 1)
                )
        }
        .buttonStyle(DSPressEffect())
    }

    /// 单月格子投影（反馈⑥ T7 改吃传入 anchor，供 TabView 各分页各自取数；投影规则零改动）
    private func projectedCells(for anchor: Date) -> [CalCell] {
        guard let couple = couples.first else { return [] }
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let momentInputs = moments.map { m in
            CalMomentInput(
                happenedDay: cal.startOfDay(for: m.happenedAt ?? .distantPast),
                dateDayDay: m.dateDay?.openedAt.map { cal.startOfDay(for: $0) })
        }
        let moodInputs = moods.compactMap { mood -> CalMoodInput? in
            guard let day = mood.day, let emoji = mood.moodEmoji else { return nil }
            return CalMoodInput(day: cal.startOfDay(for: day),
                                isMine: mood.authorPartnerID == myID, emoji: emoji)
        }
        let meetingInputs = meetings.compactMap { m -> CalMeetingInput? in
            guard let start = m.startedAt else { return nil }   // 计划中不上带（spec §一）
            let last = m.endedAt ?? Date()
            return CalMeetingInput(index: m.index,
                                   firstDay: cal.startOfDay(for: start),
                                   lastDay: cal.startOfDay(for: last))
        }
        return CalendarProjector.cells(monthAnchor: anchor, today: Date(), mode: mode,
                                       moments: momentInputs, moods: moodInputs,
                                       meetings: meetingInputs, calendar: cal)
    }

    /// 经期天集合（浅粉底用）：每段 start…(end ?? 今天) 逐日展开（样板照 HerView.marks）
    private var cycleDaySet: Set<Date> {
        var result: Set<Date> = []
        let today = cal.startOfDay(for: Date())
        for cycle in cyclesFetch {
            guard let start = cycle.startDate else { continue }
            var day = cal.startOfDay(for: start)
            let upper = cal.startOfDay(for: cycle.endDate ?? today)
            while day <= upper {
                result.insert(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    /// 排卵窗（反馈⑥ T6）：ovulationWindows 展开天数/排卵日集合，经期优先在 cell 渲染层处理（同受 cycleTintOn 控制）
    private var ovulationWindows: [OvulationWindow] {
        let inputs = cyclesFetch.compactMap { c -> (start: Date, end: Date?)? in
            c.startDate.map { ($0, c.endDate) }
        }
        let prediction = CyclePredictor.predict(cycles: inputs, calendar: cal)
        return CyclePredictor.ovulationWindows(cycles: inputs, nextStarts: prediction.nextStarts, calendar: cal)
    }

    private var ovulationDaySet: Set<Date> {
        Set(ovulationWindows.flatMap(\.days))
    }

    private var ovulationFlowerDaySet: Set<Date> {
        Set(ovulationWindows.map(\.ovulationDay))
    }

    private var calendarCard: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w).font(.system(size: 10)).foregroundStyle(DS.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            TabView(selection: $monthOffset) {
                ForEach(-24...12, id: \.self) { offset in
                    let anchor = cal.date(byAdding: .month, value: offset, to: cal.startOfDay(for: Date())) ?? Date()
                    monthGrid(anchor: anchor)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 296)   // 6 行网格：44×6+行间距 4×5=284，+12pt 余量防止内容被裁（同 HerView.calendarCard 样板）
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
    }

    /// 单月格子网格（反馈⑥ T7 从 calendarCard 抽出，按 anchor 供 TabView 各分页渲染；格内容/点天/经期排卵底色零改动）
    private func monthGrid(anchor: Date) -> some View {
        let cells = projectedCells(for: anchor)
        let cycleDays = cycleDaySet
        let ovulationDays = ovulationDaySet
        let ovulationFlowerDays = ovulationFlowerDaySet
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                  spacing: 4) {
            ForEach(cells, id: \.day) { cell in
                CalendarDayCell(cell: cell,
                                isCycleDay: cycleTintOn && cycleDays.contains(cell.day),
                                isOvulationDay: cycleTintOn && ovulationDays.contains(cell.day),
                                isOvulationFlower: cycleTintOn && ovulationFlowerDays.contains(cell.day))
                    .contentShape(Rectangle())
                    .onTapGesture { if cell.inMonth { onDayTap(cell.day, mode) } }
            }
        }
    }

    private var summaryCard: some View {
        let s = summaryData
        return Group {
            if s.daysTogether == 0 {
                Text("这个月还没见面 · 下次见面快来了")
            } else {
                Text("这个月在一起 \(Text("\(s.daysTogether) 天").foregroundStyle(DS.skyBlue)) · 记了 \(Text("\(s.momentCount)").foregroundStyle(DS.skyBlue)) 条回忆")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.darkCard))
    }

    private var summaryData: CalSummary {
        let momentInputs = moments.map { m in
            CalMomentInput(
                happenedDay: cal.startOfDay(for: m.happenedAt ?? .distantPast),
                dateDayDay: m.dateDay?.openedAt.map { cal.startOfDay(for: $0) })
        }
        let meetingInputs = meetings.compactMap { m -> CalMeetingInput? in
            guard let start = m.startedAt else { return nil }
            return CalMeetingInput(index: m.index,
                                   firstDay: cal.startOfDay(for: start),
                                   lastDay: cal.startOfDay(for: m.endedAt ?? Date()))
        }
        return CalendarProjector.summary(monthAnchor: monthAnchor, moments: momentInputs,
                                         meetings: meetingInputs, calendar: cal)
    }
}

/// 单格：日期 + 心情 emoji 对 + 记录墨点 + 见面带底 + D 标（spec §3.1/3.2）
struct CalendarDayCell: View {
    let cell: CalCell
    var isCycleDay: Bool = false
    var isOvulationDay: Bool = false
    var isOvulationFlower: Bool = false

    var body: some View {
        VStack(spacing: 1) {
            if cell.isToday {
                Text(dayNumber)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.actionBlue)
                    .frame(width: 17, height: 17)
                    .overlay(Circle().stroke(DS.actionBlue, lineWidth: 1.5))
            } else {
                Text(dayNumber)
                    .font(.system(size: 11))
                    .foregroundStyle(cell.inMonth ? DS.ink : DS.chipBorder)
            }
            HStack(spacing: 0) {
                if let mine = cell.myEmoji { Text(mine) }
                if let theirs = cell.partnerEmoji { Text(theirs) }
            }
            .font(.system(size: 9))
            .frame(height: 11)
            Circle().fill(DS.ink).frame(width: 3.5, height: 3.5)
                .opacity(cell.hasMoment ? 1 : 0)
            if isOvulationFlower {
                Text("🌸").font(.system(size: 6))
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .opacity(cell.faded ? 0.35 : 1)
        .background {
            ZStack {
                if isCycleDay {
                    RoundedRectangle(cornerRadius: 8).fill(DS.roseCell)
                } else if isOvulationDay {
                    RoundedRectangle(cornerRadius: 8).fill(DS.ovulationBg)
                }
                bandBackground
            }
        }
        .overlay(alignment: .topLeading) {
            if let label = cell.bandLabel {
                Text(label).font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(DS.actionBlue)
                    .padding(.leading, 2)
            }
        }
        .overlay(alignment: .bottom) {
            if let d = cell.dTag {
                Text(d).font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DS.actionBlue)
            }
        }
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: cell.day))"
    }

    @ViewBuilder
    private var bandBackground: some View {
        switch cell.band {
        case .single:
            RoundedRectangle(cornerRadius: 8).fill(DS.bandBlue)
        case .start:
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0).fill(DS.bandBlue)
        case .end:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 8, topTrailingRadius: 8).fill(DS.bandBlue)
        case .middle:
            Rectangle().fill(DS.bandBlue)
        case nil:
            EmptyView()
        }
    }
}
