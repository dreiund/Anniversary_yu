import SwiftUI
import PhotosUI
import CoreData

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
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var evidencesToDelete: [CDEvidence] = []
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var confirmReveal = false

    init(meeting: CDMeeting, item: CDPlanItem?, initialMode: PlanFormMode? = nil) {
        self.meeting = meeting
        self.item = item
        self.initialMode = initialMode
    }

    private var existingEvidences: [CDEvidence] {
        guard let item else { return [] }
        return PlanItemRepository(context: context).evidencesSorted(item)
            .filter { !evidencesToDelete.contains($0) }
    }
    /// 已公开条目锁定(同小本本口径)
    private var visibilityLocked: Bool {
        guard let item else { return false }
        return LedgerRules.isRevealed(visibilityRaw: item.visibilityRaw, revealedAt: item.revealedAt)
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
                    if formMode == .schedule {
                        GroupedSection {
                            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                                HStack {
                                    Text("照片").dsBody()
                                    Spacer()
                                    Text(photoDatas.isEmpty && existingEvidences.isEmpty
                                         ? "＋ 添加" : "已有 \(existingEvidences.count + photoDatas.count) 张")
                                        .dsCaption()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 11)
                            }
                            if !existingEvidences.isEmpty || !photoDatas.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(existingEvidences, id: \.objectID) { evidence in
                                            evidenceThumb(evidence)
                                        }
                                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                                            if let ui = UIImage(data: data) {
                                                Image(uiImage: ui).resizable().scaledToFill()
                                                    .frame(width: 52, height: 52)
                                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.bottom, 11)
                                }
                            }
                        }
                    }
                    if formMode == .schedule {
                        GroupedSection {
                            Toggle("私密", isOn: Binding(
                                get: { visibility == .privateUntilRevealed },
                                set: { newValue in
                                    if !newValue, item != nil, !visibilityLocked,
                                       visibility == .privateUntilRevealed {
                                        confirmReveal = true
                                    } else {
                                        visibility = newValue ? .privateUntilRevealed : .sharedImmediately
                                    }
                                }))
                                .disabled(visibilityLocked)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                        Text(visibilityLocked
                             ? "已公开，不可改回私密"
                             : "开着=公开前只有你看得到；转化成回忆的那一刻会自动公开")
                            .dsFootnote().padding(.horizontal, 4)
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
            .onChange(of: pickerItems) {
                Task {
                    var datas: [Data] = []
                    for item in pickerItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
            .alert("公开给 TA？", isPresented: $confirmReveal) {
                Button("公开") { visibility = .sharedImmediately }
                Button("取消", role: .cancel) {}
            } message: {
                Text("公开后 TA 会看到这条日程，且不可撤回。")
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
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: item.visibilityRaw) ?? .sharedImmediately)
    }

    private func defaultRemindDate() -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: moment) ?? Date()
    }

    private func evidenceThumb(_ evidence: CDEvidence) -> some View {
        Group {
            if let data = evidence.thumbnailData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.canvas)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
        .overlay(alignment: .topTrailing) {
            Button {
                evidencesToDelete.append(evidence)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .offset(x: 4, y: -4)
        }
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
            // 编辑关私密=等效公开;既有私密日程切成备忘保存=恒公开(spec §五)
            // R18-T4 评审 Important:reveal 挪到 update 之前——两次 save 若先落 day=nil
            // 再落 revealedAt,中间会留一个「day==nil 且私密未公开」的坏态窗口(可能被
            // CloudKit 同步到对方,MemoListSheet/侧签徽标会完整渲染标题)。条件不变:
            // 读的 item.visibilityRaw/visibilityLocked/isMemo 都不受 update 影响。
            if !visibilityLocked,
               item.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue,
               isMemo || visibility == .sharedImmediately {
                try? repo.reveal(item, at: Date())
            }
            try? repo.update(item, day: dayValue, time: timeValue, title: title,
                             note: noteValue, placeText: placeValue, remindAt: remindValue,
                             place: place)
            savedItem = item
        } else {
            let authorID = couple.flatMap { couples.currentPartnerID(of: $0) }
            savedItem = try? repo.add(to: meeting, day: dayValue, time: timeValue, title: title,
                                      note: noteValue, placeText: placeValue, authorID: authorID,
                                      remindAt: remindValue, place: place,
                                      visibility: isMemo ? .sharedImmediately : visibility)
        }
        if formMode == .schedule {
            for evidence in evidencesToDelete { try? repo.deleteEvidence(evidence) }
            if !photoDatas.isEmpty, let savedItem { try? repo.addEvidences(savedItem, datas: photoDatas) }
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
                                           body: "日程", at: remindDate)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
        dismiss()
    }
}
