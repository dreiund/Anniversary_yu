import SwiftUI
import CoreData

struct TimelineListView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    let selecting: Bool
    @Binding var selected: Set<NSManagedObjectID>
    @FetchRequest private var momentsFetch: FetchedResults<CDMoment>
    @FetchRequest private var daysFetch: FetchedResults<CDDateDay>
    @FetchRequest private var evalsFetch: FetchedResults<CDEvaluation>
    @State private var showSeal = false
    @State private var openSwipeID: NSManagedObjectID?
    @State private var pendingDeleteMoment: CDMoment?
    @State private var pendingDeleteDay: CDDateDay?
    @State private var blockedDayCount: Int?

    init(meeting: CDMeeting, selecting: Bool = false,
         selected: Binding<Set<NSManagedObjectID>> = .constant([])) {
        self.meeting = meeting
        self.selecting = selecting
        _selected = selected
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
        .alert("删除这条记忆？", isPresented: Binding(get: { pendingDeleteMoment != nil },
                                                set: { if !$0 { pendingDeleteMoment = nil } })) {
            Button("删除记忆", role: .destructive) {
                if let moment = pendingDeleteMoment {
                    try? MomentRepository(context: context).delete(moment)
                }
                pendingDeleteMoment = nil
            }
            Button("取消", role: .cancel) { pendingDeleteMoment = nil }
        } message: {
            Text("这条记忆和它的照片、评价会一并删除，无法恢复。")
        }
        .alert("删除第 \(pendingDeleteDay?.dayIndex ?? 0) 天？",
               isPresented: Binding(get: { pendingDeleteDay != nil },
                                    set: { if !$0 { pendingDeleteDay = nil } })) {
            Button("删除这天", role: .destructive) {
                if let day = pendingDeleteDay {
                    try? MeetingRepository(context: context).deleteDay(day)
                }
                pendingDeleteDay = nil
            }
            Button("取消", role: .cancel) { pendingDeleteDay = nil }
        } message: {
            Text("这一天的封盘记录会删除，之后的天序号自动前移。")
        }
        .alert("还不能删除", isPresented: Binding(get: { blockedDayCount != nil },
                                            set: { if !$0 { blockedDayCount = nil } })) {
            Button("好") { blockedDayCount = nil }
        } message: {
            Text("这一天还有 \(blockedDayCount ?? 0) 条记忆，先删掉记忆再删封盘。")
        }
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
            if selecting {
                Button {
                    if selected.contains(moment.objectID) { selected.remove(moment.objectID) }
                    else { selected.insert(moment.objectID) }
                } label: {
                    HStack(spacing: 10) {
                        SelectionCircle(isOn: selected.contains(moment.objectID))
                        momentCard(moment, repo: repo)
                    }
                }
                .buttonStyle(DSPressEffect())
            } else {
                SwipeDeleteRow(id: moment.objectID, openID: $openSwipeID) {
                    pendingDeleteMoment = moment
                } content: {
                    NavigationLink {
                        MomentDetailView(moment: moment)
                    } label: {
                        momentCard(moment, repo: repo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if let closed = day.closedAt {
            let sealCard = DarkCard {
                HStack {
                    Text("\(Fmt.hm.string(from: closed)) 封盘 · 晚安")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(moments.count) 条记忆")
                        .font(.system(size: 12)).foregroundStyle(DS.onDarkMuted)
                }
            }
            if selecting {
                sealCard
            } else {
                // 封盘卡左滑删这一天：仅空天可删（还有记忆先弹提示），序号自动前移
                SwipeDeleteRow(id: day.objectID, openID: $openSwipeID) {
                    if moments.isEmpty { pendingDeleteDay = day }
                    else { blockedDayCount = moments.count }
                } content: {
                    sealCard
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
                    // scaledToFill 的不可见溢出会替下方卡片抢走上方卡片的点击（clipShape 不裁命中区）；
                    // 装饰图彻底退出命中测试，点击全部交给卡片矩形
                    .allowsHitTesting(false)
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
