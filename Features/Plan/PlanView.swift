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
    @State private var showEditForm = false
    @State private var goDetail = false
    @State private var selecting = false
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmBatch = false
    @State private var openSwipeID: NSManagedObjectID?
    @State private var miniMapPlace: CDPlace?
    @Environment(\.dismiss) private var dismiss

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _items = FetchRequest(sortDescriptors: [],
                              predicate: NSPredicate(format: "meeting == %@", meeting))
    }

    var body: some View {
        // 删除后本页对象失效：立即退出，避免渲染已删 CDMeeting 触发 fault 崩溃
        if meeting.managedObjectContext == nil || meeting.isDeleted {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
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
                            VStack(spacing: 0) {
                                if selecting {
                                    planRow(item)
                                } else {
                                    // 行内紧凑左滑：日程轻量、与备忘 chip 的长按删除同级，不弹确认
                                    SwipeDeleteRow(id: item.objectID, openID: $openSwipeID,
                                                   buttonWidth: 56, cornerRadius: 10,
                                                   buttonInset: 4, showsLabel: false) {
                                        let id = item.id
                                        try? PlanItemRepository(context: context).delete(item)
                                        if let id { ReminderScheduler.cancelPlans([id]) }
                                    } content: {
                                        planRow(item)
                                    }
                                }
                                if i < section.items.count - 1 {
                                    DS.hairline.frame(height: 1).padding(.leading, 14)
                                }
                            }
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
        .toolbar {
            if stats.planned > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "管理") {
                        selecting.toggle()
                        selected = []
                        openSwipeID = nil
                    }
                    .font(.system(size: 14))
                }
            }
            if meeting.statusRaw == MeetingStatus.planned.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEditForm = true }
                        .font(.system(size: 14))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FrostedBottomBar {
                if selecting {
                    BatchDeleteBar(count: selected.count) { confirmBatch = true }
                } else {
                    HStack {
                        Text("已安排 \(stats.planned) 项 · 完成 \(stats.done) 项").dsCaption()
                        Spacer()
                        Button("添加日程") { showAdd = true }
                            .buttonStyle(BluePillButtonStyle())
                    }
                }
            }
        }
        .alert("删除所选 \(selected.count) 项？", isPresented: $confirmBatch) {
            Button("删除所选", role: .destructive) {
                let picked = selected.compactMap {
                    try? context.existingObject(with: $0) as? CDPlanItem
                }
                let ids = picked.compactMap(\.id)
                try? PlanItemRepository(context: context).delete(picked)
                ReminderScheduler.cancelPlans(ids)
                selected = []
                selecting = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选日程会删除。")
        }
        .sheet(item: $miniMapPlace) { PlaceMiniMapSheet(place: $0) }
        .sheet(isPresented: $showAdd) { PlanItemFormSheet(meeting: meeting, item: nil) }
        .sheet(item: $editingItem) { PlanItemFormSheet(meeting: meeting, item: $0) }
        .sheet(isPresented: $showEditForm, onDismiss: {
            // 表单里删除计划后：等 sheet 完全收场再退出本页——body 守卫在转场中会竞速失效
            if meeting.managedObjectContext == nil || meeting.isDeleted { dismiss() }
        }) { MeetingFormView(mode: .edit(meeting)) }
        .navigationDestination(isPresented: $goDetail) { MeetingDetailView(meeting: meeting) }
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
                        goDetail = true   // 反馈④：开始后直接进见面详情（时间线），不留在计划页
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

    private func planRow(_ item: CDPlanItem) -> some View {
        HStack(spacing: 10) {
            if selecting {
                SelectionCircle(isOn: selected.contains(item.objectID), size: 20)
            } else {
                Button {
                    try? PlanItemRepository(context: context).toggleDone(item)
                    // 反馈⑧终审:勾掉即取消提醒，对齐"记得做"(LedgerListView)的 toggle 处理；
                    // 取消勾选不恢复提醒——同构，不做重新排程
                    if item.isDone, let id = item.id {
                        ReminderScheduler.cancel(id: ReminderPlanner.planID(id))
                    }
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(item.isDone ? DS.actionBlue : DS.chipBorder)
                }
                .buttonStyle(DSPressEffect())
            }

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
                if let placeLabel = item.place?.name ?? item.placeText, !placeLabel.isEmpty {
                    Text(placeLabel)
                        .font(.system(size: 12)).foregroundStyle(DS.actionBlue)
                        .onTapGesture {
                            // 反馈⑦ 1A：点日程地点弹临时小地图——见面结束后仍可定位，不进地图页
                            if !selecting, let place = item.place,
                               place.latitude != 0 || place.longitude != 0 {
                                miniMapPlace = place
                            }
                        }
                }
            }
            Spacer()
            AvatarInitial(name: authorName(item.authorPartnerID), size: 20)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting { toggleSelection(item.objectID) } else { editingItem = item }
        }
    }

    private func memoChip(_ item: CDPlanItem) -> some View {
        Button {
            if selecting { toggleSelection(item.objectID) }
            else {
                try? PlanItemRepository(context: context).toggleDone(item)
                // 反馈⑧终审:勾掉即取消提醒，对齐"记得做"；取消勾选不恢复
                if item.isDone, let id = item.id {
                    ReminderScheduler.cancel(id: ReminderPlanner.planID(id))
                }
            }
        } label: {
            HStack(spacing: 5) {
                if selecting {
                    SelectionCircle(isOn: selected.contains(item.objectID), size: 15)
                }
                Text(item.title ?? "")
                    .font(.system(size: 13))
                    .strikethrough(item.isDone, color: DS.inkMuted)
                    .foregroundStyle(item.isDone ? DS.inkMuted : DS.ink)
            }
            .padding(.vertical, 6).padding(.horizontal, 12)
            .background(Capsule().fill(DS.canvas))
            .overlay(Capsule().stroke(DS.hairline, lineWidth: 1))
        }
        .buttonStyle(DSPressEffect())
        .contextMenu {
            Button("编辑") { editingItem = item }
            Button("删除", role: .destructive) {
                let id = item.id
                try? PlanItemRepository(context: context).delete(item)
                if let id { ReminderScheduler.cancelPlans([id]) }
            }
        }
    }

    private func toggleSelection(_ id: NSManagedObjectID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
