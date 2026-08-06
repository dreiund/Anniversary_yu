import SwiftUI
import CoreData

struct TimelineListView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @FetchRequest private var momentsFetch: FetchedResults<CDMoment>
    @FetchRequest private var daysFetch: FetchedResults<CDDateDay>
    @FetchRequest private var evalsFetch: FetchedResults<CDEvaluation>
    @State private var showSeal = false

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _momentsFetch = FetchRequest(sortDescriptors: [],
                                     predicate: NSPredicate(format: "dateDay.meeting == %@", meeting))
        _daysFetch = FetchRequest(sortDescriptors: [],
                                  predicate: NSPredicate(format: "meeting == %@", meeting))
        _evalsFetch = FetchRequest(sortDescriptors: [],
                                   predicate: NSPredicate(format: "moment.dateDay.meeting == %@", meeting))
    }

    var body: some View {
        let _ = (momentsFetch.count, daysFetch.count, evalsFetch.count)  // 注册观察：记忆/约会日（封盘）/评价（含对方补评与修改）变更均刷新时间线
        let momentsRepo = MomentRepository(context: context)
        let grouped = momentsRepo.daysWithMoments(in: meeting)

        LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
            if grouped.isEmpty {
                Text("还没有记录 · 点底栏 ⊕ 记下第一条")
                    .dsCaption()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            }
            ForEach(grouped, id: \.day.objectID) { day, moments in
                daySection(day: day, moments: moments, repo: momentsRepo)
            }
        }
        .sheet(isPresented: $showSeal) { SealSheet(meeting: meeting) }
    }

    @ViewBuilder
    private func daySection(day: CDDateDay, moments: [CDMoment], repo: MomentRepository) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("第 \(day.dayIndex) 天").dsPageTitle()
            if let opened = day.openedAt {
                Text("\(Fmt.monthDayWeek.string(from: opened)) · \(Fmt.hm.string(from: opened)) 出门").dsFootnote()
            }
        }
        ForEach(moments, id: \.objectID) { moment in
            NavigationLink {
                MomentDetailView(moment: moment)
            } label: {
                momentCard(moment, repo: repo)
            }
            .buttonStyle(.plain)
        }
        if let closed = day.closedAt {
            DarkCard {
                HStack {
                    Text("\(Fmt.hm.string(from: closed)) 封盘 · 晚安")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(moments.count) 条记忆")
                        .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                }
            }
        } else if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
            Button("封盘") { showSeal = true }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
    }

    private func momentCard(_ moment: CDMoment, repo: MomentRepository) -> some View {
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let me = couple.flatMap { couples.currentPartner(of: $0) }
        let other = couple.flatMap { couples.otherPartner(of: $0) }
        let myEval = me.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let otherEval = other.flatMap { repo.evaluation(of: moment, by: $0.id) }
        let partnerName = other?.name ?? "TA"
        let thumb = repo.photosSorted(moment).first?.thumbnailData

        return VStack(alignment: .leading, spacing: 6) {
            if let thumb, let ui = UIImage(data: thumb) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
            }
            HStack {
                Text(moment.title ?? "").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
                Text("\((MomentType(rawValue: moment.typeRaw) ?? .other).title) · \(moment.happenedAt.map { Fmt.hm.string(from: $0) } ?? "")")
                    .dsFootnote()
                Spacer()
                if let emoji = myEval?.moodEmoji { Text(emoji) }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let myEval {
                    HStack(spacing: 4) {
                        Text("你").dsFootnote()
                        StarsView(stars: Int(myEval.stars))
                        if let comment = myEval.comment, !comment.isEmpty {
                            Text("“\(comment)”").font(.system(size: 12)).foregroundStyle(DS.ink).lineLimit(2)
                        }
                    }
                }
                if let otherEval {
                    HStack(spacing: 4) {
                        Text(partnerName).dsFootnote()
                        StarsView(stars: Int(otherEval.stars))
                        if let comment = otherEval.comment, !comment.isEmpty {
                            Text("“\(comment)”").font(.system(size: 12)).foregroundStyle(DS.ink).lineLimit(2)
                        }
                    }
                } else {
                    Text("\(partnerName) · 还没写").dsFootnote()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
        // 命中区限定在卡片矩形内：scaledToFill 照片的不可见溢出不再劫持相邻卡片的点击
        .contentShape(Rectangle())
    }
}
