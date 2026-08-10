import SwiftUI
import CoreData

enum TodoFormMode {
    case create(CDCouple)
    case edit(CDTodoItem)
}

/// 记得做表单（spec ⑥ §二，结构照 QuickLedgerSheet 的 NavigationStack+GroupedSection 模式）：
/// Ta做|我做分段、私密开关（T4 同款）、提醒行（本地通知）。
struct TodoFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: TodoFormMode

    @State private var assigneeIsMe = false   // 默认 Ta做
    @State private var title = ""
    @State private var detail = ""
    @State private var dueAt = Date()
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locationCategoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var showPlacePicker = false
    @State private var remindOn = false
    @State private var remindAt = Date()
    @State private var confirmReveal = false
    @State private var confirmDelete = false
    @State private var loaded = false

    private var coupleRepo: CoupleRepository { CoupleRepository(context: context) }

    /// create 取字面量 couple；edit 走条目自己的关系（照 mode 取值，spec ⑥ §二）
    private var couple: CDCouple? {
        switch mode {
        case .create(let couple): return couple
        case .edit(let todo): return todo.couple
        }
    }

    private var editingTodo: CDTodoItem? {
        if case .edit(let todo) = mode { return todo }
        return nil
    }

    /// 已公开条目：可见性锁定「公开」（同小本本 spec §三）
    private var visibilityLocked: Bool {
        guard let todo = editingTodo else { return false }
        return LedgerRules.isRevealed(visibilityRaw: todo.visibilityRaw, revealedAt: todo.revealedAt)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: 8) {
                        assigneeButton(isMe: false, label: "Ta做")
                        assigneeButton(isMe: true, label: "我做")
                    }

                    GroupedSection {
                        TextField("要做什么", text: $title)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        TextField("详情（可选）", text: $detail)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                    }

                    GroupedSection {
                        DatePicker("目标日", selection: $dueAt, displayedComponents: .date)
                            .padding(.horizontal, 14).padding(.vertical, 6)
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
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        Toggle("私密", isOn: Binding(
                            get: { visibility == .privateUntilRevealed },
                            set: { newValue in
                                // 编辑中把已私密条目关成公开＝一次性公开仪式，先确认（spec §三/§二）
                                if !newValue, editingTodo != nil, !visibilityLocked,
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
                         : "开着=公开前只有你看得到")
                        .dsFootnote().padding(.horizontal, 4)

                    GroupedSection {
                        Toggle("提醒我", isOn: Binding(
                            get: { remindOn },
                            set: { newValue in
                                remindOn = newValue
                                if newValue { remindAt = defaultRemindAt() }   // 开启瞬间默认=目标日 09:00
                            }))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                        if remindOn {
                            DS.hairline.frame(height: 1).padding(.leading, 14)
                            DatePicker("提醒时刻", selection: $remindAt,
                                      displayedComponents: [.date, .hourAndMinute])
                                .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }
                    Text("提醒只响在设置它的手机上").dsFootnote().padding(.horizontal, 4)

                    if editingTodo != nil {
                        GroupedSection {
                            Button { confirmDelete = true } label: {
                                Text("删除这条").dsBody()
                                    .foregroundStyle(DS.dsRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                            }
                            .buttonStyle(DSPressEffect())
                        }
                    }
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(editingTodo == nil ? "待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
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
            .alert("公开给 TA？", isPresented: $confirmReveal) {
                Button("公开") { visibility = .sharedImmediately }
                Button("取消", role: .cancel) {}
            } message: {
                Text("公开后 TA 会看到这条，且不可撤回。")
            }
            .alert("删除这条待办？", isPresented: $confirmDelete) {
                Button("删除", role: .destructive) { delete() }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func assigneeButton(isMe: Bool, label: String) -> some View {
        Button {
            assigneeIsMe = isMe
        } label: {
            Text(label)
                .font(.system(size: 14, weight: assigneeIsMe == isMe ? .semibold : .regular))
                .foregroundStyle(assigneeIsMe == isMe ? DS.actionBlue : DS.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(assigneeIsMe == isMe ? DS.actionBlue : DS.chipBorder,
                            lineWidth: assigneeIsMe == isMe ? 1.5 : 1))
        }
        .buttonStyle(DSPressEffect())
    }

    private func defaultRemindAt() -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: cal.startOfDay(for: dueAt)) ?? dueAt
    }

    private func loadIfNeeded() {
        guard !loaded, let todo = editingTodo else { return }
        loaded = true
        title = todo.title ?? ""
        detail = todo.detail ?? ""
        dueAt = todo.dueAt ?? Date()
        // 同小本本表单：锁定态强制显示「公开」（reveal 不改 visibilityRaw）
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: todo.visibilityRaw) ?? .sharedImmediately)
        if let place = todo.place {
            locationName = place.name ?? ""
            coords = (place.latitude, place.longitude)
            locationCategoryRaw = place.categoryRaw
            linkedPlaceID = place.id
        }
        if let couple, let myID = coupleRepo.currentPartnerID(of: couple) {
            assigneeIsMe = todo.assigneePartnerID == myID
        }
        if let existingRemindAt = todo.remindAt {
            remindOn = true
            remindAt = existingRemindAt
        }
    }

    private func delete() {
        guard let todo = editingTodo else { dismiss(); return }
        let id = todo.id
        try? TodoRepository(context: context).delete(todo)
        if let id { ReminderScheduler.cancel(id: ReminderPlanner.todoID(id)) }
        dismiss()
    }

    private func save() {
        guard let couple else { dismiss(); return }
        let repo = TodoRepository(context: context)
        let cal = Calendar.current
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespaces)
        let myID = coupleRepo.currentPartnerID(of: couple)
        let otherID = coupleRepo.otherPartner(of: couple)?.id
        let assigneeID = assigneeIsMe ? myID : otherID

        var place: CDPlace?
        if !locationName.trimmingCharacters(in: .whitespaces).isEmpty {
            let picked = PickedPlace(name: locationName.trimmingCharacters(in: .whitespaces),
                                     latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                     categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
            place = PlaceResolver.resolve(picked, context: context, couple: couple)
        }

        let remindDate: Date? = remindOn ? remindAt : nil
        var savedTodo: CDTodoItem?

        switch mode {
        case .create:
            savedTodo = try? repo.create(couple: couple, title: trimmedTitle,
                                         detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
                                         dueAt: dueAt, assigneeID: assigneeID, authorID: myID,
                                         visibility: visibility, place: place, remindAt: remindDate,
                                         calendar: cal)
        case .edit(let todo):
            try? repo.update(todo, title: trimmedTitle,
                             detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
                             dueAt: dueAt, assigneeID: assigneeID, place: place,
                             remindAt: remindDate, calendar: cal)
            // 编辑私密条目改公开 = 等效公开动作（spec §三，与私密 Toggle 确认弹窗配套）
            if !visibilityLocked, visibility == .sharedImmediately,
               todo.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                try? repo.reveal(todo, at: Date())
            }
            savedTodo = todo
        }

        if let id = savedTodo?.id {
            let key = ReminderPlanner.todoID(id)
            // 完成的事项不该再响（P6-B3，堵「勾掉后编辑保存复活提醒」）
            if remindOn, ReminderPlanner.shouldSchedule(remindAt: remindDate,
                                                        isDone: savedTodo?.isDone == true, now: Date()) {
                ReminderScheduler.schedule(id: key, title: trimmedTitle,
                                           body: trimmedDetail.isEmpty ? "待办" : trimmedDetail,
                                           at: remindAt)
            } else {
                ReminderScheduler.cancel(id: key)
            }
        }
        dismiss()
    }
}
