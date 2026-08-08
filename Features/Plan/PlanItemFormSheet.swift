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
                            try? PlanItemRepository(context: context).delete(item)
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
    }

    private func save() {
        let repo = PlanItemRepository(context: context)
        let dayValue = hasDay ? day : nil
        let timeValue = (hasDay && hasTime) ? time : nil
        let noteValue = note.isEmpty ? nil : note
        let placeValue = placeText.isEmpty ? nil : placeText
        if let item {
            try? repo.update(item, day: dayValue, time: timeValue, title: title,
                             note: noteValue, placeText: placeValue, remindAt: item.remindAt)
        } else {
            let couples = CoupleRepository(context: context)
            let authorID = (try? couples.fetchCouple()).flatMap { couples.currentPartnerID(of: $0) }
            _ = try? repo.add(to: meeting, day: dayValue, time: timeValue, title: title,
                              note: noteValue, placeText: placeValue, authorID: authorID)
        }
        dismiss()
    }
}
