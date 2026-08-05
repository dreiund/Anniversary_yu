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

    @State private var monthAnchor = Calendar.current.startOfDay(for: Date())
    @State private var mode: CalendarMode = .natural

    private var cal: Calendar { Calendar.current }

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
                        withAnimation(.snappy) { monthAnchor = cal.startOfDay(for: Date()) }
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

    private var projectedCells: [CalCell] {
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
        return CalendarProjector.cells(monthAnchor: monthAnchor, today: Date(), mode: mode,
                                       moments: momentInputs, moods: moodInputs,
                                       meetings: meetingInputs, calendar: cal)
    }

    private var calendarCard: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                    Text(w).font(.system(size: 10)).foregroundStyle(DS.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            let cells = projectedCells
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                      spacing: 4) {
                ForEach(cells, id: \.day) { cell in
                    CalendarDayCell(cell: cell)
                        .contentShape(Rectangle())
                        .onTapGesture { if cell.inMonth { onDayTap(cell.day, mode) } }
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.snappy) {
                    monthAnchor = cal.date(byAdding: .month,
                                           value: value.translation.width < 0 ? 1 : -1,
                                           to: monthAnchor)!
                }
            }
        )
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
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .opacity(cell.faded ? 0.35 : 1)
        .background(bandBackground)
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
