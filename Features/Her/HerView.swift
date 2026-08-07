import SwiftUI
import CoreData

/// 「记录·她」主页（spec §一）：横幅 + 粉卡双态 + 整月滑动月历，到日历为止
struct HerView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var couples: FetchedResults<CDCouple>
    @FetchRequest(sortDescriptors: []) private var cycles: FetchedResults<CDCycle>
    @FetchRequest(sortDescriptors: []) private var dayLogs: FetchedResults<CDCycleDayLog>
    @FetchRequest(sortDescriptors: []) private var intimacyAll: FetchedResults<CDIntimacyRecord>
    @FetchRequest(sortDescriptors: []) private var partners: FetchedResults<CDPartner>

    @State private var monthOffset = 0
    @State private var selectedDay: SelectedCycleDay?
    @State private var needsPicker = false

    private var cal: Calendar { .current }
    private var repo: CycleRepository { CycleRepository(context: context) }

    var body: some View {
        let _ = (cycles.count, dayLogs.count, intimacyAll.count, partners.count)
        if let couple = couples.first {
            content(couple)
        } else {
            Text("先完成配对").dsCaption()
        }
    }

    @ViewBuilder
    private func content(_ couple: CDCouple) -> some View {
        let inputs = repo.cyclesSorted(couple: couple).compactMap { c -> (start: Date, end: Date?)? in
            c.startDate.map { ($0, c.endDate) }
        }
        let prediction = CyclePredictor.predict(cycles: inputs, calendar: cal)
        let ongoing = repo.ongoing(couple: couple)
        let delay = prediction.nextStarts.first.flatMap {
            CyclePredictor.delayDays(nextStart: $0, hasOngoing: ongoing != nil,
                                     today: Date(), calendar: cal)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let delay {
                    Text("🕐 已推迟 \(delay) 天")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.roseCycle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.rosePale))
                }
                statusCard(couple: couple, ongoing: ongoing, prediction: prediction)
                calendarCard(couple)
            }
            .padding(DS.Spacing.md)
        }
        .background(DS.canvas)
        .navigationTitle("记录·她")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { sel in
            CycleDaySheet(couple: couple, selection: sel)
        }
        .sheet(isPresented: $needsPicker) { TrackedPickerView(couple: couple) }
        .onAppear {
            if repo.trackedPartner(couple: couple) == nil { needsPicker = true }
        }
    }

    /// 粉卡双态 + 无记录态（spec §一.3）；早来附注仅记录后 2 小时（本机时间戳）
    @ViewBuilder
    private func statusCard(couple: CDCouple, ongoing: CDCycle?, prediction: CyclePrediction) -> some View {
        HStack {
            if let ongoing, let start = ongoing.startDate {
                let n = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: Date())).day ?? 0) + 1
                VStack(alignment: .leading, spacing: 2) {
                    Text("经期第 \(n) 天")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.roseCycle)
                    if let earlyText = earlyNote(ongoing) { Text(earlyText).dsFootnote() }
                }
                Spacer()
                if let end = prediction.ongoingEnd {
                    Text("预计 \(Fmt.monthDay.string(from: end)) 结束")
                        .font(.system(size: 12)).foregroundStyle(DS.roseCycle.opacity(0.75))
                }
            } else if let next = prediction.nextStarts.first {
                let n = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                           to: cal.startOfDay(for: next)).day ?? 0
                Text("距下次预计还有 \(max(n, 0)) 天")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.roseCycle)
                Spacer()
                Text(Fmt.monthDay.string(from: next))
                    .font(.system(size: 12)).foregroundStyle(DS.roseCycle.opacity(0.75))
            } else {
                Text("还没有经期记录 · 点日历上的日期开始记").dsCaption()
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.rosePale))
    }

    private func earlyNote(_ ongoing: CDCycle) -> String? {
        guard let start = ongoing.startDate,
              let dev = CyclePredictor.deviationDays(predictedAtLogging: ongoing.predictedStartAtLogging,
                                                     actualStart: start, calendar: cal),
              dev < 0 else { return nil }
        let logged = UserDefaults.standard.double(forKey: "cycleStartLoggedAt")
        guard logged > 0, Date().timeIntervalSince1970 - logged < 7_200 else { return nil }
        return "这次早了 \(-dev) 天"
    }

    private func calendarCard(_ couple: CDCouple) -> some View {
        let anchor = cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return VStack(spacing: 8) {
            HStack {
                Button("回今天") { monthOffset = 0 }
                    .font(.system(size: 13)).foregroundStyle(DS.actionBlue)
                    .opacity(monthOffset == 0 ? 0.35 : 1)
                Spacer()
                Button { stepMonth(-1) } label: {
                    Text("‹").font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(DS.actionBlue)
                Text(monthTitle(anchor)).dsSectionTitle()
                Button { stepMonth(1) } label: {
                    Text("›").font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(DS.actionBlue)
                Spacer()
                NavigationLink { CycleStatsView() } label: {
                    Text("统计").font(.system(size: 13)).foregroundStyle(DS.actionBlue)
                }
            }
            TabView(selection: $monthOffset) {
                ForEach(-24...12, id: \.self) { offset in
                    let month = cal.date(byAdding: .month, value: offset, to: Date()) ?? Date()
                    CycleMonthGrid(anchor: month, marks: marks(for: month, couple: couple)) { day in
                        selectedDay = SelectedCycleDay(id: cal.startOfDay(for: day))
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            VStack(alignment: .leading, spacing: 2) {
                Text(legendLine1)
                Text("点：疼痛/流量/颜色（红黄绿=重中轻）· 蓝点亲密（实心有措施）")
            }
            .dsFootnote()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.darkCard).fill(DS.canvas))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.darkCard).stroke(DS.hairline, lineWidth: 1))
    }

    private var legendLine1: String {
        let inputs = couples.first.map { repo.cyclesSorted(couple: $0) }?.compactMap {
            c -> (start: Date, end: Date?)? in c.startDate.map { ($0, c.endDate) }
        } ?? []
        let base = "左右滑动换月 · 浅红=经期 · 虚线=预测 · 墨环=今天"
        return CyclePredictor.predict(cycles: inputs, calendar: cal).isDefault && !inputs.isEmpty
            ? base + " · 数据积累中" : base
    }

    /// spec §一.4：‹ › 步进（clamp 到 TabView 的 -24...12 范围，样式同统计页）
    private func stepMonth(_ delta: Int) {
        monthOffset = max(-24, min(12, monthOffset + delta))
    }

    private func monthTitle(_ anchor: Date) -> String {
        let comp = cal.dateComponents([.year, .month], from: anchor)
        return "\(comp.year ?? 0) 年 \(comp.month ?? 0) 月"
    }

    /// 该月每天的标记：经期/预测/三点/亲密（spec §一.4；预测虚线只画今天之后、且不盖实际经期）
    private func marks(for month: Date, couple: CDCouple) -> [Date: CycleDayMarks] {
        var result: [Date: CycleDayMarks] = [:]
        guard let interval = cal.dateInterval(of: .month, for: month) else { return result }
        let today = cal.startOfDay(for: Date())
        for cycle in repo.cyclesSorted(couple: couple) {
            guard let start = cycle.startDate else { continue }
            let upper = cycle.endDate ?? today
            var day = max(start, interval.start)
            while day <= min(upper, interval.end) {
                result[day, default: CycleDayMarks()].inPeriod = true
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            for log in (cycle.dayLogs as? Set<CDCycleDayLog>) ?? [] {
                guard let d = log.day, interval.contains(d) else { continue }
                result[d, default: CycleDayMarks()].painRaw = log.painRaw
                result[d, default: CycleDayMarks()].flowRaw = log.flowRaw
                result[d, default: CycleDayMarks()].colorRaw = log.colorRaw
            }
        }
        let inputs = repo.cyclesSorted(couple: couple).compactMap { c -> (start: Date, end: Date?)? in
            c.startDate.map { ($0, c.endDate) }
        }
        let prediction = CyclePredictor.predict(cycles: inputs, calendar: cal)
        for predictedStart in prediction.nextStarts {
            for i in 0..<prediction.periodLength {
                guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: predictedStart)),
                      interval.contains(day), day > today,
                      result[day]?.inPeriod != true else { continue }
                result[day, default: CycleDayMarks()].predicted = true
            }
        }
        if let couple = couples.first {
            for record in (couple.intimacyRecords as? Set<CDIntimacyRecord>) ?? [] {
                guard let at = record.happenedAt, interval.contains(at) else { continue }
                let day = cal.startOfDay(for: at)
                let unprotected = record.protectionUsed?.boolValue == false
                let existing = result[day]?.intimacy ?? .none
                result[day, default: CycleDayMarks()].intimacy =
                    (unprotected || existing == .unprotected) ? .unprotected : .protected
            }
        }
        return result
    }
}
