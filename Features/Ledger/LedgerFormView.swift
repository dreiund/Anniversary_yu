import SwiftUI
import PhotosUI
import CoreData

enum LedgerFormMode {
    case create(CDCouple)
    case edit(CDLedgerEntry)
}

/// 互评一屏滚动表单（spec §六，小样选 A）
struct LedgerFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: LedgerFormMode

    @State private var category: LedgerCategory = .praise
    @State private var title = ""
    @State private var detail = ""
    @State private var happenedAt = Date()
    @State private var visibility: EntryVisibility = .sharedImmediately
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var evidencesToDelete: [CDEvidence] = []
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locationCategoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var showPlacePicker = false
    @State private var confirmReveal = false
    @State private var loaded = false

    private var editingEntry: CDLedgerEntry? {
        if case .edit(let entry) = mode { return entry }
        return nil
    }
    /// 已公开条目：可见性锁定「公开」（spec §六）
    private var visibilityLocked: Bool {
        guard let entry = editingEntry else { return false }
        return LedgerRules.isRevealed(visibilityRaw: entry.visibilityRaw, revealedAt: entry.revealedAt)
    }
    private var existingEvidences: [CDEvidence] {
        guard let entry = editingEntry else { return [] }
        return LedgerRepository(context: context).evidencesSorted(entry)
            .filter { !evidencesToDelete.contains($0) }
    }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: 8) {
                        categoryChip(.praise, accent: DS.dsGreen)
                        categoryChip(.complaint, accent: DS.dsOrange)
                    }

                    GroupedSection {
                        HStack {
                            Text("标题").dsBody()
                            TextField("一句话概括", text: $title).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        DS.hairline.frame(height: 1).padding(.leading, 14)
                        TextField("这件事的经过和你的感受…", text: $detail, axis: .vertical)
                            .lineLimit(4...8)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                    }

                    GroupedSection {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                            HStack {
                                Text("证据照片").dsBody()
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

                    GroupedSection {
                        DatePicker("事发日期", selection: $happenedAt, displayedComponents: .date)
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
                                // 编辑中把已私密条目关成公开＝一次性公开仪式，先确认（spec §三/§六）
                                if !newValue, editingEntry != nil, !visibilityLocked,
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
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(editingEntry == nil ? "记一笔互评" : "编辑互评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
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
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func categoryChip(_ target: LedgerCategory, accent: Color) -> some View {
        Button {
            category = target
        } label: {
            Text(target.title)
                .font(.system(size: 13, weight: category == target ? .semibold : .regular))
                .foregroundStyle(category == target ? accent : DS.inkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(category == target ? accent : DS.chipBorder,
                            lineWidth: category == target ? 1.5 : 1))
        }
        .buttonStyle(DSPressEffect())
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

    private func loadIfNeeded() {
        guard !loaded, let entry = editingEntry else { return }
        loaded = true
        category = LedgerCategory(rawValue: entry.categoryRaw) ?? .praise
        title = entry.title ?? ""
        detail = entry.detail ?? ""
        happenedAt = entry.happenedAt ?? Date()
        // 经详情页仪式公开的条目 visibilityRaw 仍为私密（reveal 不碰它）——锁定态强制显示「公开」
        visibility = visibilityLocked ? .sharedImmediately
            : (EntryVisibility(rawValue: entry.visibilityRaw) ?? .sharedImmediately)
        if let place = entry.place {
            locationName = place.name ?? ""
            coords = (place.latitude, place.longitude)
            locationCategoryRaw = place.categoryRaw
            linkedPlaceID = place.id
        }
    }

    private func save() {
        let repo = LedgerRepository(context: context)
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespaces)

        var place: CDPlace?
        if !locationName.trimmingCharacters(in: .whitespaces).isEmpty {
            let picked = PickedPlace(name: locationName.trimmingCharacters(in: .whitespaces),
                                     latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                     categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
            place = PlaceResolver.resolve(picked, context: context, couple: couple)
        }

        switch mode {
        case .create(let couple):
            let authorID = couples.currentPartnerID(of: couple)
            _ = try? repo.createEntry(couple: couple, category: category, title: trimmedTitle,
                                      detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
                                      happenedAt: happenedAt, visibility: visibility,
                                      place: place, evidenceDatas: photoDatas, authorID: authorID)
        case .edit(let entry):
            try? repo.updateEntry(entry, category: category, title: trimmedTitle,
                                  detail: trimmedDetail.isEmpty ? nil : trimmedDetail,
                                  happenedAt: happenedAt, place: place)
            for evidence in evidencesToDelete { try? repo.deleteEvidence(evidence) }
            if !photoDatas.isEmpty { try? repo.addEvidences(entry, datas: photoDatas) }
            // 编辑私密条目改公开 = 等效公开动作（spec §六，触发对方通知）
            if !visibilityLocked, visibility == .sharedImmediately,
               entry.visibilityRaw == EntryVisibility.privateUntilRevealed.rawValue {
                try? repo.reveal(entry, at: Date())
            }
        }
        dismiss()
    }
}
