import SwiftUI
import CoreData

struct MeetingsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @State private var showForm = false
    @State private var segment = 0
    @State private var selectedDay: SelectedCalendarDay?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                SelectableChip(title: "列表", isSelected: segment == 0) { segment = 0 }
                SelectableChip(title: "日历", isSelected: segment == 1) { segment = 1 }
                SelectableChip(title: "地图", isSelected: segment == 2) { segment = 2 }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 8)

            switch segment {
            case 1:
                CalendarView(onDayTap: { day, mode in
                    selectedDay = SelectedCalendarDay(id: day, mode: mode)
                })
            case 2:
                Text("地图（下一任务接入）").dsCaption()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.canvas)
            default:
                listContent
            }
        }
        .background(DS.canvas)
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForm) {
            if let couple = couples.first { MeetingFormView(mode: .create(couple)) }
        }
        .sheet(item: $selectedDay) { sel in
            DaySheet(day: sel.id, mode: sel.mode)
                .presentationDetents([.medium, .large])
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                ForEach(meetings, id: \.objectID) { meeting in
                    card(for: meeting)
                }
                if meetings.isEmpty {
                    Text("还没有见面记录").dsCaption().padding(.top, 48)
                }
                Button("计划见面") { showForm = true }
                    .buttonStyle(GhostPillButtonStyle())
                    .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
    }

    private func dateRange(_ m: CDMeeting) -> String {
        let s = m.startedAt ?? m.plannedStart
        let e = m.endedAt ?? m.plannedEnd
        switch (s, e) {
        case let (s?, e?): return "\(Fmt.monthDay.string(from: s)) – \(Fmt.monthDay.string(from: e))"
        case let (s?, nil): return Fmt.monthDay.string(from: s)
        default: return "日期待定"
        }
    }

    @ViewBuilder
    private func card(for meeting: CDMeeting) -> some View {
        switch MeetingStatus(rawValue: meeting.statusRaw) ?? .planned {
        case .planned:
            NavigationLink { PlanView(meeting: meeting) } label: { plannedCard(meeting) }
                .buttonStyle(DSPressEffect())
        case .ongoing:
            NavigationLink { MeetingDetailView(meeting: meeting) } label: { ongoingCard(meeting) }
                .buttonStyle(DSPressEffect())
        case .finished:
            NavigationLink { MeetingDetailView(meeting: meeting) } label: { finishedCard(meeting) }
                .buttonStyle(DSPressEffect())
        }
    }

    private func plannedCard(_ meeting: CDMeeting) -> some View {
        let stats = PlanItemRepository(context: context).stats(for: meeting)
        let days = meeting.plannedStart.map {
            HomeLogic.countdownDays(to: $0, from: Date(), calendar: .current)
        }
        return ParchmentCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(meeting.index) 次见面 · 计划中").dsFootnote()
                Text([meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · ")
                     .isEmpty ? "未命名的见面" : [meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · "))
                    .dsPageTitle()
                HStack {
                    Text("\(dateRange(meeting)) · 行前计划 \(stats.done)/\(stats.planned)").dsCaption()
                    Spacer()
                    if let days {
                        Text("\(days) 天后")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 4).padding(.horizontal, 12)
                            .background(Capsule().fill(DS.actionBlue))
                    }
                }
            }
        }
    }

    private func ongoingCard(_ meeting: CDMeeting) -> some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("第 \(meeting.index) 次见面 · 进行中")
                    .font(.system(size: 13)).foregroundStyle(DS.onDarkMuted)
                Text(meeting.city ?? meeting.title ?? "这次见面")
                    .font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                Text(dateRange(meeting)).font(.system(size: 13)).foregroundStyle(DS.skyBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func finishedCard(_ meeting: CDMeeting) -> some View {
        let momentsRepo = MomentRepository(context: context)
        let grouped = momentsRepo.daysWithMoments(in: meeting)
        let momentCount = grouped.reduce(0) { $0 + $1.moments.count }
        let cover = grouped
            .flatMap(\.moments)
            .compactMap { momentsRepo.photosSorted($0).first?.thumbnailData }
            .first

        return ZStack(alignment: .bottomLeading) {
            if let cover, let ui = UIImage(data: cover) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.image)
                            .fill(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                                 startPoint: .center, endPoint: .bottom))
                    )
                    .dsPhotoShadow()
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.image)
                    .fill(DS.parchment)
                    .frame(height: 120)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(meeting.index) 次见面")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cover != nil ? DS.onDarkMuted : DS.inkMuted)
                Text("\(meeting.city ?? "") · \(dateRange(meeting)) · \(momentCount) 条记忆")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(cover != nil ? .white : DS.ink)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
    }
}
