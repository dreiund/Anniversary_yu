import SwiftUI
import CoreData

struct MeetingsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDCouple.createdAt)]) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDMeeting.index, order: .reverse)])
    private var meetings: FetchedResults<CDMeeting>
    @State private var showForm = false
    @State private var pendingDelete: CDMeeting?
    @State private var openSwipeID: NSManagedObjectID?
    @State private var selecting = false
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmBatch = false

    private var deleteIsPlanned: Bool {
        pendingDelete.map { MeetingStatus(rawValue: $0.statusRaw) == .planned } ?? false
    }
    @State private var segment = 0
    @State private var selectedDay: SelectedCalendarDay?

    private var myID: UUID? {
        couples.first.flatMap { CoupleRepository(context: context).currentPartnerID(of: $0) }
    }
    /// R17 私密计划过滤(spec §四):对方未公开的私密计划整条不出现——列表/空态/批量/toolbar 全走这份
    private var visibleMeetings: [CDMeeting] { meetings.filter { $0.isVisible(to: myID) } }

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
                PlacesMapView()
            default:
                listContent
            }
        }
        .background(DS.canvas)
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: segment) { _, _ in
            selecting = false
            selected = []
        }
        .toolbar {
            if segment == 0 && !visibleMeetings.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "管理") {
                        selecting.toggle()
                        selected = []
                        openSwipeID = nil
                    }
                    .font(.system(size: 14))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && segment == 0 {
                FrostedBottomBar {
                    BatchDeleteBar(count: selected.count) { confirmBatch = true }
                }
            }
        }
        .alert("删除所选 \(selected.count) 项？", isPresented: $confirmBatch) {
            Button("删除所选", role: .destructive) {
                let picked = visibleMeetings.filter { selected.contains($0.objectID) }
                let ids = picked.flatMap { (($0.planItems as? Set<CDPlanItem>) ?? []).compactMap(\.id) }
                try? MeetingRepository(context: context).delete(Array(picked))
                ReminderScheduler.cancelPlans(ids)
                selected = []
                selecting = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选见面的约会日、记忆和照片会一并删除，无法恢复。")
        }
        .sheet(isPresented: $showForm) {
            if let couple = couples.first { MeetingFormView(mode: .create(couple)) }
        }
        .sheet(item: $selectedDay) { sel in
            DaySheet(day: sel.id, mode: sel.mode)
                .presentationDetents([.medium, .large])
        }
        .alert(deleteIsPlanned ? "删除这次计划？" : "删除这次见面？",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } })) {
            Button(deleteIsPlanned ? "删除计划" : "删除见面", role: .destructive) {
                if let meeting = pendingDelete {
                    let ids = ((meeting.planItems as? Set<CDPlanItem>) ?? []).compactMap(\.id)
                    try? MeetingRepository(context: context).delete(meeting)
                    ReminderScheduler.cancelPlans(ids)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteIsPlanned
                 ? "行前计划的日程会一起删除。"
                 : "这次见面的所有约会日、记忆和照片会一并删除，无法恢复。")
        }
    }

    private var listContent: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                ForEach(visibleMeetings, id: \.objectID) { meeting in
                    if selecting {
                        Button {
                            toggleSelection(meeting.objectID)
                        } label: {
                            HStack(spacing: 10) {
                                SelectionCircle(isOn: selected.contains(meeting.objectID))
                                cardBody(for: meeting)
                            }
                        }
                        .buttonStyle(DSPressEffect())
                    } else {
                        SwipeDeleteRow(id: meeting.objectID, openID: $openSwipeID) {
                            pendingDelete = meeting
                        } content: {
                            card(for: meeting)
                        }
                    }
                }
                if visibleMeetings.isEmpty {
                    Text("还没有见面记录").dsCaption().padding(.top, 48)
                }
                Button("计划见面") { showForm = true }
                    .buttonStyle(GhostPillButtonStyle())
                    .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
    }

    private func card(for meeting: CDMeeting) -> some View {
        NavigationLink { destination(for: meeting) } label: { cardBody(for: meeting) }
            .buttonStyle(DSPressEffect())
    }

    private func toggleSelection(_ id: NSManagedObjectID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    @ViewBuilder
    private func destination(for meeting: CDMeeting) -> some View {
        switch MeetingStatus(rawValue: meeting.statusRaw) ?? .planned {
        case .planned: PlanView(meeting: meeting)
        default: MeetingDetailView(meeting: meeting)
        }
    }

    @ViewBuilder
    private func cardBody(for meeting: CDMeeting) -> some View {
        switch MeetingStatus(rawValue: meeting.statusRaw) ?? .planned {
        case .planned: plannedCard(meeting)
        case .ongoing: ongoingCard(meeting)
        case .finished: finishedCard(meeting)
        }
    }

    /// 反馈⑦：只填标题没填城市的见面，结束卡此前一个名字都不显示（原来只取 city）
    private func finishedName(_ m: CDMeeting) -> String {
        let name = [m.city, m.title].compactMap { $0 }.joined(separator: " · ")
        return name.isEmpty ? "未命名的见面" : name
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
    private func plannedCard(_ meeting: CDMeeting) -> some View {
        let stats = PlanItemRepository(context: context).stats(for: meeting)
        let days = meeting.plannedStart.map {
            HomeLogic.countdownDays(to: $0, from: Date(), calendar: .current)
        }
        return ParchmentCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("第 \(meeting.index) 次见面 · 计划中").dsFootnote()
                    if meeting.isPrivateUnrevealed { MeetingPrivacyChip() }
                }
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

        return Group {
            if let cover, let ui = UIImage(data: cover) {
                photoFinishedCard(meeting, cover: ui, momentCount: momentCount)
            } else {
                // 反馈⑧bug2：无照片的结束卡原来是一大块封面占位+底部小字，标题看似消失——
                // 改为文字版式（与计划卡同构，大标题当家）
                ParchmentCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("第 \(meeting.index) 次见面 · 已结束").dsFootnote()
                        Text(finishedName(meeting)).dsPageTitle()
                        Text("\(dateRange(meeting)) · \(momentCount) 条记忆").dsCaption()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func photoFinishedCard(_ meeting: CDMeeting, cover ui: UIImage,
                                   momentCount: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
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
                    .allowsHitTesting(false)   // 溢出不抢相邻卡点击
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("第 \(meeting.index) 次见面")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.onDarkMuted)
                Text("\(finishedName(meeting)) · \(dateRange(meeting)) · \(momentCount) 条记忆")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        // 封面图已退出命中（防溢出抢点击），整卡命中区由此矩形接管
        .contentShape(Rectangle())
    }
}
