import SwiftUI
import CoreData

enum CycleStatsSegment: Hashable { case month, year }

/// 统计页（spec §四）：月|年三数字卡 + 历史周期列表（改起止/左滑删/补录）
struct CycleStatsView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: []) private var cycles: FetchedResults<CDCycle>
    @FetchRequest(sortDescriptors: []) private var dayLogs: FetchedResults<CDCycleDayLog>
    @FetchRequest(sortDescriptors: []) private var intimacyAll: FetchedResults<CDIntimacyRecord>

    @State private var segment: CycleStatsSegment = .month
    @State private var anchorDate = Date()
    @State private var sheetMode: RangeSheetMode?
    @State private var openSwipeID: NSManagedObjectID?
    @State private var pendingDelete: CDCycle?

    private var cal: Calendar { .current }
    private var repo: CycleRepository { CycleRepository(context: context) }

    var body: some View {
        let _ = (cycles.count, dayLogs.count, intimacyAll.count)   // 注册刷新
        if let couple = couples.first {
            content(couple)
        } else {
            Text("先完成配对").dsCaption()
        }
    }

    @ViewBuilder
    private func content(_ couple: CDCouple) -> some View {
        let range = statsRange
        let history = repo.cyclesSorted(couple: couple)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                segmentHeader
                statCards(couple: couple, history: history, range: range)
                historySection(history)
                Button("＋ 补录一段") { sheetMode = .backfill }
                    .buttonStyle(GhostPillButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, DS.Spacing.xs)
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheetMode) { mode in
            CycleRangeSheet(couple: couple, mode: mode, calendar: cal)
        }
        .alert("删除这段经期？", isPresented: Binding(get: { pendingDelete != nil },
                                              set: { if !$0 { pendingDelete = nil } })) {
            Button("删除", role: .destructive) {
                if let cycle = pendingDelete { try? repo.delete(cycle) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("这段的每日记录会一并删除。")
        }
    }

    // MARK: 分段 `月|年` + `‹ ›` 翻范围（spec §四）

    private var segmentHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                SelectableChip(title: "月", isSelected: segment == .month) { segment = .month }
                SelectableChip(title: "年", isSelected: segment == .year) { segment = .year }
            }
            HStack {
                Button { step(-1) } label: {
                    Text("‹").font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(DS.actionBlue)
                Spacer()
                Text(rangeTitle).dsSectionTitle()
                Spacer()
                Button { step(1) } label: {
                    Text("›").font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(DS.actionBlue)
            }
        }
    }

    private func step(_ delta: Int) {
        switch segment {
        case .month: anchorDate = cal.date(byAdding: .month, value: delta, to: anchorDate) ?? anchorDate
        case .year: anchorDate = cal.date(byAdding: .year, value: delta, to: anchorDate) ?? anchorDate
        }
    }

    private var statsRange: DateInterval {
        let interval: DateInterval?
        switch segment {
        case .month: interval = cal.dateInterval(of: .month, for: anchorDate)
        case .year: interval = cal.dateInterval(of: .year, for: anchorDate)
        }
        return interval ?? DateInterval(start: anchorDate, end: anchorDate)
    }

    private var rangeTitle: String {
        let comp = cal.dateComponents([.year, .month], from: anchorDate)
        switch segment {
        case .month: return "\(comp.year ?? 0) 年 \(comp.month ?? 0) 月"
        case .year: return "\(comp.year ?? 0) 年"
        }
    }

    /// 半开区间 [start, end)：避免 DateInterval.contains 两端闭区间在月/年边界重复计入
    private func inRange(_ date: Date, _ range: DateInterval) -> Bool {
        date >= range.start && date < range.end
    }

    // MARK: 三数字卡（spec §四；疼痛率/准时率浅粉、亲密淡蓝）

    @ViewBuilder
    private func statCards(couple: CDCouple, history: [CDCycle], range: DateInterval) -> some View {
        HStack(spacing: 8) {
            statCard(label: "疼痛率", value: percentText(painRate(history: history, range: range)),
                    background: DS.rosePale, valueColor: DS.roseCycle)
            statCard(label: "准时率", value: percentText(onTimeRate(history: history, range: range)),
                    background: DS.rosePale, valueColor: DS.roseCycle)
            statCard(label: "亲密", value: "\(intimacyCount(couple: couple, range: range)) 次",
                    background: DS.bandBlue, valueColor: DS.actionBlue)
        }
    }

    private func statCard(label: String, value: String, background: Color, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).dsFootnote()
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(background))
    }

    /// 疼痛率输入=范围内（按 log.day 落在范围）所有 dayLog 的 painRaw
    private func painRate(history: [CDCycle], range: DateInterval) -> Double? {
        var raws: [Int16] = []
        for cycle in history {
            for log in (cycle.dayLogs as? Set<CDCycleDayLog>) ?? [] {
                guard let day = log.day, inRange(day, range) else { continue }
                raws.append(log.painRaw)
            }
        }
        return CycleStats.painRate(painRaws: raws)
    }

    /// 准时率输入=开始日落在范围且已结束周期的 CyclePredictor.deviationDays
    private func onTimeRate(history: [CDCycle], range: DateInterval) -> Double? {
        var deviations: [Int?] = []
        for cycle in history {
            guard let start = cycle.startDate, inRange(start, range), cycle.endDate != nil else { continue }
            deviations.append(CyclePredictor.deviationDays(predictedAtLogging: cycle.predictedStartAtLogging,
                                                            actualStart: start, calendar: cal))
        }
        return CycleStats.onTimeRate(deviations: deviations)
    }

    /// 亲密=happenedAt 落在范围条数
    private func intimacyCount(couple: CDCouple, range: DateInterval) -> Int {
        ((couple.intimacyRecords as? Set<CDIntimacyRecord>) ?? [])
            .filter { $0.happenedAt.map { inRange($0, range) } ?? false }
            .count
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    // MARK: 历史周期列表（spec §四；主页删除后安置于此；不随分段/范围过滤）

    @ViewBuilder
    private func historySection(_ history: [CDCycle]) -> some View {
        Text("历史周期").dsSectionTitle()
        if history.isEmpty {
            Text("还没有历史周期记录").dsCaption()
                .frame(maxWidth: .infinity).padding(.top, 24)
        } else {
            ForEach(history, id: \.objectID) { cycle in
                SwipeDeleteRow(id: cycle.objectID, openID: $openSwipeID) {
                    pendingDelete = cycle
                } content: {
                    Button { sheetMode = .edit(cycle) } label: { historyRow(cycle) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyRow(_ cycle: CDCycle) -> some View {
        HStack {
            Text(rangeText(cycle)).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
            Spacer()
            badge(cycle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
        .contentShape(Rectangle())
    }

    private func rangeText(_ cycle: CDCycle) -> String {
        guard let start = cycle.startDate else { return "" }
        let endText = cycle.endDate.map { Fmt.monthDay.string(from: $0) } ?? "进行中"
        return "\(Fmt.monthDay.string(from: start)) – \(endText)"
    }

    /// 偏差徽标（spec §四）：准时(绿)/推迟 n 天(橙)/早来 n 天(橙)/—(灰，补录无预测值)；±0 判准时
    private func badge(_ cycle: CDCycle) -> some View {
        let dev = cycle.startDate.flatMap {
            CyclePredictor.deviationDays(predictedAtLogging: cycle.predictedStartAtLogging,
                                         actualStart: $0, calendar: cal)
        }
        let (text, color): (String, Color) = {
            guard let dev else { return ("—", DS.inkMuted) }
            if dev == 0 { return ("准时", DS.dsGreen) }
            if dev > 0 { return ("推迟 \(dev) 天", DS.dsOrange) }
            return ("早来 \(-dev) 天", DS.dsOrange)
        }()
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }
}

// MARK: - 修改起止 / 补录一段

/// 控制方裁定：已结束的段两个 DatePicker 都必填；进行中的段只给开始日一个 DatePicker，
/// 保存时 end 传 nil 维持进行中——不提供把结束日清空、造双进行中的路径。
private enum RangeSheetMode: Identifiable {
    case edit(CDCycle)
    case backfill

    var id: String {
        switch self {
        case .edit(let cycle): return cycle.objectID.uriRepresentation().absoluteString
        case .backfill: return "backfill"
        }
    }

    var isOngoingEdit: Bool {
        if case .edit(let cycle) = self { return cycle.endDate == nil }
        return false
    }

    var title: String {
        switch self {
        case .edit: return "修改起止"
        case .backfill: return "补录一段"
        }
    }
}

private struct CycleRangeSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    let mode: RangeSheetMode
    let calendar: Calendar

    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Calendar.current.startOfDay(for: Date())
    @State private var loaded = false
    @State private var overlapMessage: String?

    private var repo: CycleRepository { CycleRepository(context: context) }

    var body: some View {
        NavigationStack {
            ScrollView {
                GroupedSection {
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    if !mode.isOngoingEdit {
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        DatePicker("结束日期", selection: $end, displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
        }
        .presentationDetents([.medium])
        .alert("不能这样记", isPresented: Binding(get: { overlapMessage != nil },
                                             set: { if !$0 { overlapMessage = nil } })) {
            Button("好") { overlapMessage = nil }
        } message: { Text(overlapMessage ?? "") }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let cycle) = mode {
            start = cycle.startDate ?? start
            end = cycle.endDate ?? start
        }
    }

    private func save() {
        do {
            switch mode {
            case .edit(let cycle):
                try repo.updateRange(cycle, start: start, end: mode.isOngoingEdit ? nil : end,
                                     calendar: calendar)
            case .backfill:
                _ = try repo.backfill(couple: couple, start: start, end: end,
                                      today: Date(), calendar: calendar)
            }
            dismiss()
        } catch { showError(error) }
    }

    /// 同 CycleDaySheet.showCycleError 文案规则（T4）
    private func showError(_ error: Error) {
        if case CycleRepository.CycleError.overlap(let s, let e) = error {
            let endText = e.map { Fmt.monthDay.string(from: $0) } ?? "进行中"
            overlapMessage = "和 \(Fmt.monthDay.string(from: s)) – \(endText) 那段重叠了"
        } else if case CycleRepository.CycleError.endBeforeStart = error {
            overlapMessage = "结束不能早于开始"
        } else {
            overlapMessage = "这样记不进去，检查一下日期"
        }
    }
}
