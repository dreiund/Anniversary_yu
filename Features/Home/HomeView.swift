import SwiftUI
import CoreData
import CloudKit

struct HomeView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @FetchRequest(sortDescriptors: []) private var moods: FetchedResults<CDDailyMood>
    @FetchRequest(sortDescriptors: []) private var dateDays: FetchedResults<CDDateDay>
    @FetchRequest(sortDescriptors: []) private var planItems: FetchedResults<CDPlanItem>
    @FetchRequest(fetchRequest: {
        // 提醒区只关心最近的待补评：限量 50 条按时间倒序，年深日久也不全表扫描；
        // 更久远的未评价记忆不再入提醒（补评提醒本就该关注近期）。
        let request = NSFetchRequest<CDMoment>(entityName: "CDMoment")
        request.sortDescriptors = [NSSortDescriptor(key: "happenedAt", ascending: false)]
        request.fetchLimit = 50
        return request
    }())
    private var momentsAll: FetchedResults<CDMoment>
    @State private var accountAvailable = true
    @State private var showMoodSheet = false

    private var couple: CDCouple? { couples.first }

    var body: some View {
        ScrollView {
            let _ = (moods.count, dateDays.count, planItems.count, momentsAll.count)  // 注册观察：心情/约会日/计划项/记忆（含对方同步进来的）变更均刷新首页
            if let couple {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if !accountAvailable {
                        ParchmentCard {
                            HStack(spacing: 8) {
                                Circle().fill(DS.dsRed).frame(width: 6, height: 6)
                                Text("同步已暂停 · 登录 iCloud 后自动恢复").dsCaption()
                            }
                        }
                    }
                    header(couple)
                    hero(couple)
                    statusCard(couple)
                    moodCard(couple)
                    reminders(couple)
                }
                .padding(DS.Spacing.md)
            }
        }
        .background(DS.canvas)
        .task { await refreshAccountStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task { await refreshAccountStatus() }
        }
        .sheet(isPresented: $showMoodSheet) {
            if let couple { MoodSheet(couple: couple) }
        }
    }

    private func header(_ couple: CDCouple) -> some View {
        let partners = CoupleRepository(context: context).partners(of: couple)
        return HStack {
            HStack(spacing: -6) {
                ForEach(partners, id: \.objectID) { p in
                    AvatarInitial(name: p.name ?? "", size: 28)
                }
            }
            Spacer()
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.inkMuted)
            }
        }
    }

    private func hero(_ couple: CDCouple) -> some View {
        VStack(spacing: 4) {
            Text("我们的时光").dsFootnote()
            if let anniversary = couple.anniversaryDate {
                let days = HomeLogic.daysTogether(anniversary: anniversary, today: Date(), calendar: .current)
                Text("在一起 \(days) 天")
                    .dsHero()
                    .contentTransition(.numericText())
                let toNext = HomeLogic.daysToNextAnniversary(anniversary: anniversary, today: Date(), calendar: .current)
                Text("\(Fmt.ymd.string(from: anniversary)) · 距纪念日还有 \(toNext) 天")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.actionBlue)
            } else {
                Text("在设置里填上在一起的日子").dsCaption()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
    }

    @ViewBuilder
    private func statusCard(_ couple: CDCouple) -> some View {
        let repo = MeetingRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let planned = try? repo.nextPlannedMeeting(couple: couple, after: Calendar.current.startOfDay(for: Date()))

        if let ongoing {
            let dayIndex = (try? repo.daysSorted(in: ongoing).last?.dayIndex) ?? 0
            NavigationLink {
                MeetingDetailView(meeting: ongoing)
            } label: {
                DarkCard {
                    VStack(spacing: 4) {
                        Text("第 \(ongoing.index) 次见面 · 进行中")
                            .font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text(dayIndex > 0 ? "第 \(dayIndex) 天" : "还没开始记录")
                            .font(.system(size: 30, weight: .semibold)).tracking(-0.6)
                        Text("点开看时间线 ›")
                            .font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
            }
            .buttonStyle(DSPressEffect())
        } else if showCountdown, let planned, let start = planned.plannedStart {
            let days = HomeLogic.countdownDays(to: start, from: Date(), calendar: .current)
            let stats = PlanItemRepository(context: context).stats(for: planned)
            NavigationLink {
                PlanView(meeting: planned)
            } label: {
                DarkCard {
                    VStack(spacing: 4) {
                        Text("距下次见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                        Text("\(days) 天")
                            .font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                            .contentTransition(.numericText())
                        Text("查看行前计划 · 已安排 \(stats.planned) 项 ›")
                            .font(.system(size: 13)).foregroundStyle(DS.skyBlue)
                    }
                }
            }
            .buttonStyle(DSPressEffect())
        } else {
            DarkCard {
                VStack(spacing: 4) {
                    Text("还没有计划中的见面").font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                    Text("去足迹页计划一次吧").font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    private func moodCard(_ couple: CDCouple) -> some View {
        let repo = CoupleRepository(context: context)
        let me = repo.currentPartner(of: couple)
        let other = repo.otherPartner(of: couple)
        let moodRepo = DailyMoodRepository(context: context)
        let mine = moodRepo.mood(couple: couple, authorID: me?.id, day: Date(), calendar: .current)
        let partnerMood = other.flatMap {
            moodRepo.mood(couple: couple, authorID: $0.id, day: Date(), calendar: .current)
        }
        return Button {
            showMoodSheet = true
        } label: {
            ParchmentCard {
                HStack(spacing: 8) {
                    Text("今日心情").dsCaption()
                    if let emoji = mine?.moodEmoji {
                        Text(emoji).font(.system(size: 18))
                    } else {
                        Circle().stroke(DS.chipBorder, style: StrokeStyle(lineWidth: 1, dash: [3]))
                            .frame(width: 24, height: 24)
                            .overlay(Text("+").dsCaption())
                    }
                    if let partnerEmoji = partnerMood?.moodEmoji {
                        Text(partnerEmoji).font(.system(size: 18))
                    }
                    Spacer()
                    if let other, partnerMood == nil {
                        Text("\(other.name ?? "TA") 还没打卡").dsFootnote()
                    }
                }
            }
        }
        .buttonStyle(DSPressEffect())
    }

    @ViewBuilder
    private func reminders(_ couple: CDCouple) -> some View {
        let meetingRepo = MeetingRepository(context: context)
        let momentRepo = MomentRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let stale = ongoing.flatMap { try? meetingRepo.staleOpenDay(in: $0, now: Date()) } ?? nil
        let myID = CoupleRepository(context: context).currentPartnerID(of: couple)
        let pendingEvals = Array(momentsAll.lazy.filter { momentRepo.evaluation(of: $0, by: myID) == nil }.prefix(3))

        Text("提醒").dsSectionTitle()
        GroupedSection {
            if stale == nil && pendingEvals.isEmpty {
                GroupedRow(title: "一切都好", value: "去足迹翻翻回忆 ›", showsDivider: false)
            } else {
                if let ongoing, stale != nil {
                    NavigationLink {
                        MeetingDetailView(meeting: ongoing)
                    } label: {
                        GroupedRow(title: "昨天忘了封盘？", value: "去封盘 ›",
                                   valueColor: DS.actionBlue, showsDivider: !pendingEvals.isEmpty)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(pendingEvals.enumerated()), id: \.element.objectID) { i, moment in
                    NavigationLink {
                        MomentDetailView(moment: moment)
                    } label: {
                        GroupedRow(title: "「\(moment.title ?? "新回忆")」还没写你的评价",
                                   value: "去补评 ›", valueColor: DS.actionBlue,
                                   showsDivider: i < pendingEvals.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MainActor
    private func refreshAccountStatus() async {
        let status = try? await CKContainer(identifier: PersistenceController.cloudContainerID).accountStatus()
        accountAvailable = status == .available
    }
}
