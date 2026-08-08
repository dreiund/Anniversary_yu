import SwiftUI

struct PlanItemFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    let item: CDPlanItem?

    @State private var title = ""
    @State private var note = ""
    @State private var placeText = ""
    @State private var hasDay = false
    @State private var day = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var remindOn = false
    @State private var remindDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    GroupedSection {
                        HStack {
                            Text("事项").dsBody()
                            TextField("如 G102 高铁", text: $title).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        Toggle("指定日期", isOn: $hasDay.animation())
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        if hasDay {
                            DatePicker("日期", selection: $day, displayedComponents: .date)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            Toggle("指定时间", isOn: $hasTime.animation())
                                .padding(.horizontal, 14).padding(.vertical, 8)
                            if hasTime {
                                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                            }
                        }
                        Toggle("提醒我", isOn: $remindOn.animation())
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .onChange(of: remindOn) { _, newValue in
                                if newValue { remindDate = defaultRemindDate() }
                            }
                        if remindOn {
                            DatePicker("提醒时刻", selection: $remindDate)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            Text("提醒只响在设置它的手机上").dsFootnote()
                                .padding(.horizontal, 14).padding(.bottom, 6)
                        }
                    }
                    GroupedSection {
                        HStack {
                            Text("备注").dsBody()
                            TextField("可选", text: $note).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        HStack {
                            Text("地点").dsBody()
                            TextField("可选，如 湖滨路店", text: $placeText).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    if let item {
                        Button("删除此项") {
                            let id = item.id
                            try? PlanItemRepository(context: context).delete(item)
                            if let id { ReminderScheduler.cancel(id: ReminderPlanner.planID(id)) }
                            dismiss()
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(DS.dsRed)
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(item == nil ? "添加日程" : "编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    private func loadIfEditing() {
        guard let item else { return }
        title = item.title ?? ""
        note = item.note ?? ""
        placeText = item.placeText ?? ""
        if let d = item.day { hasDay = true; day = d }
        if let t = item.time { hasTime = true; time = t }
        if let r = item.remindAt { remindOn = true; remindDate = r }
    }

    private func defaultRemindDate() -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? Date()
    }

    private func save() {
        let repo = PlanItemRepository(context: context)
        let dayValue = hasDay ? day : nil
        let timeValue = (hasDay && hasTime) ? time : nil
        let noteValue = note.isEmpty ? nil : note
        let placeValue = placeText.isEmpty ? nil : placeText
        let remindValue: Date? = remindOn ? remindDate : nil
        var savedItem: CDPlanItem?
        if let item {
            try? repo.update(item, day: dayValue, time: timeValue, title: title,
                             note: noteValue, placeText: placeValue, remindAt: remindValue)
            savedItem = item
        } else {
            let couples = CoupleRepository(context: context)
            let authorID = (try? couples.fetchCouple()).flatMap { couples.currentPartnerID(of: $0) }
            savedItem = try? repo.add(to: meeting, day: dayValue, time: timeValue, title: title,
                                      note: noteValue, placeText: placeValue, authorID: authorID,
                                      remindAt: remindValue)
        }
        if let id = savedItem?.id {
            let key = ReminderPlanner.planID(id)
            if remindOn, ReminderPlanner.shouldSchedule(remindAt: remindValue, now: Date()) {
                ReminderScheduler.schedule(id: key, title: title,
                                           body: "行前日程", at: remindDate)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
        dismiss()
    }
}
