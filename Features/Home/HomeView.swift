import SwiftUI
import CoreData

struct HomeView: View {
    @Environment(\.managedObjectContext) private var context
    @AppStorage("showCountdown") private var showCountdown = true
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @FetchRequest(sortDescriptors: []) private var moods: FetchedResults<CDDailyMood>
    @State private var showMoodSheet = false

    private var couple: CDCouple? { couples.first }

    var body: some View {
        ScrollView {
            if let couple {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
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
        let partners = repo.partners(of: couple)
        let mine = DailyMoodRepository(context: context)
            .mood(couple: couple, authorID: partners.first?.id, day: Date(), calendar: .current)
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
                    Spacer()
                    Text(partners.count > 1 ? "\(partners[1].name ?? "TA") 还没打卡" : "")
                        .dsFootnote()
                }
            }
        }
        .buttonStyle(DSPressEffect())
    }

    @ViewBuilder
    private func reminders(_ couple: CDCouple) -> some View {
        let repo = MeetingRepository(context: context)
        let ongoing = meetings.first { $0.statusRaw == MeetingStatus.ongoing.rawValue }
        let stale = ongoing.flatMap { try? repo.staleOpenDay(in: $0, now: Date()) } ?? nil

        Text("提醒").dsSectionTitle()
        GroupedSection {
            if let ongoing, stale != nil {
                NavigationLink {
                    MeetingDetailView(meeting: ongoing)
                } label: {
                    GroupedRow(title: "昨天忘了封盘？", value: "去封盘 ›",
                               valueColor: DS.actionBlue, showsDivider: false)
                }
                .buttonStyle(.plain)
            } else {
                GroupedRow(title: "一切都好", value: "去足迹翻翻回忆 ›", showsDivider: false)
            }
        }
    }
}
