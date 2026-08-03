import SwiftUI
import CoreData

struct PlanView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @FetchRequest private var items: FetchedResults<CDPlanItem>
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "statusRaw == %d", MeetingStatus.ongoing.rawValue)
    ) private var ongoingMeetings: FetchedResults<CDMeeting>
    @State private var editingItem: CDPlanItem?
    @State private var showAdd = false

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _items = FetchRequest(sortDescriptors: [],
                              predicate: NSPredicate(format: "meeting == %@", meeting))
    }

    var body: some View {
        let _ = items.count  // 注册 FetchRequest 依赖：任何 CDPlanItem 变更触发本视图刷新
        let repo = PlanItemRepository(context: context)
        let sections = repo.sections(for: meeting, calendar: .current)
        let stats = repo.stats(for: meeting)

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header

                ForEach(sections.dated, id: \.day) { section in
                    Text(Fmt.monthDayWeek.string(from: section.day)).dsSectionTitle()
                    GroupedSection {
                        ForEach(Array(section.items.enumerated()), id: \.element.objectID) { i, item in
                            planRow(item, showsDivider: i < section.items.count - 1)
                        }
                    }
                }

                if !sections.undated.isEmpty {
                    Text("备忘").dsSectionTitle()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 8) {
                        ForEach(sections.undated, id: \.objectID) { item in
                            memoChip(item)
                        }
                    }
                }

                if stats.planned == 0 {
                    Text("还没有安排，点下面「添加日程」开始").dsCaption()
                        .frame(maxWidth: .infinity).padding(.top, 24)
                }
            }
            .padding(DS.Spacing.md)
            .padding(.bottom, 80)
        }
        .background(DS.parchment)
        .navigationTitle("行前计划")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            FrostedBottomBar {
                HStack {
                    Text("已安排 \(stats.planned) 项 · 完成 \(stats.done) 项").dsCaption()
                    Spacer()
                    Button("添加日程") { showAdd = true }
                        .buttonStyle(BluePillButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showAdd) { PlanItemFormSheet(meeting: meeting, item: nil) }
        .sheet(item: $editingItem) { PlanItemFormSheet(meeting: meeting, item: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · ")
                 .isEmpty ? "第 \(meeting.index) 次见面" : [meeting.city, meeting.title].compactMap { $0 }.joined(separator: " · "))
                .dsPageTitle()
            if let start = meeting.plannedStart {
                let days = HomeLogic.countdownDays(to: start, from: Date(), calendar: .current)
                Text("距出发还有 \(days) 天").dsCaption()
            }
            if meeting.statusRaw == MeetingStatus.planned.rawValue {
                if ongoingMeetings.isEmpty {
                    Button("开始见面") {
                        try? MeetingRepository(context: context).start(meeting, at: Date())
                    }
                    .buttonStyle(BluePillButtonStyle())
                    .padding(.top, 6)
                } else {
                    Text("先结束进行中的见面，再开始这一次").dsFootnote().padding(.top, 6)
                }
            }
        }
    }

    private func authorName(_ id: UUID?) -> String {
        let repo = CoupleRepository(context: context)
        guard let id, let couple = try? repo.fetchCouple() else { return "" }
        return repo.partners(of: couple).first { $0.id == id }?.name ?? ""
    }

    private func planRow(_ item: CDPlanItem, showsDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    try? PlanItemRepository(context: context).toggleDone(item)
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.time.map { Fmt.hm.string(from: $0) } ?? "全天")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.actionBlue)
                        Text(item.title ?? "").dsBody()
                            .strikethrough(item.isDone, color: DS.inkMuted)
                    }
                    if let note = item.note, !note.isEmpty {
                        Text(note).dsFootnote()
                    }
                    if let place = item.placeText, !place.isEmpty {
                        Text(place).font(.system(size: 12)).foregroundStyle(DS.actionBlue)
                    }
                }
                Spacer()
                AvatarInitial(name: authorName(item.authorPartnerID), size: 20)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { editingItem = item }
            if showsDivider {
                DS.hairline.frame(height: 1).padding(.leading, 14)
            }
        }
    }

    private func memoChip(_ item: CDPlanItem) -> some View {
        Button {
            try? PlanItemRepository(context: context).toggleDone(item)
        } label: {
            Text(item.title ?? "")
                .font(.system(size: 13))
                .strikethrough(item.isDone, color: DS.inkMuted)
                .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Capsule().fill(DS.canvas))
                .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))
        }
        .buttonStyle(DSPressEffect())
        .contextMenu {
            Button("编辑") { editingItem = item }
            Button("删除", role: .destructive) {
                try? PlanItemRepository(context: context).delete(item)
            }
        }
    }
}
