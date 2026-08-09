import SwiftUI

enum PlanFormMode { case schedule, memo }

struct PlanItemFormSheet: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let meeting: CDMeeting
    let item: CDPlanItem?
    let initialMode: PlanFormMode?

    @State private var title = ""
    @State private var note = ""
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locationCategoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var showPlacePicker = false
    @State private var formMode: PlanFormMode = .schedule
    @State private var moment = Date()
    @State private var remindOn = false
    @State private var remindDate = Date()

    init(meeting: CDMeeting, item: CDPlanItem?, initialMode: PlanFormMode? = nil) {
        self.meeting = meeting
        self.item = item
        self.initialMode = initialMode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.md) {
                    Picker("", selection: $formMode.animation()) {
                        Text("日程").tag(PlanFormMode.schedule)
                        Text("备忘").tag(PlanFormMode.memo)
                    }
                    .pickerStyle(.segmented)
                    GroupedSection {
                        HStack {
                            Text("事项").dsBody()
                            TextField(formMode == .memo ? "如 带伞" : "如 G102 高铁", text: $title)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        if formMode == .schedule {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker("时刻", selection: $moment)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            DS.hairline.frame(height: 1).padding(.leading, 14)
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
                    }
                    GroupedSection {
                        HStack {
                            Text("备注").dsBody()
                            TextField("可选", text: $note).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        if formMode == .schedule {
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
            .navigationTitle(item == nil ? (formMode == .memo ? "添加备忘" : "添加日程") : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                formMode = initialMode ?? ((item?.day == nil && item != nil) ? .memo : .schedule)
                loadIfEditing()
            }
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
            let cal = Calendar.current
            if let t = item.time {
                // 旧有时间数据：合成 day 的年月日 + time 的时分
                var comps = cal.dateComponents([.year, .month, .day], from: d)
                let tc = cal.dateComponents([.hour, .minute], from: t)
                comps.hour = tc.hour
                comps.minute = tc.minute
                moment = cal.date(from: comps) ?? d
            } else {
                // 旧全天编辑预填 9:00
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
        let isMemo = formMode == .memo
        let dayValue: Date? = isMemo ? nil : moment
        let timeValue: Date? = isMemo ? nil : moment
        let noteValue = note.isEmpty ? nil : note
        let remindValue: Date? = (!isMemo && remindOn) ? remindDate : nil
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        // 反馈⑦ 1A：地点走选点归并（与记忆/小本本同管线）；placeText 同步写名字兼容旧展示
        // 反馈⑨T1修：备忘模式表单没有地点行，place/placeText 原样透传不改
        // （编辑=保留 item 原有关系，新建=nil），避免旧「day=nil 但已填地点」计划项
        // 一保存（哪怕只是改错别字）就被静默清空地点；日程模式仍走现有 PlaceResolver 逻辑
        var place: CDPlace?
        var placeValue: String?
        let trimmedLocation = locationName.trimmingCharacters(in: .whitespaces)
        if isMemo {
            place = item?.place
            placeValue = item?.placeText
        } else if !trimmedLocation.isEmpty {
            let picked = PickedPlace(name: trimmedLocation,
                                     latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                     categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
            place = PlaceResolver.resolve(picked, context: context, couple: couple)
            placeValue = trimmedLocation
        }
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
        // 备忘模式 remindValue 恒为 nil → shouldSchedule(remindAt: nil, ...) 恒 false →
        // 下面必然落到 else 分支 cancel(取消原提醒)。这里没有显式写 isMemo 分支，
        // 是刻意依赖这条隐式链条；以后改这段逻辑时别把它改没了，否则备忘会漏取消提醒。
        if let id = savedItem?.id {
            let key = ReminderPlanner.planID(id)
            // 完成的事项不该再响（P6-B3，堵「勾掉后编辑保存复活提醒」）
            if remindOn, ReminderPlanner.shouldSchedule(remindAt: remindValue,
                                                        isDone: savedItem?.isDone == true, now: Date()) {
                ReminderScheduler.schedule(id: key, title: title,
                                           body: "行前日程", at: remindDate)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
        dismiss()
    }
}
