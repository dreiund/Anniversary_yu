import SwiftUI
import CoreData

struct SelectedCalendarDay: Identifiable {
    let id: Date
    var mode: CalendarMode
}

/// 点天抽屉（spec §3.3）：日期头 + 心情行 + 记忆行 + 封盘行；内容按当前投影模式归日。
struct DaySheet: View {
    let day: Date
    let mode: CalendarMode
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMoment.happenedAt)])
    private var allMoments: FetchedResults<CDMoment>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index)])
    private var meetings: FetchedResults<CDMeeting>

    private var cal: Calendar { Calendar.current }

    private var dayMoments: [CDMoment] {
        allMoments.filter { m in
            let key: Date
            if mode == .dateDay, let opened = m.dateDay?.openedAt {
                key = opened
            } else {
                key = m.happenedAt ?? .distantPast
            }
            return cal.isDate(key, inSameDayAs: day)
        }
    }

    /// 该自然日所处的约会日（用于 D 标与封盘行）
    private var dateDayInfo: (meetingIndex: Int32, dayIndex: Int32, closedAt: Date?)? {
        for meeting in meetings {
            for case let dd as CDDateDay in (meeting.dateDays ?? []) {
                if let opened = dd.openedAt, cal.isDate(opened, inSameDayAs: day) {
                    return (meeting.index, dd.dayIndex, dd.closedAt)
                }
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    moodRow
                    if dayMoments.isEmpty {
                        Text("这天还没有记录").dsCaption()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(dayMoments, id: \.objectID) { moment in
                            momentRow(moment)
                        }
                    }
                    if let info = dateDayInfo, let closed = info.closedAt {
                        Text("\(Fmt.hm.string(from: closed)) 封盘 · 晚安")
                            .dsFootnote()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.canvas)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Fmt.monthDay.string(from: day))
                .font(.system(size: 17, weight: .bold))
            if let info = dateDayInfo {
                Text("第 \(info.meetingIndex) 次见面 · D\(info.dayIndex)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.actionBlue)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var moodRow: some View {
        let repo = CoupleRepository(context: context)
        let moodRepo = DailyMoodRepository(context: context)
        guard let couple = couples.first else { return AnyView(EmptyView()) }
        let me = repo.currentPartner(of: couple)
        let other = repo.otherPartner(of: couple)
        let mine = moodRepo.mood(couple: couple, authorID: me?.id, day: day, calendar: cal)
        let theirs = other.flatMap { moodRepo.mood(couple: couple, authorID: $0.id, day: day, calendar: cal) }
        guard mine != nil || theirs != nil else { return AnyView(EmptyView()) }
        var parts: [String] = []
        if let m = mine?.moodEmoji { parts.append("\(m) 我") }
        if let t = theirs?.moodEmoji { parts.append("\(t) \(other?.name ?? "TA")") }
        return AnyView(
            Text(parts.joined(separator: "  ·  "))
                .dsCaption()
                .padding(.bottom, 8)
        )
    }

    private func momentRow(_ moment: CDMoment) -> some View {
        let repo = MomentRepository(context: context)
        let thumbData = repo.photosSorted(moment).first?.thumbnailData
        let myID = couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
        let stars = repo.evaluation(of: moment, by: myID)?.stars
        let subtitle = [
            moment.place.map { PlaceCategory.from(raw: $0.categoryRaw).label },
            moment.happenedAt.map { Fmt.hm.string(from: $0) }
        ].compactMap { $0 }.joined(separator: " · ")
        return NavigationLink {
            MomentDetailView(moment: moment)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let data = thumbData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                .allowsHitTesting(false)   // 溢出不抢相邻行点击
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title ?? "未命名").dsBody().lineLimit(1)
                    Text(subtitle).dsFootnote()
                }
                Spacer()
                if let stars {
                    Text("★\(stars)").font(.system(size: 11)).foregroundStyle(DS.ink)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())   // 缩略图退出命中后，整行仍可点
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { DS.hairline.frame(height: 1) }
    }
}
