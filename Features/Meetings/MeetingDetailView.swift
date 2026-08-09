import SwiftUI
import CoreData

struct MeetingDetailView: View {
    @Environment(\.managedObjectContext) private var context
    let meeting: CDMeeting
    @State private var segment = 0
    @State private var confirmEnd = false
    @State private var showEditForm = false
    @State private var selecting = false
    @State private var selected: Set<NSManagedObjectID> = []
    @State private var confirmBatch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("第 \(meeting.index) 次见面\(meeting.city.map { " · \($0)" } ?? "")").dsFootnote()
                        .lineLimit(1)   // 三段 chips 定宽后，空间不足由标题截断
                }
                Spacer()
                HStack(spacing: 4) {
                    SelectableChip(title: "时间线", isSelected: segment == 0) { segment = 0 }
                    SelectableChip(title: "路线图", isSelected: segment == 1) { segment = 1 }
                    // 反馈⑧:见面开始后行前计划整体并入时间线,「计划」入口只在计划中状态存在
                    if meeting.statusRaw == MeetingStatus.planned.rawValue {
                        SelectableChip(title: "计划", isSelected: segment == 2) { segment = 2 }
                    }
                }
            }
            .padding(DS.Spacing.md)

            if segment == 0 {
                ScrollView {
                    TimelineListView(meeting: meeting, selecting: selecting, selected: $selected)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                }
            } else if segment == 1 {
                RouteMapView(meeting: meeting)
            } else if meeting.statusRaw == MeetingStatus.planned.rawValue {
                PlanView(meeting: meeting)
            } else {
                ScrollView {
                    TimelineListView(meeting: meeting, selecting: selecting, selected: $selected)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                }
            }
        }
        .background(DS.parchment)
        .navigationTitle(meeting.title ?? meeting.city ?? "见面")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: segment) { _, _ in
            selecting = false
            selected = []
        }
        .onChange(of: meeting.statusRaw) { _, newValue in
            if segment == 2, newValue != MeetingStatus.planned.rawValue { segment = 0 }
        }
        .toolbar {
            if segment == 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "完成" : "管理") {
                        selecting.toggle()
                        selected = []
                    }
                    .font(.system(size: 14))
                }
            }
            if meeting.statusRaw == MeetingStatus.ongoing.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("结束见面") { confirmEnd = true }
                        .font(.system(size: 14))
                }
            }
            if meeting.statusRaw != MeetingStatus.planned.rawValue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") { showEditForm = true }
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
                let picked = selected.compactMap {
                    try? context.existingObject(with: $0) as? CDMoment
                }
                try? MomentRepository(context: context).delete(picked)
                selected = []
                selecting = false
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所选记忆和照片会一并删除，无法恢复。")
        }
        .alert("结束这次见面？", isPresented: $confirmEnd) {
            Button("结束见面", role: .destructive) {
                // 反馈⑧终审:见面结束,取消该见面全部计划项的提醒——不再按 isDone 过滤
                // (已勾掉的项此前会漏取消,导致见面结束后野提醒仍照响；取消已取消的提醒是幂等操作,无害)
                let planIDs = ((meeting.planItems as? Set<CDPlanItem>) ?? []).compactMap(\.id)
                ReminderScheduler.cancelPlans(planIDs)
                try? MeetingRepository(context: context).end(meeting, at: Date())
                SealReminder.refresh(context: context)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未封盘的天会一并封盘。")
        }
        .sheet(isPresented: $showEditForm) { MeetingFormView(mode: .edit(meeting)) }
    }
}
