import SwiftUI
import CoreData

enum CycleSheetSegment: Hashable { case period, intimacy }

struct SelectedCycleDay: Identifiable, Equatable {
    let id: Date
    var segment: CycleSheetSegment = .period
}

/// 点日期弹出的记录卡（spec §二）：生理期五态状态机 + 亲密段
struct CycleDaySheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let couple: CDCouple
    let selection: SelectedCycleDay
    @FetchRequest(sortDescriptors: []) private var cycles: FetchedResults<CDCycle>
    @FetchRequest(sortDescriptors: []) private var intimacyAll: FetchedResults<CDIntimacyRecord>
    // 点选档位改的是 CDCycleDayLog 的字段：不观察它，二次点选（update 不碰 CDCycle）不刷新，
    // 视觉上就是「只有第一下会亮」（首次点选是 insert，恰好碰到 cycle.dayLogs 关系才刷）
    @FetchRequest(sortDescriptors: []) private var dayLogsAll: FetchedResults<CDCycleDayLog>

    @State private var segment: CycleSheetSegment = .period
    @State private var note = ""
    @State private var intimacyProtected = true
    @State private var intimacyNote = ""
    @State private var intimacyTime = Date()
    @State private var editingIntimacy: CDIntimacyRecord?
    @State private var overlapMessage: String?
    @State private var confirmDeleteIntimacy: CDIntimacyRecord?
    @State private var loaded = false

    private var day: Date { selection.id }
    private var repo: CycleRepository { CycleRepository(context: context) }
    private var cal: Calendar { .current }

    var body: some View {
        let _ = (cycles.count, intimacyAll.count, dayLogsAll.count)   // 注册刷新
        let containing = repo.cycle(containing: day, couple: couple, calendar: cal)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    Picker("", selection: $segment) {
                        Text("生理期").tag(CycleSheetSegment.period)
                        Text("亲密活动").tag(CycleSheetSegment.intimacy)
                    }
                    .pickerStyle(.segmented)
                    if segment == .period {
                        periodSection(containing: containing)
                    } else {
                        intimacySection
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.canvas)
            .navigationTitle(Fmt.monthDay.string(from: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("不能这样记", isPresented: Binding(get: { overlapMessage != nil },
                                             set: { if !$0 { overlapMessage = nil } })) {
            Button("好") { overlapMessage = nil }
        } message: { Text(overlapMessage ?? "") }
        .alert("删除这条记录？", isPresented: Binding(get: { confirmDeleteIntimacy != nil },
                                               set: { if !$0 { confirmDeleteIntimacy = nil } })) {
            Button("删除", role: .destructive) {
                if let record = confirmDeleteIntimacy {
                    try? repo.deleteIntimacy(record)
                }
                confirmDeleteIntimacy = nil
            }
            Button("取消", role: .cancel) { confirmDeleteIntimacy = nil }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            segment = selection.segment
            if !cal.isDate(day, inSameDayAs: Date()) {
                intimacyTime = cal.date(bySettingHour: 12, minute: 0, second: 0,
                                        of: cal.startOfDay(for: day)) ?? Date()
            }
            if let c = repo.cycle(containing: day, couple: couple, calendar: cal),
               let log = repo.dayLog(in: c, day: day, calendar: cal) {
                note = log.note ?? ""
            }
        }
    }

    // MARK: 生理期段（spec §二 五态）

    @ViewBuilder
    private func periodSection(containing: CDCycle?) -> some View {
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: day)
        let ongoing = repo.ongoing(couple: couple)
        if target > today {
            Text("未来的日子只能看预测").dsCaption()
                .frame(maxWidth: .infinity).padding(.top, 24)
        } else if let cycle = containing {
            inPeriodBody(cycle: cycle)
        } else if let ongoing, let start = ongoing.startDate, start < target {
            Button("这天经期结束") { endCycle(ongoing) }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
            Text("经期从 \(Fmt.monthDay.string(from: start)) 开始").dsFootnote()
        } else if ongoing != nil {
            Text("要补过去的经期，去统计页「补录一段」").dsCaption()
                .frame(maxWidth: .infinity).padding(.top, 24)
        } else {
            Button("这天经期开始") { startCycle() }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
        }
    }

    @ViewBuilder
    private func inPeriodBody(cycle: CDCycle) -> some View {
        let dayIndex = (cal.dateComponents([.day], from: cycle.startDate ?? day,
                                           to: cal.startOfDay(for: day)).day ?? 0) + 1
        let log = repo.dayLog(in: cycle, day: day, calendar: cal)
        Text("经期第 \(dayIndex) 天")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.roseCycle)
        levelRow(title: "疼痛", labels: CycleLevels.pain, value: log?.painRaw ?? 0) { newRaw in
            saveLog(cycle: cycle, pain: newRaw, flow: log?.flowRaw ?? 0, color: log?.colorRaw ?? 0)
        }
        levelRow(title: "流量", labels: CycleLevels.flow, value: log?.flowRaw ?? 0) { newRaw in
            saveLog(cycle: cycle, pain: log?.painRaw ?? 0, flow: newRaw, color: log?.colorRaw ?? 0)
        }
        levelRow(title: "颜色", labels: CycleLevels.color, value: log?.colorRaw ?? 0) { newRaw in
            saveLog(cycle: cycle, pain: log?.painRaw ?? 0, flow: log?.flowRaw ?? 0, color: newRaw)
        }
        TextField("备注（可选）", text: $note, axis: .vertical)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
            .onChange(of: note) { _, _ in
                saveLog(cycle: cycle, pain: log?.painRaw ?? 0,
                        flow: log?.flowRaw ?? 0, color: log?.colorRaw ?? 0)
            }
        if cycle.endDate == nil, cal.startOfDay(for: day) >= (cycle.startDate ?? day) {
            Button("这天经期结束") { endCycle(cycle) }
                .buttonStyle(GhostPillButtonStyle())
        }
    }

    /// 一排三档：点选即存，再点取消（raw 1/2/3，红黄绿=重中轻反向 index）
    private func levelRow(title: String, labels: [String], value: Int16,
                          onPick: @escaping (Int16) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).dsFootnote()
            HStack(spacing: 8) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    let raw = Int16(i + 1)
                    let tint: Color = [DS.dsGreen, DS.dsOrange, DS.dsRed][i]
                    let selected = value == raw
                    Button {
                        onPick(selected ? 0 : raw)     // 再点取消
                    } label: {
                        Text(label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selected ? .white : tint)
                            .padding(.vertical, 6).padding(.horizontal, 16)
                            .background(Capsule().fill(selected ? tint : .clear))
                            .overlay(Capsule().stroke(tint, lineWidth: 1))
                    }
                    .buttonStyle(DSPressEffect())
                }
            }
        }
    }

    private func saveLog(cycle: CDCycle, pain: Int16, flow: Int16, color: Int16) {
        try? repo.setDayLog(in: cycle, day: day, painRaw: pain, flowRaw: flow,
                            colorRaw: color, note: note.isEmpty ? nil : note, calendar: cal)
    }

    private func startCycle() {
        let inputs = repo.cyclesSorted(couple: couple).compactMap { c -> (Date, Date?)? in
            c.startDate.map { ($0, c.endDate) }
        }
        let predicted = inputs.isEmpty ? nil
            : CyclePredictor.predict(cycles: inputs, calendar: cal).nextStarts.first
        do {
            _ = try repo.start(couple: couple, on: day, predictedStart: predicted,
                               today: Date(), calendar: cal)
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: "cycleStartLoggedAt")     // 早来 2h 窗（本机，spec §五）
        } catch { showCycleError(error) }
    }

    private func endCycle(_ cycle: CDCycle) {
        do { try repo.end(cycle, on: day, calendar: cal) } catch { showCycleError(error) }
    }

    private func showCycleError(_ error: Error) {
        if case CycleRepository.CycleError.overlap(let s, let e) = error {
            let endText = e.map { Fmt.monthDay.string(from: $0) } ?? "进行中"
            overlapMessage = "和 \(Fmt.monthDay.string(from: s)) – \(endText) 那段重叠了"
        } else if case CycleRepository.CycleError.endBeforeStart = error {
            overlapMessage = "结束不能早于开始"
        } else {
            overlapMessage = "这样记不进去，检查一下日期"
        }
    }

    // MARK: 亲密段（spec §二；未来天只看预测，不给表单）

    @ViewBuilder
    private var intimacySection: some View {
        let today = cal.startOfDay(for: Date())
        if cal.startOfDay(for: day) > today {
            Text("未来的日子只能看预测").dsCaption()
                .frame(maxWidth: .infinity).padding(.top, 24)
        } else {
            let records = repo.intimacy(on: day, couple: couple, calendar: cal)
            ForEach(records, id: \.objectID) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.happenedAt.map { Fmt.hm.string(from: $0) } ?? "").dsBody()
                        Text(record.protectionUsed?.boolValue == true ? "有措施" : "无措施").dsFootnote()
                        if let n = record.note, !n.isEmpty { Text(n).dsFootnote() }
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        Button("编辑") { startEditingIntimacy(record) }
                            .font(.system(size: 14)).foregroundStyle(DS.actionBlue)
                        Button("删除") { confirmDeleteIntimacy = record }
                            .font(.system(size: 14)).foregroundStyle(DS.dsRed)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.parchment))
            }
            Toggle("有措施", isOn: $intimacyProtected).dsBody()
            DatePicker("时刻", selection: $intimacyTime, displayedComponents: .hourAndMinute)
                .dsBody()
            TextField("备注（可选）", text: $intimacyNote, axis: .vertical)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
            Button(editingIntimacy == nil ? "保存" : "保存修改") { saveIntimacy() }
                .buttonStyle(BluePillButtonStyle(fullWidth: true))
            if editingIntimacy != nil {
                Button("取消") { cancelEditingIntimacy() }
                    .font(.system(size: 13)).foregroundStyle(DS.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func startEditingIntimacy(_ record: CDIntimacyRecord) {
        editingIntimacy = record
        intimacyProtected = record.protectionUsed?.boolValue ?? true
        intimacyNote = record.note ?? ""
        if let at = record.happenedAt { intimacyTime = at }
    }

    /// 时刻选择器的时分落在所点日上（编辑用）
    private func combinedTime() -> Date {
        let hm = cal.dateComponents([.hour, .minute], from: intimacyTime)
        return cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0,
                        second: 0, of: cal.startOfDay(for: day)) ?? intimacyTime
    }

    private func cancelEditingIntimacy() {
        editingIntimacy = nil
        intimacyNote = ""
    }

    /// 编辑态=updateIntimacy 改既有条；非编辑态=addIntimacy 新增（行为不变）
    private func saveIntimacy() {
        if let record = editingIntimacy {
            try? repo.updateIntimacy(record, protected: intimacyProtected,
                                     note: intimacyNote.isEmpty ? nil : intimacyNote,
                                     happenedAt: combinedTime())
            editingIntimacy = nil
        } else {
            try? repo.addIntimacy(couple: couple, day: day,
                                  protected: intimacyProtected,
                                  note: intimacyNote.isEmpty ? nil : intimacyNote,
                                  now: Date(), calendar: cal, time: intimacyTime)
        }
        intimacyNote = ""
    }
}
