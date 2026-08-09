import SwiftUI

struct PlanItemFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    let item: CDPlanItem?

    @State private var title = ""
    @State private var note = ""
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locationCategoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var showPlacePicker = false
    @State private var hasDay = false
    @State private var moment = Date()
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
                            DatePicker("日期", selection: $moment, displayedComponents: .date)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker("时刻", selection: $moment, displayedComponents: .hourAndMinute)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                        Toggle("提醒我", isOn: Binding(
                            get: { remindOn },
                            set: { newValue in
                                withAnimation {
                                    remindOn = newValue
                                    if newValue { remindDate = defaultRemindDate() }
                                }
                            }))
                            .padding(.horizontal, 14).padding(.vertical, 6)
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
                        Button {
                            showPlacePicker = true
                        } label: {
                            HStack {
                                Text("地点").dsBody()
                                Spacer()
                                Text(locationName.isEmpty ? "可跳过 ›" : locationName)
                                    .dsCaption().lineLimit(1)
                                if !locationName.isEmpty {
                                    Button {
                                        locationName = ""; coords = nil
                                        locationCategoryRaw = 0; linkedPlaceID = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 13)).foregroundStyle(DS.chipBorder)
                                    }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        }
                        .buttonStyle(.plain)
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
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerSheet(initial: coords.map {
                    PickedPlace(name: locationName, latitude: $0.0, longitude: $0.1,
                                categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
                } ?? (locationName.isEmpty ? nil
                      : PickedPlace(name: locationName, latitude: 0, longitude: 0,
                                    categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID))) { picked in
                    locationName = picked.name
                    coords = (picked.latitude, picked.longitude)
                    locationCategoryRaw = picked.categoryRaw
                    linkedPlaceID = picked.existingPlaceID
                }
            }
        }
    }

    private func loadIfEditing() {
        guard let item else { return }
        title = item.title ?? ""
        note = item.note ?? ""
        if let place = item.place {
            // 已关联真地点：预填全量，改选/清除都走选点页
            locationName = place.name ?? ""
            if place.latitude != 0 || place.longitude != 0 {
                coords = (place.latitude, place.longitude)
            }
            locationCategoryRaw = place.categoryRaw
            linkedPlaceID = place.id
        } else {
            locationName = item.placeText ?? ""   // 旧数据的手输文字照常显示
        }
        if let d = item.day {
            hasDay = true
            if let t = item.time {
                moment = t
            } else {
                // 旧全天编辑预填 9:00
                let cal = Calendar.current
                moment = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
            }
        }
        if let r = item.remindAt { remindOn = true; remindDate = r }
    }

    private func defaultRemindDate() -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: moment) ?? Date()
    }

    private func save() {
        let repo = PlanItemRepository(context: context)
        let momentValue = hasDay ? moment : nil
        let dayValue = momentValue
        let timeValue = momentValue
        let noteValue = note.isEmpty ? nil : note
        let remindValue: Date? = remindOn ? remindDate : nil
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        // 反馈⑦ 1A：地点走选点归并（与记忆/小本本同管线）；placeText 同步写名字兼容旧展示
        var place: CDPlace?
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespaces)
        if !trimmedLocation.isEmpty {
            let picked = PickedPlace(name: trimmedLocation,
                                     latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                     categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
            place = PlaceResolver.resolve(picked, context: context, couple: couple)
        }
        let placeValue = trimmedLocation.isEmpty ? nil : trimmedLocation
        var savedItem: CDPlanItem?
        if let item {
            try? repo.update(item, day: dayValue, time: timeValue, title: title,
                             note: noteValue, placeText: placeValue, remindAt: remindValue,
                             place: place)
            savedItem = item
        } else {
            let authorID = couple.flatMap { couples.currentPartnerID(of: $0) }
            savedItem = try? repo.add(to: meeting, day: dayValue, time: timeValue, title: title,
                                      note: noteValue, placeText: placeValue, authorID: authorID,
                                      remindAt: remindValue, place: place)
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
