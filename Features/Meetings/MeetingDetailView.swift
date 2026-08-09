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
    // 反馈⑨T4:备忘侧签——独立 FetchRequest 挂在这一层(ScrollView 容器外)，
    // 侧签才能贴着屏幕左缘常驻，不会像挂在 TimelineListView 的 LazyVStack 上那样随时间线滚走
    @FetchRequest private var plansFetch: FetchedResults<CDPlanItem>
    @State private var showMemos = false

    init(meeting: CDMeeting) {
        self.meeting = meeting
        _plansFetch = FetchRequest(sortDescriptors: [],
                                   predicate: NSPredicate(format: "meeting == %@", meeting))
    }

    // 备忘只在进行中/已结束展示(与 TimelineListView 的 showPlans 口径一致)；计划中态该走「计划」chip 里的 PlanView
    private var showPlans: Bool {
        meeting.statusRaw == MeetingStatus.ongoing.rawValue || meeting.statusRaw == MeetingStatus.finished.rawValue
    }
    // 反馈⑨终审修(M-3):按 sortIndex 排序,与 PlanView 备忘区(PlanItemRepository.sections 的 undated)口径一致——
    // FetchRequest 本身未设 sortDescriptors,不排序时行序跨启动不稳
    private var memos: [CDPlanItem] {
        showPlans ? plansFetch.filter { $0.day == nil }.sorted { $0.sortIndex < $1.sortIndex } : []
    }

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
        // 反馈⑨T4:备忘侧签——挂在这一层(时间线 ScrollView 的容器外)才能常驻不随滚动消失；
        // 只在「时间线」分段且有备忘时露出，路线图/计划分段不出现
        // 反馈⑨T4修(评审 Moderate,spec §一):侧签要竖排书签样式——汉字逐字竖排，数字压在最下面
        .overlay(alignment: .leading) {
            if segment == 0 && !memos.isEmpty {
                Button { showMemos = true } label: {
                    VStack(spacing: 2) {
                        ForEach(Array("备忘"), id: \.self) { ch in
                            Text(String(ch))
                        }
                        Text("\(memos.count)")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    // 反馈⑩bug2:加大字号与内边距,热区补足到 44pt 触控标准(原来太小不好点)
                    .padding(.vertical, 14).padding(.horizontal, 9)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                       bottomTrailingRadius: 10, topTrailingRadius: 10)
                        .fill(DS.ink))
                    // 反馈⑪:热区框要 alignment .leading——默认居中会把签块推离屏幕左缘留缝;
                    // 透明热区只向右侧延伸,签块本体紧贴屏幕边
                    .frame(minWidth: 48, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressEffect())
            }
        }
        .sheet(isPresented: $showMemos) {
            MemoListSheet(meeting: meeting)
        }
    }
}
