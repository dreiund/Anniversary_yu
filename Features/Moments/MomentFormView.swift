import SwiftUI
import PhotosUI
import CoreData

enum MomentFormMode {
    case create(CDMeeting)
    case edit(CDMoment)
}

struct MomentFormView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    let mode: MomentFormMode

    @State private var type: MomentType = .restaurant
    @State private var title = ""
    @State private var bodyText = ""
    @State private var happenedAt = Date()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []
    @State private var stars = 0
    @State private var moodEmoji: String?
    @State private var comment = ""
    @State private var locationName = ""
    @State private var coords: (Double, Double)?
    @State private var locationCategoryRaw: Int16 = 0
    @State private var linkedPlaceID: UUID?
    @State private var staleDay: CDDateDay?
    @State private var backfillSeal: BackfillSealTarget?
    @State private var showPlacePicker = false
    @State private var existingPhotos: [CDPhoto] = []
    @State private var photosToDelete: [CDPhoto] = []
    @State private var loadedPlaceSignature = ""

    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var placeSignature: String {
        "\(locationName.trimmingCharacters(in: .whitespaces))|\(coords?.0 ?? 0)|\(coords?.1 ?? 0)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    typeChips
                    photoSection
                    fieldsSection
                    if !isEdit { evaluationSection }
                    locationSection
                }
                .padding(DS.Spacing.md)
            }
            .background(DS.parchment)
            .navigationTitle(isEdit ? "编辑记忆" : "新的记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存储") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { loadIfEditing() }
            .onChange(of: pickerItems) { _, items in
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
            .sheet(item: $staleDay) { day in
                StaleSealSheet(day: day) { sealTime in
                    if case let .create(meeting) = mode {
                        try? MeetingRepository(context: context).sealOpenDay(in: meeting, at: sealTime)
                        doCreate(in: meeting)
                    }
                }
            }
            .sheet(item: $backfillSeal) { target in
                BackfillSealSheet(day: target.id) { sealAt in
                    backfillSeal = nil
                    if case let .create(meeting) = mode {
                        doCreate(in: meeting, sealNewPastDayAt: sealAt)
                    }
                }
            }
            .sheet(isPresented: $showPlacePicker) {
                PlacePickerSheet(initial: coords.map {
                    PickedPlace(name: locationName, latitude: $0.0, longitude: $0.1,
                                categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
                } ?? (locationName.isEmpty ? nil : PickedPlace(name: locationName, latitude: 0, longitude: 0,
                                                                categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID))) { picked in
                    locationName = picked.name
                    coords = (picked.latitude, picked.longitude)
                    locationCategoryRaw = picked.categoryRaw
                    linkedPlaceID = picked.existingPlaceID
                }
            }
        }
    }

    private var typeChips: some View {
        HStack(spacing: 6) {
            ForEach(MomentType.allCases, id: \.rawValue) { t in
                SelectableChip(title: t.title, isSelected: type == t) { type = t }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 9, matching: .images) {
                Text(photoDatas.isEmpty ? (isEdit ? "追加照片" : "选择照片") : "已选 \(photoDatas.count) 张")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.actionBlue)
            }
            if isEdit && !existingPhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(existingPhotos, id: \.objectID) { photo in
                            if let thumb = photo.thumbnailData, let ui = UIImage(data: thumb) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                                    .opacity(photosToDelete.contains(photo) ? 0.3 : 1)
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            if let i = photosToDelete.firstIndex(of: photo) {
                                                photosToDelete.remove(at: i)
                                            } else {
                                                photosToDelete.append(photo)
                                            }
                                        } label: {
                                            Image(systemName: photosToDelete.contains(photo)
                                                  ? "arrow.uturn.backward.circle.fill" : "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundStyle(.white, DS.ink.opacity(0.55))
                                        }
                                        .padding(3)
                                    }
                            }
                        }
                    }
                }
                if !photosToDelete.isEmpty {
                    Text("已标记删除 \(photosToDelete.count) 张 · 保存后生效").dsFootnote()
                }
            }
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.image))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var fieldsSection: some View {
        GroupedSection {
            HStack {
                Text("标题").dsBody()
                TextField("如 蟹家大院", text: $title).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            DatePicker("时刻", selection: $happenedAt)
                .padding(.horizontal, 14).padding(.vertical, 6)
            DS.hairline.frame(height: 1).padding(.leading, 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("正文 · 共同记事（可选）").dsFootnote()
                TextField("发生了什么…", text: $bodyText, axis: .vertical)
                    .lineLimit(3...6)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
        }
    }

    private var evaluationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("你的评价").dsFootnote()
            StarInputView(stars: $stars)
            EmojiPickerRow(selection: $moodEmoji)
            TextField("短评：一句话点评（可选）", text: $comment)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.image).fill(DS.parchment))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.canvas))
    }

    private var locationSection: some View {
        GroupedSection {
            HStack {
                Text("地点").dsBody()
                TextField("可手输或选点", text: $locationName).multilineTextAlignment(.trailing)
                if !locationName.isEmpty || coords != nil {
                    Button("清除") {
                        locationName = ""
                        coords = nil
                        locationCategoryRaw = 0
                        linkedPlaceID = nil
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.inkMuted)
                }
                Button("选地点") { showPlacePicker = true }
                    .font(.system(size: 14))
                    .foregroundStyle(DS.actionBlue)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            if coords != nil {
                Text("已带坐标 · 换店请重新选点")
                    .dsFootnote()
                    .padding(.horizontal, 14).padding(.bottom, 9)
            }
        }
    }

    private func loadIfEditing() {
        guard case let .edit(moment) = mode else { return }
        type = MomentType(rawValue: moment.typeRaw) ?? .other
        title = moment.title ?? ""
        bodyText = moment.body ?? ""
        happenedAt = moment.happenedAt ?? Date()
        existingPhotos = MomentRepository(context: context).photosSorted(moment)
        locationName = moment.place?.name ?? ""
        if let place = moment.place, place.latitude != 0 || place.longitude != 0 {
            coords = (place.latitude, place.longitude)
        }
        locationCategoryRaw = moment.place?.categoryRaw ?? 0
        linkedPlaceID = moment.place?.id
        loadedPlaceSignature = placeSignature
    }

    private func save() {
        switch mode {
        case let .edit(moment):
            let repo = MomentRepository(context: context)
            try? repo.update(moment, type: type, title: title,
                             body: bodyText.isEmpty ? nil : bodyText, happenedAt: happenedAt)
            for photo in photosToDelete { try? repo.deletePhoto(photo) }
            if !photoDatas.isEmpty { try? repo.addPhotos(moment, datas: photoDatas) }
            applyPlaceChangeIfNeeded(to: moment, repo: repo)
            dismiss()
        case let .create(meeting):
            let meetingRepo = MeetingRepository(context: context)
            let stale = (try? meetingRepo.staleOpenDay(in: meeting, now: Date(), recordAt: happenedAt)) ?? nil
            if let stale {
                staleDay = stale
                return
            }
            // 反馈④：补录要新开过去的天 → 先选那天的收尾时刻，不再默认 23:59
            if meetingRepo.wouldOpenNewPastDay(in: meeting, at: happenedAt) {
                backfillSeal = BackfillSealTarget(id: happenedAt)
                return
            }
            doCreate(in: meeting)
        }
    }

    private func doCreate(in meeting: CDMeeting, sealNewPastDayAt: Date? = nil) {
        let couples = CoupleRepository(context: context)
        let couple = try? couples.fetchCouple()
        let authorID = couple.flatMap { couples.currentPartnerID(of: $0) }

        var place: CDPlace?
        if !locationName.trimmingCharacters(in: .whitespaces).isEmpty, let couple {
            let picked = PickedPlace(name: locationName.trimmingCharacters(in: .whitespaces),
                                     latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                     categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
            place = PlaceResolver.resolve(picked, context: context, couple: couple)
        }

        let evaluation = stars > 0 || moodEmoji != nil || !comment.isEmpty
            ? NewEvaluation(stars: Int16(stars), moodEmoji: moodEmoji,
                            comment: comment.isEmpty ? nil : comment)
            : nil

        _ = try? MomentRepository(context: context).create(
            in: meeting, type: type, title: title,
            body: bodyText.isEmpty ? nil : bodyText,
            happenedAt: happenedAt, photoDatas: photoDatas,
            myEvaluation: evaluation, authorID: authorID, place: place,
            sealNewPastDayAt: sealNewPastDayAt)
        SealReminder.refresh(context: context)
        dismiss()
    }

    /// 地点签名变了才动关系：清空→setPlace(nil)；有值→关联既有或新建 CDPlace（PlaceResolver.resolve，六字段纪律）。
    /// 旧 CDPlace 不删（可能被其他记忆引用）。
    private func applyPlaceChangeIfNeeded(to moment: CDMoment, repo: MomentRepository) {
        guard placeSignature != loadedPlaceSignature else { return }
        let trimmed = locationName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            try? repo.setPlace(moment, place: nil)
            return
        }
        let couples = CoupleRepository(context: context)
        guard let couple = try? couples.fetchCouple() else { return }
        let picked = PickedPlace(name: trimmed, latitude: coords?.0 ?? 0, longitude: coords?.1 ?? 0,
                                 categoryRaw: locationCategoryRaw, existingPlaceID: linkedPlaceID)
        guard let place = PlaceResolver.resolve(picked, context: context, couple: couple) else { return }
        try? repo.setPlace(moment, place: place)
    }
}

extension CDDateDay: Identifiable {}

/// 补录待选收尾时刻的目标日（sheet item）
struct BackfillSealTarget: Identifiable {
    let id: Date
}
